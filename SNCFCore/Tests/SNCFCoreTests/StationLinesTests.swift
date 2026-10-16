import Foundation
import Testing
@testable import SNCFCore

/// The station line map: the `depth=2` terminus parse, grouping by terminus, folding into "Other", the
/// two sides of the line, the time axis and the label rows. Fixtures and made-up trains only; reuses the
/// shared `at`/`paris`/`fixture`.
@Suite struct StationLinesTests {
    private static let lyon = Station(id: "stop_area:SNCF:87723197", name: "Lyon Part Dieu", latitude: 45.760585, longitude: 4.859435)
    private static let chambery = Station(id: "C", name: "Chambéry", latitude: 45.571156, longitude: 5.920660)
    private static let annecy = Station(id: "N", name: "Annecy", latitude: 45.901200, longitude: 6.121900)
    private static let valence = Station(id: "V", name: "Valence Ville", latitude: 44.926650, longitude: 4.893466)
    private static let gap = Station(id: "G", name: "Gap", latitude: 44.559600, longitude: 6.079000)
    private static let standre = Station(id: "S", name: "St-André-le-Gaz", latitude: 45.545100, longitude: 5.528600)
    private static let gieres = Station(id: "U", name: "Grenoble Universités-Gières", latitude: 45.185600, longitude: 5.781100)

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
        let lanes = StationLines.lanes(from: trains, now: at(17, 40))
        #expect(lanes.map(\.name) == ["Lyon Part Dieu", "Chambéry", "Rives (Rives)"])
        #expect(lanes[0].trains.map(\.scheduledDeparture) == [at(17, 47), at(18, 47)])
        // The cancelled 17:52 stays listed but is never the next one.
        #expect(lanes[1].trains.count == 2)
        #expect(lanes[1].next?.scheduledDeparture == at(18, 22))
        #expect(lanes[2].terminus == nil)
    }

    @Test func aLaneWhoseTrainsAreAllCancelledHasNoNext() {
        let lanes = StationLines.lanes(from: [train(18, 0, to: Self.gap, cancelled: true)], now: at(17, 40))
        #expect(lanes.count == 1)
        #expect(lanes[0].next == nil)
    }

    @Test func theSmallestTerminiFoldIntoOther() {
        // Five termini, room for three: the two busiest keep a lane, the rest share "Other".
        let trains = [
            train(17, 45, to: Self.gap),
            train(17, 50, to: Self.lyon), train(18, 50, to: Self.lyon), train(19, 50, to: Self.lyon),
            train(17, 55, to: Self.annecy),
            train(18, 0, to: Self.valence), train(19, 0, to: Self.valence),
            train(18, 5, to: Self.chambery),
        ]
        let lanes = StationLines.lanes(from: trains, now: at(17, 40), maxLanes: 3)
        #expect(lanes.map(\.name) == ["Lyon Part Dieu", "Valence Ville", "Other destinations"])
        #expect(lanes[2].isOther)
        #expect(lanes[2].trains.compactMap(\.direction) == ["Gap", "Annecy", "Chambéry"])
        #expect(StationLines.lanes(from: trains, now: at(17, 40), maxLanes: 8).count == 5)
    }

    // MARK: Sides

    @Test func bearingsReadLikeAMap() {
        let grenoble = BigScreenFixtures.grenoble
        let lyon = StationLines.bearing(from: grenoble, to: Self.lyon)
        #expect(lyon > 270 && lyon < 360)                          // up-left
        #expect(StationLines.bearing(from: grenoble, to: Self.valence) > 180)
        #expect(StationLines.bearing(from: grenoble, to: Self.valence) < 270)
        let gap = StationLines.bearing(from: grenoble, to: Self.gap)
        #expect(gap > 90 && gap < 180)                             // down-right
        #expect(abs(StationLines.bearing(from: Station(id: "", name: "", latitude: 45, longitude: 5),
                                         to: Station(id: "", name: "", latitude: 46, longitude: 5))) < 0.001)
    }

    /// Voiron: Lyon and St-André up the line to the north-west, Grenoble and Gières down it to the south-east,
    /// and Valence off to the south-west, which still rides with Grenoble because it leaves via Moirans.
    @Test func voironSplitsAtItsTwoWidestGaps() {
        let voiron = BigScreenFixtures.voiron
        let termini = [Self.lyon, Self.standre, BigScreenFixtures.grenoble, Self.gieres, Self.valence]
        let sides = StationLines.sides(for: termini.map { StationLines.bearing(from: voiron, to: $0) })
        #expect(sides.above.map { termini[$0].name } == ["Lyon Part Dieu", "St-André-le-Gaz"])
        #expect(sides.below.map { termini[$0].name } == ["Grenoble Universités-Gières", "Grenoble", "Valence Ville"])
    }

    @Test func terminiWithoutCoordinatesJoinTheBiggerSide() {
        let sides = StationLines.sides(for: [320, nil, 150, 160, 230])
        #expect(sides.above == [0])
        #expect(sides.below == [2, 3, 4, 1])
    }

    @Test func oneFanOrNoBearingsPutsEverythingAbove() {
        #expect(StationLines.sides(for: [nil, nil]) == ([0, 1], []))
        #expect(StationLines.sides(for: [90, nil]) == ([0, 1], []))
        #expect(StationLines.sides(for: [90, 90, 90]) == ([0, 1, 2], []))
    }

    @Test func theNorthernFanGoesAboveWhicheverWayTheCircleIsCut() {
        // Two lanes due south, one due north: the lone northern one still takes the top.
        #expect(StationLines.sides(for: [175, 185, 0]) == ([2], [0, 1]))
    }

    @Test func compassWords() {
        #expect(StationLines.compass(308) == "NORTH-WEST")
        #expect(StationLines.compass(153) == "SOUTH-EAST")
        #expect(StationLines.compass(359) == "NORTH")
        #expect(StationLines.compass(90) == "EAST")
    }

    // MARK: Time

    @Test func theWindowIsTwoAndAHalfHoursOrTheEveningToThree() {
        let now = at(17, 40)
        #expect(StationLines.windowEnd(now: now, tonight: false, lastDeparture: at(23, 0), calendar: paris) == at(20, 10))
        #expect(StationLines.windowEnd(now: now, tonight: true, lastDeparture: at(22, 0), calendar: paris) == at(22, 15))
        #expect(StationLines.windowEnd(now: now, tonight: true, lastDeparture: at(18, 0), calendar: paris) == at(20, 10))
        #expect(StationLines.windowEnd(now: now, tonight: true, lastDeparture: nil, calendar: paris)
            == at(3, 0).addingTimeInterval(24 * 3600))
    }

    @Test func hoursAndQuartersOnTheAxis() {
        let marks = StationLines.marks(from: at(17, 40), to: at(20, 10), calendar: paris)
        #expect(marks.hours == [at(18, 0), at(19, 0), at(20, 0)])
        #expect(marks.quarters.first == at(17, 45))
        #expect(marks.quarters.count == 7)
    }

    @Test func aRegularServiceSaysHowOften() {
        #expect(StationLines.frequency(of: [at(17, 51), at(18, 21), at(18, 51), at(19, 21)]) == "EVERY 30 MIN")
        // 12/18 alternating, the Grenoble pattern: the median is 15 and every gap is within 3 of it.
        #expect(StationLines.frequency(of: [at(17, 46), at(17, 58), at(18, 16), at(18, 28), at(18, 46)]) == "EVERY 15 MIN")
        #expect(StationLines.frequency(of: [at(18, 10), at(19, 10)]) == "HOURLY")
        #expect(StationLines.frequency(of: [at(18, 0), at(20, 0)]) == "EVERY 2 H")
        #expect(StationLines.frequency(of: [at(18, 0), at(18, 30), at(20, 0)]) == nil)
        #expect(StationLines.frequency(of: [at(18, 0)]) == nil)
    }

    // MARK: Labels

    @Test func theMockupsGrenobleClusterLiftsTwoLabels() {
        // Next 17:46 with its countdown, 17:58, the +24 at 18:40, 18:28, 18:46, at 4.33 pt a minute.
        let spans: [ClosedRange<Double>] = [442...567, 484...532, 644...737, 614...662, 692...740]
        #expect(StationLines.labelRows(spans) == [.below, .above, .below, .above, .above])
    }

    @Test func aLabelWithNoRoomOnEitherRowIsHidden() {
        #expect(StationLines.labelRows([0...100, 50...150, 90...120]) == [.below, .above, .hidden])
        #expect(StationLines.labelRows([0...100, 50...150], allowAbove: false) == [.below, .hidden])
    }

    @Test func monoWidthIsSixTenthsOfAnEm() {
        #expect(StationLines.monoWidth("17:51", size: 16) == 48)
    }

    // MARK: Providers

    @Test func theServiceDayWindowRunsToThreeAndNeverUnderTheFloor() {
        #expect(BoardState.restOfServiceDay(after: at(18, 0), atLeast: 2 * 3600, calendar: paris) == 9 * 3600)
        #expect(BoardState.restOfServiceDay(after: at(2, 0), atLeast: 2 * 3600, calendar: paris) == 2 * 3600)
    }

    @Test func theBoardAsksTheWindowAndFallsBackToTheCountAtNight() async {
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
