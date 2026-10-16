import Foundation

/// Token storage shared by the host app and the widget through the App Group.
public enum SharedSettings {
    static let tokenKey = "sncfToken"

    /// The App Group suite name from Info.plist (`SNCFAppGroup`), carrying the per-platform shape: the
    /// team prefix on macOS, a "group." prefix on iOS. Public so the big-screen providers read it from
    /// here instead of each repeating the Info.plist lookup. nil without a group (a free Apple account).
    public static var appGroupSuiteName: String? {
        Bundle.main.object(forInfoDictionaryKey: "SNCFAppGroup") as? String
    }

    static var defaults: UserDefaults? {
        appGroupSuiteName.flatMap { UserDefaults(suiteName: $0) }
    }

    /// Whether the app and the widget actually share storage. False without a real signing team on
    /// iOS, where a free Apple account gets no App Group: the token then has to be compiled in.
    public static var isShared: Bool { defaults != nil }

    /// Set by a widget's refresh button so the next timeline can show that widget's last result
    /// marked as updating, before the network answers. Stored per widget kind and per widget, so
    /// clicking one widget never puts another in the updating state. A no-op without an App Group,
    /// where the widget simply fetches straight away.
    public static func requestRefresh(kind: String, signature: String) {
        guard let data = try? JSONEncoder().encode(RefreshRequest(signature: signature, at: .now)) else { return }
        defaults?.set(data, forKey: "refresh.\(kind)")
    }

    /// True once, for the widget that was actually clicked. A request that no widget ever picks up
    /// expires on its own, so nothing can stay pinned to "updating".
    public static func takeRefreshRequest(kind: String, signature: String) -> Bool {
        guard let data = defaults?.data(forKey: "refresh.\(kind)"),
              let request = try? JSONDecoder().decode(RefreshRequest.self, from: data),
              request.signature == signature, Date.now.timeIntervalSince(request.at) < 10 else { return false }
        defaults?.removeObject(forKey: "refresh.\(kind)")
        return true
    }

    /// The last board a widget managed to fetch, kept per widget: two trip widgets showing
    /// different journeys must not redraw each other's trains.
    public static func cachedBoard(kind: String, signature: String) -> CachedBoard? {
        guard let data = defaults?.data(forKey: "board.\(kind)#\(signature)") else { return nil }
        return try? JSONDecoder().decode(CachedBoard.self, from: data)
    }

    public static func cache(_ board: CachedBoard, kind: String, signature: String) {
        guard let data = try? JSONEncoder().encode(board) else { return }
        defaults?.set(data, forKey: "board.\(kind)#\(signature)")
    }

    /// The journeys saved in the app. Kept in the App Group so the widget's station picker can
    /// suggest their stations, and in the app's own defaults when there is no group — a free Apple
    /// account on iOS — where the only thing lost is those suggestions.
    public static var favorites: [JourneyConfiguration] {
        get {
            guard let data = (defaults ?? .standard).data(forKey: "favorites") else { return [] }
            return (try? JSONDecoder().decode([JourneyConfiguration].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            (defaults ?? .standard).set(data, forKey: "favorites")
        }
    }

    public static var token: String? {
        get { stored ?? bundled }
        set { defaults?.set(newValue, forKey: tokenKey) }
    }

    /// How the iOS app paints itself. A local preference, not shared with the widget: a widget
    /// always follows the system appearance and cannot be forced per-app, so this lives in whatever
    /// defaults exist — the App Group when there is one, the app's own otherwise.
    public enum Appearance: String, CaseIterable, Sendable {
        case system, light, dark
    }

    public static var appearance: Appearance {
        get { (defaults ?? .standard).string(forKey: "appearance").flatMap(Appearance.init) ?? .system }
        set { (defaults ?? .standard).set(newValue.rawValue, forKey: "appearance") }
    }

    /// Typed in the host app, shared through the App Group. Without one — a free Apple account on
    /// iOS — `SNCF_TOKEN` in Config/Local.xcconfig takes over.
    static var stored: String? { trimmed(defaults?.string(forKey: tokenKey)) }

    public static var bundled: String? { trimmed(Bundle.main.object(forInfoDictionaryKey: "SNCFToken") as? String) }

    static func trimmed(_ value: String?) -> String? {
        let token = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty ?? true) ? nil : token
    }
}

struct RefreshRequest: Codable {
    let signature: String
    let at: Date
}

/// What a widget showed last, so a refresh can redraw it immediately instead of a blank panel.
public struct CachedBoard: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let origin: Station
    /// nil for the radar, which has no destination.
    public let destination: Station?
    public let trains: [TrainDeparture]

    public init(fetchedAt: Date, origin: Station, destination: Station?, trains: [TrainDeparture]) {
        self.fetchedAt = fetchedAt
        self.origin = origin
        self.destination = destination
        self.trains = trains
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
