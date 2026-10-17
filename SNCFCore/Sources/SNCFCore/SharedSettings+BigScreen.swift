import Foundation

/// Big-screen settings that live only here: the per-station walk time the "LEAVE HOME IN" countdown is
/// based on, and the single station Wall mode pins to. Both are user choices made in the app, so they
/// follow `favorites`/`appearance` and fall back to the app's own defaults without an App Group — on a
/// free Apple account the Wall screen still runs in the app, it just stops sharing them with the widget.
public extension SharedSettings {
    /// Six minutes to the platform, the mockup's figure: what a station never set reads, when MapKit has
    /// no walking ETA to offer instead.
    static let defaultWalkMinutes = 6

    /// Minutes on foot from home to a station, keyed by `Station.id`; the default for one never set.
    static subscript(walkMinutesFor stationID: String) -> Int {
        get { walkMinutesIfSet(for: stationID) ?? defaultWalkMinutes }
        set { setWalkMinutes(newValue, for: stationID, in: localStore) }
    }

    /// The walk the user picked for this station, nil while it is still the default: a figure they chose
    /// beats MapKit's estimate, which only stands in for one never set.
    static func walkMinutesIfSet(for stationID: String) -> Int? {
        walkMinutesIfSet(for: stationID, in: localStore)
    }

    /// The station Wall mode is locked to. nil clears it (back to the nearest-station default).
    static var pinnedStation: Station? {
        get {
            guard let data = localStore.data(forKey: pinnedStationKey) else { return nil }
            return try? JSONDecoder().decode(Station.self, from: data)
        }
        set {
            guard let station = newValue, let data = try? JSONEncoder().encode(station) else {
                localStore.removeObject(forKey: pinnedStationKey)
                return
            }
            localStore.set(data, forKey: pinnedStationKey)
        }
    }

    // The store-taking forms are what the tests drive, on a suite of their own rather than `.standard`.
    // One dictionary under one key, so a station's figure round-trips and every other station keeps its own.

    internal static func walkMinutesIfSet(for stationID: String, in store: UserDefaults) -> Int? {
        walkMinutesByStation(in: store)[stationID]
    }

    internal static func setWalkMinutes(_ minutes: Int, for stationID: String, in store: UserDefaults) {
        var map = walkMinutesByStation(in: store)
        map[stationID] = minutes
        guard let data = try? JSONEncoder().encode(map) else { return }
        store.set(data, forKey: walkMinutesKey)
    }

    private static func walkMinutesByStation(in store: UserDefaults) -> [String: Int] {
        guard let data = store.data(forKey: walkMinutesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private static var localStore: UserDefaults { defaults ?? .standard }
    private static var walkMinutesKey: String { "bigscreen.walkMinutes" }
    private static var pinnedStationKey: String { "bigscreen.pinnedStation" }
}
