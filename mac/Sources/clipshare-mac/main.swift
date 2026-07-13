import AppKit
import ClipShareCore
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let loopGuard = LoopGuard()

    private var pasteboardWatcher: PasteboardWatcher?
    private var server: ClipServer?
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusMenuController = StatusMenuController(settings: settings)
        let pasteboardWatcher = PasteboardWatcher()
        let server = ClipServer(
            port: settings.port,
            token: settings.token,
            callbackQueue: .main
        )

        self.statusMenuController = statusMenuController
        self.pasteboardWatcher = pasteboardWatcher
        self.server = server

        pasteboardWatcher.onChange = { [weak self] text in
            guard let self,
                  settings.isSyncEnabled,
                  loopGuard.shouldSend(text) else {
                return
            }
            server.broadcast(text: text)
        }

        server.onClipReceived = { [weak self] text in
            guard let self, settings.isSyncEnabled else {
                return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                print("ClipShare: failed to write received text to the pasteboard")
                return
            }
            loopGuard.recordReceived(text)
            statusMenuController.updateLastSyncedText(text)
        }

        server.onStateChange = { isConnected in
            statusMenuController.updateConnectionState(isConnected: isConnected)
        }

        do {
            try server.start()
            print("ClipShare: listening on port \(settings.port)")
        } catch {
            print("ClipShare: failed to start server on port \(settings.port): \(error)")
        }

        pasteboardWatcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pasteboardWatcher?.stop()
        server?.stop()
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
NSApp.setActivationPolicy(.accessory)
application.delegate = appDelegate
withExtendedLifetime(appDelegate) {
    application.run()
}
