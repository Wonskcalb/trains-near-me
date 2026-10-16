import Foundation
import Testing
@testable import SNCFCore

/// The station star: the `depth=2` terminus parse, grouping by terminus, folding into "Other", and the
/// bearing-to-angle layout. Fixtures and made-up trains only; reuses the shared `at`/`paris`/`fixture`.
@Suite struct StationStarTests {
    private static let lyon = Station(id: "stop_area:SNCF:87723197", name: "Lyon Part Dieu", latitude: 45.760585, longitude: 4.859435)
    private static let chambery = Station(id: "C", name: "Chambéry", latitude: 45.571156, longitude: 5.920660)
    private static let annecy = Station(id: "N", name: "Annecy", latitude: 45.901200, longitude: 6.121900)
    private static let valence = Station(id: "V", name: "Valence Ville", latitude: 44.926650, longitude: 4.893466)
    private static let gap = Station(id: "G", name: "Gap", latitude: 44.559600, longitude: 6.079000)

    private func train(_ h: Int, _ m: Int, to terminus: Station?, headsign: String? = nil,
                       delay: Int? = 0, cancelled: Bool = false) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: at(h, m), direction: headsign ?? terminus?.name, delayMinutes: delay,
                       isCancelled: cancelled, trainNumber: "\(h)\(m)", terminus: terminus)
    }

    // MARK: Parse

    @Test func depth2BoardCarriesEachTrainsTerminus() throws {
        let board = try NavitiaParser.stopDepartures(from: fixture("stop_departures_depth2"))
        #expect(board.count == 5)
        #expect(board[0].terminus == Self.lyon)
        #expect(board[1].terminus?.id == "stop_area:SNCF:87741009")
        #expect(board[2].terminus?.latitude == 44.928382)
        // A short working on the Lyon route: its headsign is not the route's end, so no terminus.
        #expect(board[3].direction == "Saint-André-le-Gaz (Saint-André-le-Gaz)")
        #expect(board[3].terminus == nil)
    }

    @Test func theTrimmedBoardHasNoTerminus() throws {
        #expect(try NavitiaParser.stopDepartures(from: fixture("stop_departures")).allSatisfy { $0.terminus == nil })
    }

    /// A board cached by a build before `terminus` existed still decodes.
    @Test func anOldCachedTrainStillDecodes() throws {
        let old = Data(#"{"scheduledDeparture": 0, "isCancelled": false, "delayMinutes": 3, "direction": "Lyon"}"#.utf8)
        let train = try JSONDecoder().decode(TrainDeparture.self, from: old)
        #expect(train.terminus == nil)
        #expect(train.delayMinutes == 3)
    }

    // MARK: Grouping

    @Test func groupsByTerminusSoonestFirstAndSkipsDepartedTrains() {
        let trains = [
            train(17, 30, to: Self.lyon),                       // already left
            train(17, 47, to: Self.lyon),
            train(17, 52, to: Self.chambery, cancelled: true),
            train(18, 22, to: Self.chambery),
            train(18, 47, to: Self.lyon),
            train(19, 0, to: nil, headsign: "Rives (Rives)"),
        ]
        let branches = StationStar.branches(from: trains, now: at(17, 40))
        #expect(branches.map(\.name) == ["Lyon Part Dieu", "Chambéry", "Rives (Rives)"])
        #expect(branches[0].trains.map(\.scheduledDeparture) == [at(17, 47), at(18, 47)])
        // The cancelled 17:52 stays listed but is never the next one.
        #expect(branches[1].trains.count == 2)
        #expect(branches[1].next?.scheduledDeparture == at(18, 22))
        #expect(branches[2].terminus == nil)
    }

    @Test func aBranchWhoseTrainsAreAllCancelledHasNoNext() {
        let branches = StationStar.branches(from: [train(18, 0, to: Self.gap, cancelled: true)], now: at(17, 40))
        #expect(branches.count == 1)
        #expect(branches[0].next == nil)
    }

    @Test func theSmallestTerminiFoldIntoOther() {
        // Five termini, room for three: the two busiest keep a branch, the rest share "Other".
        let trains = [
            train(17, 45, to: Self.gap),
            train(17, 50, to: Self.lyon), train(18, 50, to: Self.lyon), train(19, 50, to: Self.lyon),
            train(17, 55, to: Self.annecy),
            train(18, 0, to: Self.valence), train(19, 0, to: Self.valence),
            train(18, 5, to: Self.chambery),
        ]
        let branches = StationStar.branches(from: trains, now: at(17, 40), maxBranches: 3)
        #expect(branches.map(\.name) == ["Lyon Part Dieu", "Valence Ville", "Other destinations"])
        #expect(branches[2].isOther)
        #expect(branches[2].trains.compactMap(\.direction) == ["Gap", "Annecy", "Chambéry"])
        #expect(StationStar.branches(from: trains, now: at(17, 40), maxBranches: 8).count == 5)
    }

    // MARK: Layout

    @Test func bearingsReadLikeAMap() {
        let grenoble = BigScreenFixtures.grenoble
        let lyon = StationStar.bearing(from: grenoble, to: Self.lyon)
        #expect(lyon > 270 && lyon < 360)                          // up-left
        #expect(StationStar.bearing(from: grenoble, to: Self.valence) > 180)
        #expect(StationStar.bearing(from: grenoble, to: Self.valence) < 270)
        let gap = StationStar.bearing(from: grenoble, to: Self.gap)
        #expect(gap > 90 && gap < 180)                             // down-right
        #expect(abs(StationStar.bearing(from: Station(id: "", name: "", latitude: 45, longitude: 5),
                                        to: Station(id: "", name: "", latitude: 46, longitude: 5))) < 0.001)
    }

    @Test func wellSeparatedBearingsAreKeptAsIs() {
        let angles = StationStar.angles(for: [315, 20, 245, 160])
        #expect(zip(angles, [315.0, 20, 245, 160]).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test func closeBearingsArePushedApartSymmetrically() {
        // Chambéry and Annecy sit a degree apart seen from Grenoble.
        let angles = StationStar.angles(for: [20, 22])
        #expect(abs(angles[0] - 8.5) < 0.1)
        #expect(abs(angles[1] - 33.5) < 0.1)
    }

    @Test func aClusterAcrossNorthSpreadsWithoutReordering() {
        let angles = StationStar.angles(for: [355, 0, 5, 180])
        let gaps = [angles[1] - angles[0] + 360, angles[2] - angles[1]].map { StationStar.normalized($0) }
        #expect(gaps.allSatisfy { $0 >= 24.9 && $0 < 40 })
        #expect(abs(angles[3] - 180) < 0.001)
    }

    @Test func tooManyBranchesShareTheCircleEvenly() {
        let angles = StationStar.angles(for: Array(repeating: 90, count: 18)).sorted()
        let gaps = zip(angles.dropFirst(), angles).map { $0 - $1 }
        #expect(gaps.allSatisfy { $0 > 19 })
    }

    @Test func withoutCoordinatesTheBranchesSpreadEvenlyFromTheTop() {
        #expect(StationStar.angles(for: [nil, nil, nil, nil]) == [0, 90, 180, 270])
    }

    @Test func anUnknownBearingTakesTheWidestGap() {
        let angles = StationStar.angles(for: [0, 90, nil])
        #expect(abs(angles[2] - 225) < 0.001)
    }

    @Test func theServiceDayWindowRunsToThreeAndNeverUnderTheFloor() {
        #expect(BoardState.restOfServiceDay(after: at(18, 0), atLeast: 2 * 3600, calendar: paris) == 9 * 3600)
        #expect(BoardState.restOfServiceDay(after: at(2, 0), atLeast: 2 * 3600, calendar: paris) == 2 * 3600)
    }

    // MARK: Providers

    @Test func theStarAsksTheWindowAndFallsBackToTheCountAtNight() async {
        let tomorrow = TrainDeparture(scheduledDeparture: at(5, 42).addingTimeInterval(24 * 3600), delayMinutes: 0,
                                      isCancelled: false, trainNumber: "1")
        let tonight = train(18, 0, to: Self.lyon)
        let evening = LiveStationBoard(calendar: paris, board: { _, _ in [tomorrow] }, window: { _, _ in [tonight] }, trip: { _ in [] })
        #expect(await evening.serviceDayBoard(for: grenoble, at: at(17, 40)) == .departures([tonight]))
        let night = LiveStationBoard(calendar: paris, board: { _, _ in [tomorrow] }, window: { _, _ in [] }, trip: { _ in [] })
        #expect(await night.serviceDayBoard(for: grenoble, at: at(23, 50)) == .endOfService(firstTrain: tomorrow.scheduledDeparture))
    }

    @Test func anUnsavedLegIsFetchedOnDemand() async {
        let trains = [TrainDeparture(scheduledDeparture: at(18, 0), scheduledArrival: at(19, 17), delayMinutes: 0,
                                     isCancelled: false, trainNumber: "17614")]
        let provider = LiveJourneyBoards(favorites: { [] }, location: { nil }, calendar: paris, fetch: { leg, _ in
            leg.to.id == Self.lyon.id ? trains : []
        })
        let board = await provider.board(for: Leg(from: grenoble, to: Self.lyon), at: at(17, 40))
        #expect(board.state == .departures(trains))
        #expect(board.journey == JourneyConfiguration(stationA: grenoble, stationB: Self.lyon))
    }
}
