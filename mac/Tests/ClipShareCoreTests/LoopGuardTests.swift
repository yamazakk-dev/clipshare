import XCTest
import ClipShareCore

final class LoopGuardTests: XCTestCase {
    private let fiveMegabytes = 5 * 1024 * 1024

    func testTextCanBeSentBeforeAnythingIsReceived() {
        XCTAssertTrue(LoopGuard().shouldSend("local text"))
    }

    func testReceivedTextIsNotSentBack() {
        let guardUnderTest = LoopGuard()

        guardUnderTest.recordReceived("remote text")

        XCTAssertFalse(guardUnderTest.shouldSend("remote text"))
    }

    func testReceivedTextIsOnlySuppressedOnce() {
        let guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("remote text")

        XCTAssertFalse(guardUnderTest.shouldSend("remote text"))
        XCTAssertTrue(guardUnderTest.shouldSend("remote text"))
    }

    func testDifferentTextCanBeSent() {
        let guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("remote text")

        XCTAssertTrue(guardUnderTest.shouldSend("different local text"))
    }

    func testOnlyMostRecentlyReceivedTextIsSuppressed() {
        let guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("first")
        guardUnderTest.recordReceived("second")

        XCTAssertTrue(guardUnderTest.shouldSend("first"))
        XCTAssertFalse(guardUnderTest.shouldSend("second"))
    }

    func testExactlyFiveMegabytesCanBeSent() {
        let text = String(repeating: "a", count: fiveMegabytes)

        XCTAssertTrue(LoopGuard().shouldSend(text))
    }

    func testMoreThanFiveMegabytesCannotBeSent() {
        let text = String(repeating: "a", count: fiveMegabytes + 1)

        XCTAssertFalse(LoopGuard().shouldSend(text))
    }

    func testSizeLimitCountsUTF8Bytes() {
        let text = String(repeating: "é", count: (fiveMegabytes / 2) + 1)

        XCTAssertFalse(LoopGuard().shouldSend(text))
    }
}
