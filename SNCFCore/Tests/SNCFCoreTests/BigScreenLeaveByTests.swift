import Foundation
import Testing
@testable import SNCFCore

/// The live leave-by provider's catch-the-train logic and the two App-Group settings behind it, all from
/// fixtures at the mockups' anchor (Thu 15 Oct 2026, 17:40 Europe/Paris). The board is injected, so no
/// SNCF API; the walk time defaults to the stored setting, so no MapKit.
@Suite struct BigScreenLeaveBy {
    let now = BigScreenFixtures.now
    let calendar = BigScreenFixtures.calendar
    let voiron = BigScreenFixtures.voiron

    private func train(_ h: Int, _ m: Int, delay: Int = 0, cancelled: Bool = false, number: String) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: BigScreenFixtures.at(h, m), scheduledArrival: BigScreenFixtures.at(h + 1, m),
                       mode: "TER", delayMinutes: delay, isCancelled: cancelled, trainNumber: number)
    }

    /// A provider whose board is the given trains, and a leg from a fresh origin whose walk time is `walk`.
    /// The origin is unique per call so tests that run in parallel never fight over one station's setting.
    private func provider(_ trains: [TrainDeparture], walk: Int) -> (LiveLeaveBy, Leg) {
        let origin = Station(id: UUID().uuidString, name: "Origin", latitude: 0, longitude: 0)
        SharedSettings[walkMinutesFor: origin.id] = walk
        let calendar = calendar
        let provider = LiveLeaveBy(board: { _, now in BoardState.from(trains, now: now, calendar: calendar) })
        return (provider, Leg(from: origin, to: voiron))
    }

    @Test func picksTheFirstTrainYouCanStillMake() async {
        // 17:44 leaves in 4 min — a 6-minute walk means you already had to go; 17:46 is the first you make.
        let (provider, leg) = provider([train(17, 44, number: "A"), train(17, 46, number: "B"),
                                        train(18, 12, number: "C")], walk: 6)
        let result = await provider.leaveBy(toCatch: leg, at: now)
        #expect(result?.train.trainNumber == "B")
        #expect(result?.walkMinutes == 6)
        #expect(result?.leaveAt == BigScreenFixtures.at(17, 40))   // 17:46 − 6, exactly now: just catchable
    }

    @Test func nilWhenEveryTrainIsAlreadyGone() async {
        // The only train leaves in 4 min, the walk is 6: leaveAt is before now, it is missed.
        let (provider, leg) = provider([train(17, 44, number: "A")], walk: 6)
        #expect(await provider.leaveBy(toCatch: leg, at: now) == nil)
    }

    @Test func skipsCancelledTrainsEvenWhenTheyAreCatchable() async {
        // 17:46 is catchable but cancelled; the next running one, 17:50, is taken instead.
        let (provider, leg) = provider([train(17, 46, cancelled: true, number: "X"),
                                        train(17, 50, number: "Y")], walk: 6)
        let result = await provider.leaveBy(toCatch: leg, at: now)
        #expect(result?.train.trainNumber == "Y")
        #expect(result?.leaveAt == BigScreenFixtures.at(17, 44))
    }

    @Test func nilWhenEveryTrainIsCancelled() async {
        let (provider, leg) = provider([train(18, 12, cancelled: true, number: "X"),
                                        train(18, 42, cancelled: true, number: "Y")], walk: 6)
        #expect(await provider.leaveBy(toCatch: leg, at: now) == nil)
    }

    @Test func leaveAtIsTheExpectedDepartureMinusTheWalk() async throws {
        // A delayed train: leaveAt is measured from the amended time, not the timetable.
        let (provider, leg) = provider([train(18, 12, delay: 12, number: "D")], walk: 10)
        let result = try #require(await provider.leaveBy(toCatch: leg, at: now))
        #expect(result.train.expectedDeparture == BigScreenFixtures.at(18, 24))
        #expect(result.walkMinutes == 10)
        #expect(result.leaveAt == result.train.expectedDeparture.addingTimeInterval(-10 * 60))
        #expect(result.leaveAt == BigScreenFixtures.at(18, 14))
    }

    // MARK: Settings

    @Test func walkMinutesRoundTripsAndDefaults() {
        let unset = Station(id: UUID().uuidString, name: "Unset", latitude: 0, longitude: 0)
        #expect(SharedSettings[walkMinutesFor: unset.id] == SharedSettings.defaultWalkMinutes)

        let set = Station(id: UUID().uuidString, name: "Set", latitude: 0, longitude: 0)
        SharedSettings[walkMinutesFor: set.id] = 17
        #expect(SharedSettings[walkMinutesFor: set.id] == 17)
        // Other stations keep their own value.
        #expect(SharedSettings[walkMinutesFor: unset.id] == SharedSettings.defaultWalkMinutes)
    }

    @Test func pinnedStationRoundTripsIncludingNil() async {
        let provider = LiveLeaveBy(board: { _, _ in .noTrains })
        await provider.pin(voiron)
        #expect(await provider.pinnedStation() == voiron)
        await provider.pin(nil)
        #expect(await provider.pinnedStation() == nil)
    }
}
