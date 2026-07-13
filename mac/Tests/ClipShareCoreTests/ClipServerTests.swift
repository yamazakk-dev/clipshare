import Foundation
import XCTest
@testable import ClipShareCore

final class ClipServerTests: XCTestCase {
    func testCorrectTokenReceivesAuthOk() async throws {
        let server = try startedServer()
        let client = try makeClient(for: server)
        defer {
            client.close()
            server.stop()
        }

        try client.connect()
        try await client.send(.auth(token: "correct-token", deviceId: .android))

        let response = try client.receive()
        XCTAssertEqual(response, .authOk)
    }

    func testWrongTokenDisconnects() async throws {
        let server = try startedServer()
        let client = try makeClient(for: server)
        defer {
            client.close()
            server.stop()
        }

        try client.connect()
        try await client.send(.auth(token: "wrong-token", deviceId: .android))

        assertConnectionCloses(client, expectedCode: .policyViolation)
    }

    func testClipBeforeAuthenticationDisconnects() async throws {
        let server = try startedServer()
        let client = try makeClient(for: server)
        defer {
            client.close()
            server.stop()
        }

        try client.connect()
        try await client.send(.clip(text: "too early", deviceId: .android, ts: 123))

        assertConnectionCloses(client, expectedCode: .policyViolation)
    }

    func testConnectionWithoutAuthenticationTimesOut() async throws {
        let server = ClipServer(
            port: 0,
            token: "correct-token",
            authenticationTimeout: 0.1
        )
        try server.start()
        let client = try makeClient(for: server)
        defer {
            client.close()
            server.stop()
        }

        try client.connect()

        assertConnectionCloses(client, expectedCode: .policyViolation)
    }

    func testAuthenticatedClipAndBroadcastRoundTrip() async throws {
        let server = try startedServer()
        let client = try makeClient(for: server)
        let receivedClip = expectation(description: "Server receives client clip")
        let connected = expectation(description: "Server reports authenticated connection")
        let disconnected = expectation(description: "Server reports client disconnect")
        server.onClipReceived = { text in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(text, "from Android")
            receivedClip.fulfill()
        }
        server.onStateChange = { isConnected in
            XCTAssertTrue(Thread.isMainThread)
            if isConnected {
                connected.fulfill()
            } else {
                disconnected.fulfill()
            }
        }
        defer {
            client.close()
            server.stop()
        }

        try client.connect()
        try await client.send(.auth(token: "correct-token", deviceId: .android))
        let authResponse = try client.receive()
        XCTAssertEqual(authResponse, .authOk)
        await fulfillment(of: [connected], timeout: 2)

        try await client.send(
            .clip(text: "from Android", deviceId: .android, ts: 123)
        )
        await fulfillment(of: [receivedClip], timeout: 2)

        server.broadcast(text: "from Mac")
        guard case let .clip(text, deviceId, ts) = try client.receive() else {
            return XCTFail("Expected a clip broadcast")
        }
        XCTAssertEqual(text, "from Mac")
        XCTAssertEqual(deviceId, .mac)
        XCTAssertLessThanOrEqual(abs(ts - Int(Date().timeIntervalSince1970)), 2)

        client.close()
        await fulfillment(of: [disconnected], timeout: 2)
    }

    func testBroadcastReachesAllAuthenticatedClients() async throws {
        let server = try startedServer()
        let firstClient = try makeClient(for: server)
        let secondClient = try makeClient(for: server)
        defer {
            firstClient.close()
            secondClient.close()
            server.stop()
        }

        try firstClient.connect()
        try secondClient.connect()
        try await firstClient.send(
            .auth(token: "correct-token", deviceId: .android)
        )
        try await secondClient.send(
            .auth(token: "correct-token", deviceId: .android)
        )
        let firstAuthResponse = try firstClient.receive()
        let secondAuthResponse = try secondClient.receive()
        XCTAssertEqual(firstAuthResponse, .authOk)
        XCTAssertEqual(secondAuthResponse, .authOk)

        server.broadcast(text: "to every client")

        let firstBroadcast = try firstClient.receive()
        let secondBroadcast = try secondClient.receive()
        XCTAssertEqual(broadcastText(firstBroadcast), "to every client")
        XCTAssertEqual(broadcastText(secondBroadcast), "to every client")
    }

    func testSecondAuthenticationMessageDisconnects() async throws {
        let server = try startedServer()
        let client = try makeClient(for: server)
        defer {
            client.close()
            server.stop()
        }

        try client.connect()
        try await client.send(.auth(token: "correct-token", deviceId: .android))
        XCTAssertEqual(try client.receive(), .authOk)

        try await client.send(.auth(token: "correct-token", deviceId: .android))

        assertConnectionCloses(client, expectedCode: .protocolError)
    }

    func testBroadcastDoesNotReachUnauthenticatedClient() async throws {
        let server = try startedServer()
        let authenticatedClient = try makeClient(for: server)
        let unauthenticatedClient = try makeClient(for: server)
        defer {
            authenticatedClient.close()
            unauthenticatedClient.close()
            server.stop()
        }

        try authenticatedClient.connect()
        try unauthenticatedClient.connect()
        try await authenticatedClient.send(
            .auth(token: "correct-token", deviceId: .android)
        )
        XCTAssertEqual(try authenticatedClient.receive(), .authOk)

        server.broadcast(text: "authenticated only")

        XCTAssertEqual(
            broadcastText(try authenticatedClient.receive()),
            "authenticated only"
        )
        XCTAssertThrowsError(try unauthenticatedClient.receive(timeout: 0.25)) { error in
            guard case WebSocketClientError.receiveTimedOut = error else {
                return XCTFail("Expected receive timeout, got \(error)")
            }
        }
    }

    func testStartThrowsWhenPortIsAlreadyInUse() throws {
        let runningServer = try startedServer()
        defer { runningServer.stop() }

        let conflictingServer = ClipServer(
            port: try XCTUnwrap(runningServer.actualPort),
            token: "other-token"
        )
        defer { conflictingServer.stop() }

        XCTAssertThrowsError(try conflictingServer.start()) { error in
            guard case ClipServerError.listenerFailed = error else {
                return XCTFail("Expected listener failure, got \(error)")
            }
        }
    }

    func testCallbacksUseConfiguredQueue() async throws {
        let callbackQueue = DispatchQueue(label: "ClipServerTests.callback")
        let callbackQueueKey = DispatchSpecificKey<Void>()
        callbackQueue.setSpecific(key: callbackQueueKey, value: ())
        let server = ClipServer(
            port: 0,
            token: "correct-token",
            callbackQueue: callbackQueue
        )
        try server.start()
        let client = try makeClient(for: server)
        let connected = expectation(description: "State callback uses configured queue")
        let receivedClip = expectation(description: "Clip callback uses configured queue")
        server.onStateChange = { isConnected in
            guard isConnected else {
                return
            }
            XCTAssertNotNil(DispatchQueue.getSpecific(key: callbackQueueKey))
            connected.fulfill()
        }
        server.onClipReceived = { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: callbackQueueKey))
            receivedClip.fulfill()
        }
        defer {
            client.close()
            server.stop()
        }

        try client.connect()
        try await client.send(.auth(token: "correct-token", deviceId: .android))
        XCTAssertEqual(try client.receive(), .authOk)
        try await client.send(.clip(text: "callback", deviceId: .android, ts: 123))

        await fulfillment(of: [connected, receivedClip], timeout: 2)
    }

    private func startedServer() throws -> ClipServer {
        let server = ClipServer(port: 0, token: "correct-token")
        try server.start()
        return server
    }

    private func makeClient(for server: ClipServer) throws -> WebSocketClient {
        WebSocketClient(port: try XCTUnwrap(server.actualPort))
    }

    private func broadcastText(_ message: ClipMessage?) -> String? {
        guard case let .clip(text, deviceId, _) = message,
              deviceId == .mac else {
            return nil
        }
        return text
    }

    private func assertConnectionCloses(
        _ client: WebSocketClient,
        expectedCode: URLSessionWebSocketTask.CloseCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let closeCode = try client.waitForClose(timeout: 2)
            XCTAssertEqual(closeCode, expectedCode, file: file, line: line)
        } catch {
            XCTFail("Expected close code \(expectedCode), got \(error)", file: file, line: line)
        }
    }
}

private enum WebSocketClientError: Error {
    case connectionTimedOut
    case closedBeforeOpening
    case closeTimedOut
    case receiveTimedOut
}

private final class OneShotResult<Value> {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return false
        }
        self.result = result
        lock.unlock()
        semaphore.signal()
        return true
    }

    func wait(timeout: TimeInterval, timeoutError: Error) throws -> Value {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw timeoutError
        }

        lock.lock()
        defer { lock.unlock() }
        return try result!.get()
    }
}

private final class WebSocketClientDelegate: NSObject, URLSessionWebSocketDelegate {
    private let opened = OneShotResult<Void>()
    private let closed = OneShotResult<URLSessionWebSocketTask.CloseCode>()

    func waitUntilOpen(timeout: TimeInterval) throws {
        try opened.wait(
            timeout: timeout,
            timeoutError: WebSocketClientError.connectionTimedOut
        )
    }

    func waitForClose(timeout: TimeInterval) throws -> URLSessionWebSocketTask.CloseCode {
        try closed.wait(
            timeout: timeout,
            timeoutError: WebSocketClientError.closeTimedOut
        )
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        opened.resolve(.success(()))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        opened.resolve(.failure(WebSocketClientError.closedBeforeOpening))
        closed.resolve(.success(closeCode))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }
        opened.resolve(.failure(error))
        closed.resolve(.failure(error))
    }
}

private final class WebSocketClient {
    private let url: URL
    private let delegate = WebSocketClientDelegate()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        return URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }()
    private lazy var task = session.webSocketTask(with: url)

    init(port: UInt16) {
        url = URL(string: "ws://127.0.0.1:\(port)")!
    }

    func connect(timeout: TimeInterval = 2) throws {
        task.resume()
        try delegate.waitUntilOpen(timeout: timeout)
    }

    func send(_ message: ClipMessage) async throws {
        try await task.send(.string(message.encode()))
    }

    func receive(timeout: TimeInterval = 2) throws -> ClipMessage? {
        guard case let .string(json) = try receiveRaw(timeout: timeout) else {
            return nil
        }
        return ClipMessage.decode(json)
    }

    func receiveRaw(
        timeout: TimeInterval = 2
    ) throws -> URLSessionWebSocketTask.Message {
        let result = OneShotResult<URLSessionWebSocketTask.Message>()
        task.receive { receiveResult in
            result.resolve(receiveResult)
        }
        return try result.wait(
            timeout: timeout,
            timeoutError: WebSocketClientError.receiveTimedOut
        )
    }

    func waitForClose(timeout: TimeInterval) throws -> URLSessionWebSocketTask.CloseCode {
        task.receive { _ in }
        return try delegate.waitForClose(timeout: timeout)
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
