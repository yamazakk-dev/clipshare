import Foundation

final class AppSettings {
    private enum Key {
        static let token = "clipshare.token"
        static let syncEnabled = "clipshare.syncEnabled"
        static let port = "clipshare.port"
    }

    private static let defaultPort: UInt16 = 4747

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults
            ?? UserDefaults(suiteName: "com.ymac.clipshare")
            ?? .standard
        self.defaults = defaults
        defaults.register(defaults: [
            Key.syncEnabled: true,
            Key.port: Int(Self.defaultPort)
        ])

        let storedToken = defaults.string(forKey: Key.token)
        if storedToken == nil || storedToken?.isEmpty == true {
            defaults.set(UUID().uuidString, forKey: Key.token)
        }
    }

    var token: String {
        guard let token = defaults.string(forKey: Key.token), !token.isEmpty else {
            let token = UUID().uuidString
            defaults.set(token, forKey: Key.token)
            return token
        }
        return token
    }

    var isSyncEnabled: Bool {
        get { defaults.bool(forKey: Key.syncEnabled) }
        set { defaults.set(newValue, forKey: Key.syncEnabled) }
    }

    var port: UInt16 {
        get {
            let storedPort = defaults.integer(forKey: Key.port)
            guard (1...Int(UInt16.max)).contains(storedPort) else {
                defaults.set(Int(Self.defaultPort), forKey: Key.port)
                return Self.defaultPort
            }
            return UInt16(storedPort)
        }
        set {
            let validPort = newValue == 0 ? Self.defaultPort : newValue
            defaults.set(Int(validPort), forKey: Key.port)
        }
    }
}
