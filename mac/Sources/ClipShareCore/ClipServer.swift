import Foundation
import Network

public enum ClipServerError: Error {
    case startupTimedOut
    case listenerFailed(NWError)
    case listenerCancelled
    case actualPortUnavailable
}

public final class ClipServer {
    public var onClipReceived: ((String) -> Void)? {
        get { performSync { clipReceivedHandler } }
        set { performSync { clipReceivedHandler = newValue } }
    }

    public var onStateChange: ((Bool) -> Void)? {
        get { performSync { stateChangeHandler } }
        set { performSync { stateChangeHandler = newValue } }
    }

    private final class Client {
        let connection: NWConnection
        var authenticationTimeoutWorkItem: DispatchWorkItem?
        var isAuthenticated = false
        var isReceiving = false

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private final class StartupWaiter {
        private let group = DispatchGroup()
        private let lock = NSLock()
        private var result: Result<Void, Error>?

        init() {
            group.enter()
        }

        @discardableResult
        func resolve(_ result: Result<Void, Error>) -> Bool {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return false
            }
            self.result = result
            lock.unlock()
            group.leave()
            return true
        }

        func wait(timeout: TimeInterval) -> Result<Void, Error> {
            if group.wait(timeout: .now() + timeout) == .timedOut {
                resolve(.failure(ClipServerError.startupTimedOut))
            }

            lock.lock()
            defer { lock.unlock() }
            return result ?? .failure(ClipServerError.startupTimedOut)
        }
    }

    private let port: UInt16
    private let token: String
    private let authenticationTimeout: TimeInterval
    private let callbackQueue: DispatchQueue
    private let queue = DispatchQueue(label: "com.ymac.clipshare.server")
    private let queueKey = DispatchSpecificKey<Void>()

    private var listener: NWListener?
    private var startupWaiter: StartupWaiter?
    private var actualPortStorage: UInt16?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var clipReceivedHandler: ((String) -> Void)?
    private var stateChangeHandler: ((Bool) -> Void)?

    public var actualPort: UInt16? {
        performSync { actualPortStorage }
    }

    public convenience init(
        port: UInt16,
        token: String,
        callbackQueue: DispatchQueue = .main
    ) {
        self.init(
            port: port,
            token: token,
            authenticationTimeout: 5,
            callbackQueue: callbackQueue
        )
    }

    init(
        port: UInt16,
        token: String,
        authenticationTimeout: TimeInterval,
        callbackQueue: DispatchQueue = .main
    ) {
        self.port = port
        self.token = token
        self.authenticationTimeout = authenticationTimeout
        self.callbackQueue = callbackQueue
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        listener?.cancel()
        clients.values.forEach { $0.connection.cancel() }
    }

    public func start() throws {
        let startup: (waiter: StartupWaiter, listenerID: ObjectIdentifier)? = try performSync {
            if let listener {
                guard let startupWaiter else {
                    return nil
                }
                return (startupWaiter, ObjectIdentifier(listener))
            }

            let startupWaiter = StartupWaiter()

            let webSocketOptions = NWProtocolWebSocket.Options()
            webSocketOptions.autoReplyPing = true
            webSocketOptions.setClientRequestHandler(queue) { _, _ in
                NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
            }

            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(
                webSocketOptions,
                at: 0
            )

            let requestedPort = port == 0
                ? NWEndpoint.Port.any
                : NWEndpoint.Port(rawValue: port)!
            let listener = try NWListener(using: parameters, on: requestedPort)
            let listenerID = ObjectIdentifier(listener)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(
                    state,
                    listenerID: listenerID,
                    startupWaiter: startupWaiter
                )
            }

            self.listener = listener
            self.startupWaiter = startupWaiter
            actualPortStorage = nil
            listener.start(queue: queue)
            return (startupWaiter, listenerID)
        }

        guard let startup else {
            return
        }

        let result = startup.waiter.wait(timeout: 5)
        if case .failure = result {
            performSync {
                guard let listener,
                      ObjectIdentifier(listener) == startup.listenerID else {
                    return
                }
                stopInternal(notifyIfConnected: false)
            }
        }
        performSync {
            if self.startupWaiter === startup.waiter {
                self.startupWaiter = nil
            }
        }
        try result.get()
    }

    public func stop() {
        performSync {
            stopInternal(notifyIfConnected: true)
        }
    }

    public func broadcast(text: String) {
        performAsync { [weak self] in
            guard let self else {
                return
            }

            let message = ClipMessage.clip(
                text: text,
                deviceId: .mac,
                ts: Int(Date().timeIntervalSince1970)
            )
            let recipients = clients.compactMap { clientID, client in
                client.isAuthenticated ? (clientID, client.connection) : nil
            }
            for (clientID, connection) in recipients {
                send(message, to: clientID, connection: connection)
            }
        }
    }

    private var hasAuthenticatedClients: Bool {
        clients.values.contains(where: \.isAuthenticated)
    }

    private func accept(_ connection: NWConnection) {
        let clientID = ObjectIdentifier(connection)
        let client = Client(connection: connection)
        clients[clientID] = client

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, clientID: clientID)
        }
        connection.start(queue: queue)

        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  let client = clients[clientID],
                  !client.isAuthenticated else {
                return
            }
            disconnect(clientID, closeCode: .policyViolation)
        }
        client.authenticationTimeoutWorkItem = timeout
        queue.asyncAfter(
            deadline: .now() + authenticationTimeout,
            execute: timeout
        )
    }

    private func handleListenerState(
        _ state: NWListener.State,
        listenerID: ObjectIdentifier,
        startupWaiter: StartupWaiter
    ) {
        guard let listener,
              ObjectIdentifier(listener) == listenerID else {
            return
        }

        switch state {
        case .ready:
            guard let port = listener.port else {
                startupWaiter.resolve(.failure(ClipServerError.actualPortUnavailable))
                stopInternal(notifyIfConnected: false)
                return
            }
            actualPortStorage = port.rawValue
            startupWaiter.resolve(.success(()))

        case let .failed(error):
            let failedDuringStartup = startupWaiter.resolve(
                .failure(ClipServerError.listenerFailed(error))
            )
            if !failedDuringStartup {
                notifyStateChange(false)
            }
            stopInternal(notifyIfConnected: false)

        case .cancelled:
            startupWaiter.resolve(.failure(ClipServerError.listenerCancelled))

        default:
            break
        }
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        clientID: ObjectIdentifier
    ) {
        switch state {
        case .ready:
            guard let client = clients[clientID], !client.isReceiving else {
                return
            }
            client.isReceiving = true
            receiveNextMessage(from: clientID)

        case .failed, .cancelled:
            removeClient(clientID, cancelConnection: false)

        default:
            break
        }
    }

    private func receiveNextMessage(from clientID: ObjectIdentifier) {
        guard let client = clients[clientID] else {
            return
        }

        client.connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self else {
                return
            }
            guard error == nil else {
                removeClient(clientID, cancelConnection: true)
                return
            }
            guard clients[clientID] != nil,
                  let metadata = context?.protocolMetadata(
                    definition: NWProtocolWebSocket.definition
                  ) as? NWProtocolWebSocket.Metadata else {
                disconnect(clientID, closeCode: .protocolError)
                return
            }

            switch metadata.opcode {
            case .text:
                guard isComplete,
                      let content,
                      let json = String(data: content, encoding: .utf8),
                      let message = ClipMessage.decode(json) else {
                    disconnect(clientID, closeCode: .invalidFramePayloadData)
                    return
                }
                handle(message, from: clientID)

            case .ping, .pong:
                receiveNextMessage(from: clientID)

            case .close:
                removeClient(clientID, cancelConnection: true)

            default:
                disconnect(clientID, closeCode: .unsupportedData)
            }
        }
    }

    private func handle(_ message: ClipMessage, from clientID: ObjectIdentifier) {
        guard let client = clients[clientID] else {
            return
        }

        if !client.isAuthenticated {
            guard case let .auth(receivedToken, deviceId) = message,
                  receivedToken == token,
                  deviceId == .android else {
                disconnect(clientID, closeCode: .policyViolation)
                return
            }

            let wasConnected = hasAuthenticatedClients
            client.isAuthenticated = true
            client.authenticationTimeoutWorkItem?.cancel()
            client.authenticationTimeoutWorkItem = nil

            if !wasConnected {
                notifyStateChange(true)
            }

            send(.authOk, to: clientID, connection: client.connection)
            receiveNextMessage(from: clientID)
            return
        }

        guard case let .clip(text, _, _) = message else {
            disconnect(clientID, closeCode: .protocolError)
            return
        }

        notifyClipReceived(text)
        receiveNextMessage(from: clientID)
    }

    private func send(
        _ message: ClipMessage,
        to clientID: ObjectIdentifier,
        connection: NWConnection
    ) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "clipshare.websocket.text",
            metadata: [metadata]
        )
        connection.send(
            content: Data(message.encode().utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard error != nil else {
                    return
                }
                self?.removeClient(clientID, cancelConnection: true)
            }
        )
    }

    private func disconnect(
        _ clientID: ObjectIdentifier,
        closeCode: NWProtocolWebSocket.CloseCode.Defined
    ) {
        guard let client = clients[clientID] else {
            return
        }

        let connection = client.connection
        removeClient(clientID, cancelConnection: false)

        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = .protocolCode(closeCode)
        let context = NWConnection.ContentContext(
            identifier: "clipshare.websocket.close",
            metadata: [metadata]
        )
        connection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if error != nil {
                    connection.cancel()
                }
            }
        )
        queue.asyncAfter(deadline: .now() + 0.5) {
            connection.cancel()
        }
    }

    private func removeClient(
        _ clientID: ObjectIdentifier,
        cancelConnection: Bool
    ) {
        let wasConnected = hasAuthenticatedClients
        guard let client = clients.removeValue(forKey: clientID) else {
            return
        }

        client.authenticationTimeoutWorkItem?.cancel()
        client.connection.stateUpdateHandler = nil
        if cancelConnection {
            client.connection.cancel()
        }

        if wasConnected && !hasAuthenticatedClients {
            notifyStateChange(false)
        }
    }

    private func stopInternal(notifyIfConnected: Bool) {
        let wasConnected = hasAuthenticatedClients

        startupWaiter?.resolve(.failure(ClipServerError.listenerCancelled))
        startupWaiter = nil
        actualPortStorage = nil

        if let listener {
            self.listener = nil
            listener.newConnectionHandler = nil
            listener.stateUpdateHandler = nil
            listener.cancel()
        }

        let existingClients = Array(clients.values)
        clients.removeAll()
        existingClients.forEach { client in
            client.authenticationTimeoutWorkItem?.cancel()
            client.connection.stateUpdateHandler = nil
            client.connection.cancel()
        }

        if notifyIfConnected && wasConnected {
            notifyStateChange(false)
        }
    }

    private func notifyStateChange(_ isConnected: Bool) {
        guard let handler = stateChangeHandler else {
            return
        }
        callbackQueue.async {
            handler(isConnected)
        }
    }

    private func notifyClipReceived(_ text: String) {
        guard let handler = clipReceivedHandler else {
            return
        }
        callbackQueue.async {
            handler(text)
        }
    }

    private func performSync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    private func performAsync(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.async(execute: work)
        }
    }
}
