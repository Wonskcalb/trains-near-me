import Foundation
import Testing
@testable import SNCFCore

/// Live boards, station board and train-stops providers, exercised through their fixture seam so no test
/// touches the network. Reuses the shared `at`/`paris`/`fixture`/`grenoble`/`voiron` helpers.
@Suite struct BigScreenBoards {

    // MARK: Journey boards

    private func config(_ a: Station, _ b: Station) -> JourneyConfiguration {
        JourneyConfiguration(stationA: a, stationB: b, direction: .forward)
    }

    private var sampleTrains: [TrainDeparture] {
        [TrainDeparture(scheduledDeparture: at(18, 0), scheduledArrival: at(18, 30),
                        delayMinutes: 0, isCancelled: false, trainNumber: "1")]
    }

    @Test func oneFailingJourneyDegradesToUnavailableKeepingTheRest() async {
        let a = Station(id: "A", name: "A", latitude: 45.0, longitude: 5.0)
        let b = Station(id: "B", name: "B", latitude: 45.1, longitude: 5.1)
        let c = Station(id: "C", name: "C", latitude: 45.2, longitude: 5.2)
        let configs = [config(a, b), config(a, c), config(b, c)]
        let trains = sampleTrains

        let fetch: LiveJourneyBoards.Fetch = { leg, _ in
            if leg.from.id == "A", leg.to.id == "C" { throw TrainServiceError.quotaExceeded }
            return trains
        }
        let provider = LiveJourneyBoards(favorites: { configs }, location: { nil }, calendar: paris, maxConcurrent: 2, fetch: fetch)

        let boards = await provider.boards(at: at(18, 0))
        #expect(boards.count == 3)
        #expect(boards.map { $0.leg.to.id } == ["B", "C", "C"])   // saved order preserved
        #expect(boards[1].state == .unavailable(.quotaExceeded))  // the failing one, not dropped
        #expect(boards[0].state == .departures(trains))
        #expect(boards[2].state == .departures(trains))
    }

    @Test func boardsResolveTheLegAndNowFromTheConfiguration() async {
        let trains = sampleTrains
        let fetch: LiveJourneyBoards.Fetch = { _, _ in trains }
        let provider = LiveJourneyBoards(
            favorites: { [JourneyConfiguration(stationA: grenoble, stationB: voiron, direction: .automatic, switchMinute: 13 * 60)] },
            location: { nil }, calendar: paris, maxConcurrent: 4, fetch: fetch)

        // Before the 13:00 switch it reads forward, after it reverses.
        #expect(await provider.boards(at: at(12, 0))[0].leg == Leg(from: grenoble, to: voiron))
        #expect(await provider.boards(at: at(14, 0))[0].leg == Leg(from: voiron, to: grenoble))
    }

    @Test func noFavouritesIsNoBoards() async {
        let fetch: LiveJourneyBoards.Fetch = { _, _ in [] }
        let provider = LiveJourneyBoards(favorites: { [] }, location: { nil }, calendar: paris, fetch: fetch)
        #expect(await provider.boards(at: at(18, 0)).isEmpty)
    }

    @Test func boardsAskedTogetherShareOneRoundUntilInvalidated() async {
        let calls = Counter()
        let trains = sampleTrains
        let fetch: LiveJourneyBoards.Fetch = { _, _ in await calls.bump(); return trains }
        let provider = LiveJourneyBoards(favorites: { [JourneyConfiguration(stationA: grenoble, stationB: voiron)] },
                                         location: { nil }, calendar: paris, fetch: fetch)

        // The sidebar and the detail screen on the same appear, then again 30 s later.
        async let sidebar = provider.boards(at: at(18, 0))
        async let detail = provider.boards(at: at(18, 0))
        #expect(await sidebar == detail)
        _ = await provider.boards(at: at(18, 0).addingTimeInterval(30))
        #expect(await calls.count == 1)

        // ⌘R forgets the memo; so does the minute running out.
        await provider.invalidate()
        _ = await provider.boards(at: at(18, 1))
        #expect(await calls.count == 2)
        _ = await provider.boards(at: at(18, 3))
        #expect(await calls.count == 3)
    }

    @Test func everyRawBoardIsHandedToTheWatcherHook() async {
        let seen = Seen()
        let cancelled = TrainDeparture(scheduledDeparture: at(18, 0), scheduledArrival: at(18, 30),
                                       delayMinutes: 0, isCancelled: true, trainNumber: "1")
        let fetch: LiveJourneyBoards.Fetch = { _, _ in [cancelled] }
        let provider = LiveJourneyBoards(favorites: { [JourneyConfiguration(stationA: grenoble, stationB: voiron)] },
                                         location: { nil }, calendar: paris,
                                         observe: { trains, leg in await seen.add(trains, leg) }, fetch: fetch)
        // The board collapses to `.noService`, but the hook still saw the cancelled row itself.
        #expect(await provider.boards(at: at(17, 0))[0].state == .noService)
        #expect(await seen.trains == [cancelled])
        #expect(await seen.legs == [Leg(from: grenoble, to: voiron)])
    }

    // MARK: Station board + via cache

    @Test func stationBoardMapsDeparturesAndDegradesOnError() async {
        let trains = [TrainDeparture(scheduledDeparture: at(18, 0), direction: "Lyon",
                                     delayMinutes: 0, isCancelled: false, trainNumber: "1")]
        let okBoard: LiveStationBoard.BoardFetch = { _, _ in trains }
        let noTrip: LiveStationBoard.TripFetch = { _ in [] }
        let ok = LiveStationBoard(calendar: paris, board: okBoard, trip: noTrip)
        #expect(await ok.board(for: grenoble, at: at(18, 0)) == .departures(trains))

        let downBoard: LiveStationBoard.BoardFetch = { _, _ in throw TrainServiceError.offline }
        let down = LiveStationBoard(calendar: paris, board: downBoard, trip: noTrip)
        #expect(await down.board(for: grenoble, at: at(18, 0)) == .unavailable(.offline))
    }

    @Test func viaCacheFetchesEachVehicleJourneyOnce() async {
        let calls = Counter()
        let stops = [TripStop(name: "Origin", time: "10:00", isSkipped: false),
                     TripStop(name: "Mid 1", time: "10:10", isSkipped: false),
                     TripStop(name: "Mid 2", time: "10:20", isSkipped: false),
                     TripStop(name: "Terminus", time: "10:30", isSkipped: false)]
        let noBoard: LiveStationBoard.BoardFetch = { _, _ in [] }
        let trip: LiveStationBoard.TripFetch = { _ in await calls.bump(); return stops }
        let provider = LiveStationBoard(calendar: paris, maxVia: 3, board: noBoard, trip: trip)

        let first = await provider.via(forVehicleJourneyID: "vj:1")
        let second = await provider.via(forVehicleJourneyID: "vj:1")
        #expect(first == ["Mid 1", "Mid 2"])    // origin + terminus dropped
        #expect(second == first)
        #expect(await calls.count == 1)          // the second read is cached, no new trip()
    }

    @Test func aFailedViaLookupIsAskedAgain() async {
        let calls = Counter()
        let noBoard: LiveStationBoard.BoardFetch = { _, _ in [] }
        let trip: LiveStationBoard.TripFetch = { _ in await calls.bump(); throw TrainServiceError.offline }
        let provider = LiveStationBoard(calendar: paris, board: noBoard, trip: trip)
        #expect(await provider.via(forVehicleJourneyID: "vj:1").isEmpty)
        #expect(await provider.via(forVehicleJourneyID: "vj:1").isEmpty)
        #expect(await calls.count == 2)          // a blip is not remembered as "direct"
    }

    @Test func viaListFromARealTripIsCapped() async throws {
        // vehicle_journey.json is a 10-stop Grenoble → Genève run; the via keeps the first three middles.
        let stops = try NavitiaParser.tripStops(from: fixture("vehicle_journey"))
        let noBoard: LiveStationBoard.BoardFetch = { _, _ in [] }
        let trip: LiveStationBoard.TripFetch = { _ in stops }
        let provider = LiveStationBoard(calendar: paris, maxVia: 3, board: noBoard, trip: trip)
        #expect(await provider.via(forVehicleJourneyID: "x")
                == ["Grenoble Universités - Gières", "Pontcharra sur Bréda - Allevard", "Montmélian"])
    }

    @Test func viaDerivationDropsEndsAndSkippedStops() {
        #expect(LiveStationBoard.via(from: [], max: 3).isEmpty)
        let direct = [TripStop(name: "A", time: "1", isSkipped: false), TripStop(name: "B", time: "2", isSkipped: false)]
        #expect(LiveStationBoard.via(from: direct, max: 3).isEmpty)   // nothing between origin and terminus
        let withSkip = [TripStop(name: "A", time: "1", isSkipped: false),
                        TripStop(name: "Passed", time: "2", isSkipped: true),
                        TripStop(name: "Kept", time: "3", isSkipped: false),
                        TripStop(name: "B", time: "4", isSkipped: false)]
        #expect(LiveStationBoard.via(from: withSkip, max: 3) == ["Kept"])
    }

    // MARK: Train stops

    @Test func trainStopsPassesThroughTheFetch() async throws {
        let stops = [TripStop(name: "A", time: "10:00", isSkipped: false)]
        let okFetch: LiveTrainStops.Fetch = { _ in stops }
        let ok = LiveTrainStops(fetch: okFetch)
        #expect(try await ok.stops(forVehicleJourneyID: "x") == stops)

        let badFetch: LiveTrainStops.Fetch = { _ in throw TrainServiceError.malformedResponse }
        let bad = LiveTrainStops(fetch: badFetch)
        await #expect(throws: TrainServiceError.malformedResponse) {
            try await bad.stops(forVehicleJourneyID: "x")
        }
    }
}

/// Counts fetch-seam calls across concurrency boundaries in a test.
private actor Counter {
    private var value = 0
    func bump() { value += 1 }
    var count: Int { value }
}

/// What the watcher hook was handed.
private actor Seen {
    private(set) var trains: [TrainDeparture] = []
    private(set) var legs: [Leg] = []
    func add(_ trains: [TrainDeparture], _ leg: Leg) { self.trains += trains; legs.append(leg) }
}
