import Foundation

/// Token storage shared by the host app and the widget through the App Group.
public enum SharedSettings {
    static let tokenKey = "sncfToken"

    /// The group id comes from Info.plist (`SNCFAppGroup`) so it can carry the signing team prefix.
    static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SNCFAppGroup") as? String else { return nil }
        return UserDefaults(suiteName: group)
    }

    public static var token: String? {
        get { stored ?? bundled }
        set { defaults?.set(newValue, forKey: tokenKey) }
    }

    /// Typed in the host app, shared through the App Group. Unavailable on iOS, where a free
    /// Apple account cannot use App Groups; `SNCF_TOKEN` in Config/Local.xcconfig takes over.
    static var stored: String? { trimmed(defaults?.string(forKey: tokenKey)) }

    public static var bundled: String? { trimmed(Bundle.main.object(forInfoDictionaryKey: "SNCFToken") as? String) }

    static func trimmed(_ value: String?) -> String? {
        let token = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty ?? true) ? nil : token
    }
}

extension Station {
    /// Widget configuration only persists entity identifiers, so the whole station is
    /// packed into the id to avoid an API round trip each time the system resolves it.
    public var entityIdentifier: String {
        "\(id)|\(latitude)|\(longitude)|\(name)"
    }

    public init?(entityIdentifier: String) {
        let parts = entityIdentifier.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let lat = Double(parts[1]), let lon = Double(parts[2]) else { return nil }
        self.init(id: String(parts[0]), name: String(parts[3]), latitude: lat, longitude: lon)
    }
}
