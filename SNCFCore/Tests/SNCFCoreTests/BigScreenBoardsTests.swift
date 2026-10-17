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

        let fetch: LiveJourneyBoards.Fetch = { leg, _ throws(TrainServiceError) in
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

    // MARK: Tomorrow, late in the evening

    private func train(_ h: Int, _ m: Int, cancelled: Bool = false, day: Int = 8) -> TrainDeparture {
        let departure = paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
        return TrainDeparture(scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(1800),
                              delayMinutes: 0, isCancelled: cancelled, trainNumber: "\(day)\(h)\(m)")
    }

    @Test func tonightIsNearlyDoneBelowThreeRunningTrains() {
        let three = BoardState.departures([train(21, 0), train(22, 0), train(23, 0)])
        #expect(!three.tonightIsNearlyDone(at: at(20, 0)))
        #expect(three.tonightIsNearlyDone(at: at(21, 0)))           // the 21:00 has left: two to go
        // A cancelled train is not one you can catch.
        #expect(BoardState.departures([train(21, 0), train(22, 0, cancelled: true), train(23, 0)])
                    .tonightIsNearlyDone(at: at(20, 0)))
        #expect(BoardState.endOfService(firstTrain: at(5, 42)).tonightIsNearlyDone(at: at(23, 30)))
        #expect(BoardState.noService.tonightIsNearlyDone(at: at(22, 0)))
        #expect(!BoardState.unavailable(.offline).tonightIsNearlyDone(at: at(22, 0)))
    }

    @Test func theMorningIsAskedOnlyWhenTonightIsNearlyDone() async {
        let asked = Asked()
        let evening = [train(18, 0), train(18, 30), train(19, 0), train(23, 10)]
        let morning = [train(5, 42, day: 9), train(6, 12, day: 9)]
        let fetch: LiveJourneyBoards.Fetch = { _, now in evening.filter { $0.scheduledDeparture > now } }
        let tomorrow: LiveJourneyBoards.Fetch = { _, opens in await asked.add(opens); return morning }
        let provider = LiveJourneyBoards(favorites: { [self.config(grenoble, voiron)] }, location: { nil }, calendar: paris,
                                         memoLifetime: 0, tomorrow: tomorrow, fetch: fetch)

        // 17:50: four trains to go, no extra request and no morning on the board.
        #expect(await provider.boards(at: at(17, 50))[0].tomorrow.isEmpty)
        #expect(await asked.dates.isEmpty)

        // 22:00: only the 23:10 left, so one more request, from the next 03:00.
        let late = await provider.boards(at: at(22, 0))[0]
        #expect(late.state == .departures([train(23, 10)]))
        #expect(late.tomorrow == morning)
        let opens = paris.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 3, minute: 0))!
        #expect(await asked.dates == [opens])
    }

    @Test func theMorningKeepsTheNextServiceDayOnlyAndFailsQuietly() async {
        let morning = [train(5, 42, day: 9), train(6, 12, day: 9), train(4, 0, day: 10)]
        let tonight: LiveJourneyBoards.Fetch = { _, _ in [] }
        let tomorrow: LiveJourneyBoards.Fetch = { _, _ in morning }
        let provider = LiveJourneyBoards(favorites: { [] }, location: { nil }, calendar: paris, tomorrow: tomorrow, fetch: tonight)
        #expect(await provider.board(for: Leg(from: grenoble, to: voiron), at: at(23, 30)).tomorrow == Array(morning.prefix(2)))

        let failing: LiveJourneyBoards.Fetch = { _, _ throws(TrainServiceError) in throw TrainServiceError.offline }
        let down = LiveJourneyBoards(favorites: { [] }, location: { nil }, calendar: paris, tomorrow: failing, fetch: tonight)
        let board = await down.board(for: Leg(from: grenoble, to: voiron), at: at(23, 30))
        #expect(board.state == .noTrains)
        #expect(board.tomorrow.isEmpty)
    }

    /// 23:30, the last train gone, and the window holding only tomorrow's cancelled 06:39: the board is
    /// the end of service with the first train the morning names (07:24), never "no service".
    @Test func afterTheLastTrainACancelledFirstTrainTomorrowIsEndOfService() async {
        let tonight: LiveJourneyBoards.Fetch = { _, _ in [self.train(6, 39, cancelled: true, day: 9)] }
        let morning = [train(6, 39, cancelled: true, day: 9), train(7, 24, day: 9)]
        let tomorrow: LiveJourneyBoards.Fetch = { _, _ in morning }
        let provider = LiveJourneyBoards(favorites: { [] }, location: { nil }, calendar: paris, tomorrow: tomorrow, fetch: tonight)
        let board = await provider.board(for: Leg(from: grenoble, to: voiron), at: at(23, 30))
        #expect(board.state == .endOfService(firstTrain: train(7, 24, day: 9).scheduledDeparture))
        #expect(board.tomorrow == morning)
    }

    // MARK: Station board + via cache

    @Test func stationBoardMapsDeparturesAndDegradesOnError() async {
        let trains = [TrainDeparture(scheduledDeparture: at(18, 0), direction: "Lyon",
                                     delayMinutes: 0, isCancelled: false, trainNumber: "1")]
        let okBoard: LiveStationBoard.BoardFetch = { _, _ in trains }
        let noTrip: LiveStationBoard.TripFetch = { _ in [] }
        let ok = LiveStationBoard(calendar: paris, board: okBoard, trip: noTrip)
        #expect(await ok.board(for: grenoble, at: at(18, 0)) == .departures(trains))

        let downBoard: LiveStationBoard.BoardFetch = { _, _ throws(TrainServiceError) in throw TrainServiceError.offline }
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
        let trip: LiveStationBoard.TripFetch = { _ throws(TrainServiceError) in await calls.bump(); throw TrainServiceError.offline }
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

        let badFetch: LiveTrainStops.Fetch = { _ throws(TrainServiceError) in throw TrainServiceError.malformedResponse }
        let bad = LiveTrainStops(fetch: badFetch)
        await #expect(throws: TrainServiceError.malformedResponse) {
            try await bad.stops(forVehicleJourneyID: "x")
        }
    }

    @Test func trainStopsAreFetchedOncePerVehicleJourney() async throws {
        // ↑↓ back over a row, ⌘R and a reopened popover all ask again: one trip() per run for the session.
        let calls = Counter()
        let stops = [TripStop(name: "A", time: "10:00", isSkipped: false)]
        let fetch: LiveTrainStops.Fetch = { _ in await calls.bump(); return stops }
        let provider = LiveTrainStops(fetch: fetch)
        #expect(try await provider.stops(forVehicleJourneyID: "vj:1") == stops)
        #expect(try await provider.stops(forVehicleJourneyID: "vj:1") == stops)
        #expect(await calls.count == 1)
        _ = try await provider.stops(forVehicleJourneyID: "vj:2")
        #expect(await calls.count == 2)
    }

    @Test func aFailedStopsLookupIsAskedAgain() async {
        let calls = Counter()
        let fetch: LiveTrainStops.Fetch = { _ throws(TrainServiceError) in await calls.bump(); throw TrainServiceError.offline }
        let provider = LiveTrainStops(fetch: fetch)
        _ = try? await provider.stops(forVehicleJourneyID: "vj:1")
        _ = try? await provider.stops(forVehicleJourneyID: "vj:1")
        #expect(await calls.count == 2)
    }

    // MARK: Lanes' morning

    @Test func theMorningIsFetchedOncePerLegAndKeepsTheNextServiceDay() async {
        let asked = Asked()
        let morning = [train(5, 42, day: 9), train(6, 12, day: 9), train(3, 10, day: 10)]
        let tomorrow: LiveJourneyBoards.Fetch = { _, opens in await asked.add(opens); return morning }
        let provider = LiveJourneyBoards(favorites: { [] }, location: { nil }, calendar: paris,
                                         tomorrow: tomorrow, fetch: { _, _ in [] })
        let leg = Leg(from: grenoble, to: voiron)

        // 17:50 on the 8th: the 9th's morning, in one request, whatever the evening asks after.
        #expect(await provider.morning(for: leg, at: at(17, 50)) == Array(morning.prefix(2)))
        #expect(await provider.morning(for: leg, at: at(21, 0)) == Array(morning.prefix(2)))
        let opens = paris.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 3, minute: 0))!
        #expect(await asked.dates == [opens])
        // The other way is its own leg.
        _ = await provider.morning(for: Leg(from: voiron, to: grenoble), at: at(17, 50))
        #expect(await asked.dates.count == 2)
    }

    // MARK: Polling on its own

    @Test func aPollerStopsAfterTheLastTrainUntilTheMorning() {
        let refresh = RefreshPlanner.refreshInterval
        // A train still to run tonight: the regular quarter-hour.
        #expect(RefreshPlanner.nextPoll(after: at(22, 0), state: .departures([train(22, 42)]), tomorrow: [])
                == at(22, 0).addingTimeInterval(refresh))
        // The last one gone, the morning known: nothing until half an hour before its first train.
        let morning = [train(5, 42, day: 9)]
        #expect(RefreshPlanner.nextPoll(after: at(22, 50), state: .departures([train(22, 42)]), tomorrow: morning)
                == train(5, 12, day: 9).scheduledDeparture)
        #expect(RefreshPlanner.nextPoll(after: at(23, 30), state: .endOfService(firstTrain: train(5, 42, day: 9).scheduledDeparture), tomorrow: [])
                == train(5, 12, day: 9).scheduledDeparture)
        // Nothing to name: an idle hour. An error: the regular retry.
        #expect(RefreshPlanner.nextPoll(after: at(23, 30), state: .noTrains, tomorrow: [])
                == at(23, 30).addingTimeInterval(RefreshPlanner.idleRefreshInterval))
        #expect(RefreshPlanner.nextPoll(after: at(23, 30), state: .unavailable(.offline), tomorrow: [])
                == at(23, 30).addingTimeInterval(refresh))
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

/// The dates the tomorrow seam was asked from.
private actor Asked {
    private(set) var dates: [Date] = []
    func add(_ date: Date) { dates.append(date) }
}
