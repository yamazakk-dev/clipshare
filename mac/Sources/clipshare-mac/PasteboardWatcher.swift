import AppKit
import Foundation

final class PasteboardWatcher {
    var onChange: ((String) -> Void)?

    private let pasteboard: NSPasteboard
    private let pollingInterval: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?

    init(
        pasteboard: NSPasteboard = .general,
        pollingInterval: TimeInterval = 0.5
    ) {
        self.pasteboard = pasteboard
        self.pollingInterval = pollingInterval
        lastChangeCount = pasteboard.changeCount
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount
        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        onChange?(text)
    }
}
