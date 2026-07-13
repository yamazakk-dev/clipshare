import CoreFoundation
import Foundation

public enum DeviceID: String, Equatable {
    case mac
    case android
}

public enum ClipMessage: Equatable {
    case auth(token: String, deviceId: DeviceID)
    case authOk
    case clip(text: String, deviceId: DeviceID, ts: Int)

    public func encode() -> String {
        let object: [String: Any]

        switch self {
        case let .auth(token, deviceId):
            object = [
                "type": "auth",
                "token": token,
                "deviceId": deviceId.rawValue
            ]
        case .authOk:
            object = ["type": "auth_ok"]
        case let .clip(text, deviceId, ts):
            object = [
                "type": "clip",
                "text": text,
                "deviceId": deviceId.rawValue,
                "ts": ts
            ]
        }

        // Every value above is a JSON-compatible Foundation type.
        let data = try! JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String) -> ClipMessage? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any],
              let type = fields["type"] as? String else {
            return nil
        }

        switch type {
        case "auth":
            guard let token = fields["token"] as? String,
                  let deviceIDValue = fields["deviceId"] as? String,
                  let deviceId = DeviceID(rawValue: deviceIDValue) else {
                return nil
            }
            return .auth(token: token, deviceId: deviceId)

        case "auth_ok":
            return .authOk

        case "clip":
            guard let text = fields["text"] as? String,
                  let deviceIDValue = fields["deviceId"] as? String,
                  let deviceId = DeviceID(rawValue: deviceIDValue),
                  let timestamp = fields["ts"] as? NSNumber,
                  CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
                  !CFNumberIsFloatType(timestamp),
                  let ts = timestamp as? Int else {
                return nil
            }
            return .clip(text: text, deviceId: deviceId, ts: ts)

        default:
            return nil
        }
    }
}
