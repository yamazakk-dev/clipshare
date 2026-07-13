import Foundation
import XCTest
import ClipShareCore

final class ClipMessageTests: XCTestCase {
    func testAuthEncodeDecodeRoundTrip() {
        assertRoundTrip(.auth(token: "shared-token", deviceId: .android))
    }

    func testAuthOkEncodeDecodeRoundTrip() {
        assertRoundTrip(.authOk)
    }

    func testClipEncodeDecodeRoundTrip() {
        assertRoundTrip(
            .clip(
                text: "改行や引用符も同期する\n\"ClipShare\"",
                deviceId: .mac,
                ts: 1_752_400_000
            )
        )
    }

    func testEncodedClipUsesProtocolFieldNames() throws {
        let message = ClipMessage.clip(text: "hello", deviceId: .mac, ts: 123)
        let object = try decodedJSONObject(message.encode())

        XCTAssertEqual(object["type"] as? String, "clip")
        XCTAssertEqual(object["text"] as? String, "hello")
        XCTAssertEqual(object["deviceId"] as? String, "mac")
        XCTAssertEqual(object["ts"] as? Int, 123)
    }

    func testEncodedAuthUsesProtocolFieldNames() throws {
        let message = ClipMessage.auth(token: "secret", deviceId: .android)
        let object = try decodedJSONObject(message.encode())

        XCTAssertEqual(object["type"] as? String, "auth")
        XCTAssertEqual(object["token"] as? String, "secret")
        XCTAssertEqual(object["deviceId"] as? String, "android")
    }

    func testEncodedAuthOkUsesProtocolType() throws {
        let object = try decodedJSONObject(ClipMessage.authOk.encode())

        XCTAssertEqual(object.count, 1)
        XCTAssertEqual(object["type"] as? String, "auth_ok")
    }

    func testProtocolClipJSONDecodes() {
        let json = #"{"type":"clip","text":"hello","deviceId":"android","ts":123}"#

        XCTAssertEqual(
            ClipMessage.decode(json),
            .clip(text: "hello", deviceId: .android, ts: 123)
        )
    }

    func testInvalidDeviceIDDecodesToNil() {
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"clip","text":"hello","deviceId":"ios","ts":123}"#
            )
        )
    }

    func testRequiredFieldsWithWrongTypesDecodeToNil() {
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"auth","token":123,"deviceId":"android"}"#
            )
        )
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"auth","token":"secret","deviceId":123}"#
            )
        )
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"clip","text":123,"deviceId":"mac","ts":123}"#
            )
        )
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"clip","text":"hello","deviceId":"mac","ts":"123"}"#
            )
        )
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"clip","text":"hello","deviceId":"mac","ts":true}"#
            )
        )
        XCTAssertNil(
            ClipMessage.decode(
                #"{"type":"clip","text":"hello","deviceId":"mac","ts":123.0}"#
            )
        )
    }

    func testUnknownAdditionalFieldsAreIgnored() {
        XCTAssertEqual(
            ClipMessage.decode(
                #"{"type":"auth","token":"secret","deviceId":"android","futureField":true}"#
            ),
            .auth(token: "secret", deviceId: .android)
        )
        XCTAssertEqual(
            ClipMessage.decode(#"{"type":"auth_ok","futureField":true}"#),
            .authOk
        )
        XCTAssertEqual(
            ClipMessage.decode(
                #"{"type":"clip","text":"hello","deviceId":"mac","ts":123,"futureField":true}"#
            ),
            .clip(text: "hello", deviceId: .mac, ts: 123)
        )
    }

    func testMalformedJSONDecodesToNil() {
        XCTAssertNil(ClipMessage.decode("{not-json}"))
    }

    func testUnknownTypeDecodesToNil() {
        XCTAssertNil(ClipMessage.decode(#"{"type":"unknown"}"#))
    }

    func testMissingRequiredFieldDecodesToNil() {
        XCTAssertNil(ClipMessage.decode(#"{"type":"clip","text":"hello","deviceId":"mac"}"#))
    }

    private func assertRoundTrip(
        _ message: ClipMessage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            ClipMessage.decode(message.encode()),
            message,
            file: file,
            line: line
        )
    }

    private func decodedJSONObject(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8), file: file, line: line)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line
        )
    }
}
