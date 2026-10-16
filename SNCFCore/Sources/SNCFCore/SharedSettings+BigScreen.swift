import Foundation

/// Big-screen settings that live only here: the per-station walk time the "LEAVE HOME IN" countdown is
/// based on, and the single station Wall mode pins to. Both are user choices made in the app, so they
/// follow `favorites`/`appearance` and fall back to the app's own defaults without an App Group — on a
/// free Apple account the Wall screen still runs in the app, it just stops sharing them with the widget.
public extension SharedSettings {
    /// Six minutes to the platform, the mockup's figure. Returned for any station not set yet, and the
    /// base MapKit refines when it can.
    static let defaultWalkMinutes = 6

    /// Minutes on foot from home to a station, keyed by `Station.id`. One dictionary under one key so a
    /// station's figure round-trips and every other station keeps its own.
    static subscript(walkMinutesFor stationID: String) -> Int {
        get { walkMinutesByStation[stationID] ?? defaultWalkMinutes }
        set {
            var map = walkMinutesByStation
            map[stationID] = newValue
            guard let data = try? JSONEncoder().encode(map) else { return }
            (defaults ?? .standard).set(data, forKey: walkMinutesKey)
        }
    }

    /// The station Wall mode is locked to. nil clears it (back to the nearest-station default).
    static var pinnedStation: Station? {
        get {
            guard let data = (defaults ?? .standard).data(forKey: pinnedStationKey) else { return nil }
            return try? JSONDecoder().decode(Station.self, from: data)
        }
        set {
            let store = defaults ?? .standard
            guard let station = newValue, let data = try? JSONEncoder().encode(station) else {
                store.removeObject(forKey: pinnedStationKey)
                return
            }
            store.set(data, forKey: pinnedStationKey)
        }
    }

    private static var walkMinutesByStation: [String: Int] {
        guard let data = (defaults ?? .standard).data(forKey: walkMinutesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private static var walkMinutesKey: String { "bigscreen.walkMinutes" }
    private static var pinnedStationKey: String { "bigscreen.pinnedStation" }
}
