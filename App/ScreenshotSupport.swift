#if DEBUG && os(iOS)
import Foundation
import SNCFCore

/// Debug-only hooks the screenshot script drives through launch-environment variables, so README
/// images are captured from the real screens without any UI automation: one launch per tab, each
/// one seeded and pointed at a known tab, then `simctl io screenshot`. Compiled out of Release.
enum ScreenshotSupport {
    /// `SCREENSHOT_TAB` picks which tab opens: 0 Near me, 1 Journeys, 2 Settings. Absent → Near me.
    static var initialTab: Int {
        Int(ProcessInfo.processInfo.environment["SCREENSHOT_TAB"] ?? "") ?? 0
    }

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
}
#endif
