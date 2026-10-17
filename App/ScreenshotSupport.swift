#if DEBUG && os(iOS)
import Foundation
import SNCFCore

/// Debug-only hooks the screenshot script drives through launch-environment variables, so README
/// images are captured from the real screens without any UI automation: one launch per tab, each
/// one seeded and pointed at a known tab, then `simctl io screenshot`. Compiled out of Release.
enum ScreenshotSupport {
    /// `SCREENSHOT_TAB` picks which tab opens: 0 Near me, 1 Journeys, 2 Wall, 3 Settings. Absent → Near me,
    /// or the Wall with `SCREENSHOT_WALL`.
    static var initialTab: Int {
        Int(ProcessInfo.processInfo.environment["SCREENSHOT_TAB"] ?? "") ?? (openWall ? RootView.wallTab : 0)
    }

    /// `SCREENSHOT_LINES` turns Near me's switch to Lines, `SCREENSHOT_LANES` Journeys' to Lanes.
    static var showsLines: Bool { ProcessInfo.processInfo.environment["SCREENSHOT_LINES"] != nil }
    static var showsLanes: Bool { ProcessInfo.processInfo.environment["SCREENSHOT_LANES"] != nil }

    /// `SCREENSHOT_SEED` plants one saved journey so the Journeys tab has a card to show. Real SNCF
    /// stop_area ids, so the board actually loads trains from the API.
    static func seedIfNeeded() {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_SEED"] != nil else { return }
        let grenoble = Station(id: "stop_area:SNCF:87747006", name: "Grenoble",
                               latitude: 45.19149081, longitude: 5.71454823)
        let voiron = Station(id: "stop_area:SNCF:87747287", name: "Voiron",
                             latitude: 45.36403405, longitude: 5.59495926)
        SharedSettings.favorites = [JourneyConfiguration(stationA: grenoble, stationB: voiron, direction: .automatic)]
    }

    /// `SCREENSHOT_JOURNEY` opens the first saved journey's board in the Journeys tab, which is the only
    /// way to capture a pushed board (or the Duo's board | train split) without UI automation.
    static var openJourney: JourneyConfiguration? {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_JOURNEY"] != nil else { return nil }
        return SharedSettings.favorites.first
    }

    /// `SCREENSHOT_WALL` opens the Wall tab.
    static var openWall: Bool { ProcessInfo.processInfo.environment["SCREENSHOT_WALL"] != nil }

    /// `SCREENSHOT_STATION` opens a station's line map in Near me, packed as `id|lat|lon|name` like the
    /// widget's station entity: the map splits its lanes by bearing, so the station needs its coordinates.
    static var station: Station? {
        ProcessInfo.processInfo.environment["SCREENSHOT_STATION"].flatMap(Station.init(entityIdentifier:))
    }

    /// `SCREENSHOT_ROUTE` (stationHall, lanes, wall, roundTrip, station) opens that screen of the iPad /
    /// regular-width shell, which never builds the tabs the other hooks drive. `station` shows
    /// `SCREENSHOT_STATION`.
    static var route: BigScreenRoute? {
        switch ProcessInfo.processInfo.environment["SCREENSHOT_ROUTE"] {
        case "stationHall": .stationHall
        case "lanes": .lanes
        case "wall": .wall
        case "roundTrip": .roundTrip
        case "station": .station
        default: nil
        }
    }

    /// The shell's hooks: the seed (so an iPad launch has a journey too) and the route.
    @MainActor static func apply(to model: BigScreenModel) {
        seedIfNeeded()
        guard let route else { return }
        if route == .station, let station { model.show(station: station) } else { model.select(route) }
    }
}
#endif
