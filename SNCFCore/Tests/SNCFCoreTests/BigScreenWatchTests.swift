import Foundation
import Testing
@testable import SNCFCore

/// `TrainIdentity` has to pick a stable handle so a watch survives the reloads that rewrite a
/// `TrainDeparture`: the vehicle-journey id when SNCF gives one, else the number pinned to its 03:00
/// service day, else nothing.
@Suite struct BigScreenWatchIdentity {
    let cal = BigScreenFixtures.calendar

    @Test func vehicleJourneyWins() {
        #expect(TrainIdentity(BigScreenFixtures.grenobleVoironTrains[1], calendar: cal)
                == .vehicleJourney("vehicle_journey:fake:17655"))
    }

    @Test func fallsBackToNumberPinnedToTheServiceDay() {
        let dep = BigScreenFixtures.at(18, 12)
        let row = TrainDeparture(scheduledDeparture: dep, delayMinutes: 0, isCancelled: false,
                                 trainNumber: "9999", vehicleJourneyID: nil)
        #expect(TrainIdentity(row, calendar: cal)
                == .numbered("9999", serviceDay: BoardState.serviceDay(of: dep, calendar: cal)))
    }

    @Test func aNightTrainKeepsThePreviousEveningsServiceDay() {
        // 00:15 the morning after is still the 15th's service day (the day starts at 03:00).
        let afterMidnight = BigScreenFixtures.at(0, 15, day: 16)
        let row = TrainDeparture(scheduledDeparture: afterMidnight, delayMinutes: 0, isCancelled: false,
                                 trainNumber: "1", vehicleJourneyID: nil)
        #expect(TrainIdentity(row, calendar: cal)
                == .numbered("1", serviceDay: BoardState.serviceDay(of: BigScreenFixtures.at(23, 0), calendar: cal)))
    }

    @Test func emptyIdsFallThroughOrProduceNothing() {
        let noon = BigScreenFixtures.at(12, 0)
        let day = BoardState.serviceDay(of: noon, calendar: cal)
        // An empty vehicle-journey id is treated as absent, so the number is used.
        let emptyVJ = TrainDeparture(scheduledDeparture: noon, delayMinutes: 0, isCancelled: false,
                                     trainNumber: "5", vehicleJourneyID: "")
        #expect(TrainIdentity(emptyVJ, calendar: cal) == .numbered("5", serviceDay: day))
        // Neither id nor number: nothing stable to watch.
        let bare = TrainDeparture(scheduledDeparture: noon, delayMinutes: 0, isCancelled: false,
                                  trainNumber: nil, vehicleJourneyID: nil)
        #expect(TrainIdentity(bare, calendar: cal) == nil)
        let bothEmpty = TrainDeparture(scheduledDeparture: noon, delayMinutes: 0, isCancelled: false,
                                       trainNumber: "", vehicleJourneyID: "")
        #expect(TrainIdentity(bothEmpty, calendar: cal) == nil)
    }
}

/// The band-change decision is the heart of the watcher and the only part with notification-free logic
/// worth testing. The rule: fire on a band crossing or a cancellation, stay quiet for more minutes in the
/// same band, and only record (never alert) a first sighting unless it is already cancelled.
@Suite struct BigScreenWatchDecision {
    @Test func onTimeToDelayedFires() {
        #expect(TrainWatcher.alert(from: .onTime, to: .delayed) == .bandChanged(to: .delayed))
    }

    @Test func sameBandWithWorseMinutesStaysQuiet() {
        // +12 and +16 are both "delayed": the rule fires on band crossings, not on extra minutes.
        #expect(TrainWatcher.alert(from: .delayed, to: .delayed) == nil)
    }

    @Test func crossingIntoSevereFires() {
        #expect(TrainWatcher.alert(from: .delayed, to: .severelyDelayed) == .bandChanged(to: .severelyDelayed))
    }

    @Test func anyStatusToCancelledFires() {
        #expect(TrainWatcher.alert(from: .onTime, to: .cancelled) == .cancelled)
        #expect(TrainWatcher.alert(from: .delayed, to: .cancelled) == .cancelled)
        #expect(TrainWatcher.alert(from: nil, to: .cancelled) == .cancelled)   // first sighting, already cancelled
    }

    @Test func cancelledToCancelledDoesNotRefire() {
        #expect(TrainWatcher.alert(from: .cancelled, to: .cancelled) == nil)
    }

    @Test func firstSightingOnlyRecordsUnlessCancelled() {
        #expect(TrainWatcher.alert(from: nil, to: .onTime) == nil)
        #expect(TrainWatcher.alert(from: nil, to: .delayed) == nil)
    }
}

/// The App-Group-backed store: the watched set and last-seen status round-trip through `UserDefaults`, and
/// re-evaluation records each watched train's status. Notifications are off, so nothing reaches
/// `UNUserNotificationCenter`; a unique suite per test keeps the parallel runs apart.
@Suite struct BigScreenWatchStore {
    let cal = BigScreenFixtures.calendar
    private func suite() -> String { "test.bigscreen.watch.\(UUID().uuidString)" }

    @Test func watchedSetSurvivesANewInstance() async {
        let name = suite()
        defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let id = TrainIdentity(BigScreenFixtures.grenobleVoironTrains[1], calendar: cal)!

        let a = TrainWatcher(suiteName: name, schedulesNotifications: false)
        #expect(await a.isWatched(id) == false)
        await a.watch(id)
        #expect(await a.isWatched(id))

        let reloaded = TrainWatcher(suiteName: name, schedulesNotifications: false)   // reads back from the App Group
        #expect(await reloaded.watched() == [id])
        await reloaded.unwatch(id)

        let afterUnwatch = TrainWatcher(suiteName: name, schedulesNotifications: false)
        #expect(await afterUnwatch.watched().isEmpty)
    }

    @Test func reevaluateRecordsAndPersistsLastSeen() async {
        let name = suite()
        defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let onTime = BigScreenFixtures.grenobleVoironTrains[0]        // 17653, no delay
        let id = TrainIdentity(onTime, calendar: cal)!

        let watcher = TrainWatcher(suiteName: name, schedulesNotifications: false)
        await watcher.watch(onTime, calendar: cal)                   // the concrete-train entry records initial status
        #expect(await watcher.isWatched(id))
        #expect(await watcher.lastSeen[id]?.status == .onTime)

        // Same train, now delayed +15: re-evaluation updates and persists the band.
        let delayed = TrainDeparture(scheduledDeparture: onTime.scheduledDeparture, scheduledArrival: onTime.scheduledArrival,
                                     mode: onTime.mode, delayMinutes: 15, isCancelled: false,
                                     trainNumber: onTime.trainNumber, vehicleJourneyID: onTime.vehicleJourneyID)
        await watcher.reevaluate(against: [delayed], calendar: cal)
        #expect(await watcher.lastSeen[id]?.status == .delayed)

        let reloaded = TrainWatcher(suiteName: name, schedulesNotifications: false)
        #expect(await reloaded.lastSeen[id]?.status == .delayed)
    }

    @Test func reevaluateIgnoresUnwatchedTrains() async {
        let name = suite()
        defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let watcher = TrainWatcher(suiteName: name, schedulesNotifications: false)
        await watcher.reevaluate(against: BigScreenFixtures.grenobleVoironTrains, calendar: cal)
        #expect(await watcher.lastSeen.isEmpty)
    }
}
