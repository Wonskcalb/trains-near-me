#if os(iOS)
import BackgroundTasks
import SNCFCore

/// iOS background app refresh for watched trains. When the system grants a slot, re-fetch the pinned
/// station's board and every saved journey's board and let `TrainWatcher` fire a delay-band or
/// cancellation alert on a change. This never reloads widgets: the WidgetKit budget (~40-70/day) is for
/// drawing, not for this, so the type never imports WidgetKit. The watched set and last-seen status round
/// trip through the App Group, so a fresh `TrainWatcher` per run sees the same state the app wrote.
enum BackgroundRefresh {
    /// Matches the `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist (`<bundle>.refresh`).
    static let taskID = (Bundle.main.bundleIdentifier ?? "trains-near-me") + ".refresh"

    /// Register the launch handler. iOS requires this before launch finishes, so `App.init()` calls it.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            // BGTask is not Sendable; it is only ever touched on this one launch queue, so the task
            // hops below are safe — the unsafe opt-out is what lets them satisfy Swift 6's checker.
            nonisolated(unsafe) let task = task
            let work = Task { await run() }
            task.expirationHandler = { work.cancel() }
            Task {
                await work.value
                task.setTaskCompleted(success: !work.isCancelled)
            }
        }
    }

    /// Ask the system for a future refresh; called when the app backgrounds. The system decides when.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Re-evaluate every watched train against freshly fetched boards. The RAW `[TrainDeparture]` is passed
    /// to `reevaluate` — base_schedule keeps cancelled rows, so a cancellation is still visible here; a
    /// collapsed `BoardState` would have dropped it.
    static func run() async {
        let watcher = TrainWatcher()
        guard !(await watcher.watched()).isEmpty else { return }   // nothing watched: don't spend the slot
        let client = SNCFClient(token: SharedSettings.token)
        let now = Date.now
        if let station = SharedSettings.pinnedStation,
           let trains = try? await client.departures(from: station, at: now) {
            await watcher.reevaluate(against: trains)
        }
        for journey in SharedSettings.favorites {
            let leg = JourneySelector.leg(for: journey, at: now, location: nil)
            if let trains = try? await client.departures(from: leg.from, to: leg.to, at: now) {
                await watcher.reevaluate(against: trains, to: leg)
            }
        }
    }
}
#endif
