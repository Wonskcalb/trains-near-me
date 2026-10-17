import CoreLocation
import Foundation
import Testing
@testable import SNCFCore

/// LEAVE HOME IN: the pure catch-the-train rule, which walk wins, and the two settings behind them, all
/// from fixtures at the mockups' anchor (Thu 15 Oct 2026, 17:40 Europe/Paris). No SNCF API, no MapKit,
/// and the settings run on a suite of their own rather than the real `.standard` defaults.
@Suite struct BigScreenLeaveBy {
    let now = BigScreenFixtures.now
    let voiron = BigScreenFixtures.voiron

    private func train(_ h: Int, _ m: Int, delay: Int = 0, cancelled: Bool = false, number: String) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: BigScreenFixtures.at(h, m), scheduledArrival: BigScreenFixtures.at(h + 1, m),
                       mode: "TER", delayMinutes: delay, isCancelled: cancelled, trainNumber: number)
    }

    private func catchable(_ trains: [TrainDeparture], walk: Int, at date: Date? = nil) -> LeaveBy? {
        LiveLeaveBy.firstCatchable(in: trains, walk: walk, now: date ?? now)
    }

    @Test func picksTheFirstTrainYouCanStillMake() {
        // 17:44 leaves in 4 min — a 6-minute walk means you already had to go; 17:46 is the first you make.
        let result = catchable([train(17, 44, number: "A"), train(17, 46, number: "B"), train(18, 12, number: "C")], walk: 6)
        #expect(result?.train.trainNumber == "B")
        #expect(result?.walkMinutes == 6)
        #expect(result?.leaveAt == BigScreenFixtures.at(17, 40))   // 17:46 − 6, exactly now: just catchable
    }

    @Test func aMinuteLaterTheMissedTrainGivesWayToTheNext() {
        // The Wall re-runs the rule at each tick from the trains it holds: at 17:41 the 17:46 is gone.
        let trains = [train(17, 46, number: "B"), train(18, 12, number: "C")]
        #expect(catchable(trains, walk: 6, at: BigScreenFixtures.at(17, 41))?.train.trainNumber == "C")
    }

    @Test func nilWhenEveryTrainIsAlreadyGone() {
        #expect(catchable([train(17, 44, number: "A")], walk: 6) == nil)
    }

    @Test func skipsCancelledTrainsEvenWhenTheyAreCatchable() {
        let result = catchable([train(17, 46, cancelled: true, number: "X"), train(17, 50, number: "Y")], walk: 6)
        #expect(result?.train.trainNumber == "Y")
        #expect(result?.leaveAt == BigScreenFixtures.at(17, 44))
    }

    @Test func nilWhenEveryTrainIsCancelled() {
        #expect(catchable([train(18, 12, cancelled: true, number: "X"), train(18, 42, cancelled: true, number: "Y")], walk: 6) == nil)
    }

    @Test func leaveAtIsTheExpectedDepartureMinusTheWalk() throws {
        // A delayed train: leaveAt is measured from the amended time, not the timetable.
        let result = try #require(catchable([train(18, 12, delay: 12, number: "D")], walk: 10))
        #expect(result.train.expectedDeparture == BigScreenFixtures.at(18, 24))
        #expect(result.leaveAt == BigScreenFixtures.at(18, 14))
    }

    // MARK: Which walk

    @Test func aWalkTheUserSetBeatsMapKit() async {
        let provider = LiveLeaveBy(walkETA: { _ in 3 }, storedWalk: { _ in 12 })
        #expect(await provider.walkMinutes(to: voiron) == 12)
    }

    @Test func mapKitOnlyStandsInForAWalkNeverSet() async {
        let provider = LiveLeaveBy(walkETA: { _ in 3 }, storedWalk: { _ in nil })
        #expect(await provider.walkMinutes(to: voiron) == 3)
    }

    @Test func theDefaultWhenNeitherAnswers() async {
        let provider = LiveLeaveBy(walkETA: { _ in nil }, storedWalk: { _ in nil })
        #expect(await provider.walkMinutes(to: voiron) == SharedSettings.defaultWalkMinutes)
    }

    #if canImport(MapKit)
    @Test func theMapKitOriginIsRoundedToAbout100Metres() {
        let rounded = LiveLeaveBy.rounded(.init(latitude: 45.191463, longitude: 5.714466))
        #expect(rounded.latitude == 45.191)
        #expect(rounded.longitude == 5.714)
    }
    #endif

    // MARK: Settings

    @Test func walkMinutesRoundTripsAndTellsSetFromDefault() throws {
        let name = "test.bigscreen.walk.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }

        #expect(SharedSettings.walkMinutesIfSet(for: "unset", in: store) == nil)
        SharedSettings.setWalkMinutes(17, for: "set", in: store)
        #expect(SharedSettings.walkMinutesIfSet(for: "set", in: store) == 17)
        // Other stations keep their own value, and setting one back to six still counts as set.
        #expect(SharedSettings.walkMinutesIfSet(for: "unset", in: store) == nil)
        SharedSettings.setWalkMinutes(SharedSettings.defaultWalkMinutes, for: "unset", in: store)
        #expect(SharedSettings.walkMinutesIfSet(for: "unset", in: store) == SharedSettings.defaultWalkMinutes)
    }

    @Test func pinnedStationRoundTripsIncludingNil() async {
        let provider = LiveLeaveBy()
        let before = await provider.pinnedStation()
        defer { SharedSettings.pinnedStation = before }
        await provider.pin(voiron)
        #expect(await provider.pinnedStation() == voiron)
        await provider.pin(nil)
        #expect(await provider.pinnedStation() == nil)
    }
}
