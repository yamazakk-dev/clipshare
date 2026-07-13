import CryptoKit
import Foundation

public final class LoopGuard {
    private static let maximumTextByteCount = 5 * 1024 * 1024

    private let lock = NSLock()
    private var lastReceivedHash: SHA256.Digest?

    public init() {}

    public func recordReceived(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        lastReceivedHash = hash(text)
    }

    public func shouldSend(_ text: String) -> Bool {
        guard text.utf8.count <= Self.maximumTextByteCount else {
            return false
        }

        let textHash = hash(text)

        lock.lock()
        defer { lock.unlock() }

        guard textHash == lastReceivedHash else {
            return true
        }

        lastReceivedHash = nil
        return false
    }

    private func hash(_ text: String) -> SHA256.Digest {
        SHA256.hash(data: Data(text.utf8))
    }
}
