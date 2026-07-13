import AppKit
import Foundation

final class StatusMenuController: NSObject {
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private let connectionItem = NSMenuItem(title: "接続状態: 未接続", action: nil, keyEquivalent: "")
    private let syncItem = NSMenuItem(title: "同期", action: nil, keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "最終同期: なし", action: nil, keyEquivalent: "")
    private let tokenItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(settings: AppSettings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configureMenu()
    }

    func updateConnectionState(isConnected: Bool) {
        connectionItem.title = isConnected
            ? "接続状態: 接続中"
            : "接続状態: 未接続"
    }

    func updateLastSyncedText(_ text: String) {
        let singleLineText = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let preview = String(singleLineText.prefix(50))
        let suffix = singleLineText.count > 50 ? "…" : ""
        previewItem.title = "最終同期: \(preview)\(suffix)"
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipShare"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "ClipShare"
        }
        button.toolTip = "ClipShare"
    }

    private func configureMenu() {
        let menu = NSMenu()

        connectionItem.isEnabled = false
        menu.addItem(connectionItem)

        syncItem.target = self
        syncItem.action = #selector(toggleSync(_:))
        syncItem.state = settings.isSyncEnabled ? .on : .off
        menu.addItem(syncItem)

        previewItem.isEnabled = false
        menu.addItem(previewItem)

        tokenItem.title = "トークンをコピー: \(settings.token)"
        tokenItem.target = self
        tokenItem.action = #selector(copyToken(_:))
        menu.addItem(tokenItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "終了",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleSync(_ sender: NSMenuItem) {
        settings.isSyncEnabled.toggle()
        sender.state = settings.isSyncEnabled ? .on : .off
    }

    @objc private func copyToken(_ sender: NSMenuItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(settings.token, forType: .string)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
