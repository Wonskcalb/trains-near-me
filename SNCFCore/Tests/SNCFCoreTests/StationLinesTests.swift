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

    @Test func aTerminusMustBeTheHeadsignNotJustItsStart() {
        let lyon = StopArea(id: "stop_area:SNCF:lyon", name: "Lyon", coord: Coord(lat: "45.7", lon: "4.8"))
        // "Lyon Perrache (Lyon)" starts with "Lyon" but runs to another station than the stop_area "Lyon".
        #expect(NavitiaParser.terminus(lyon, headsign: "Lyon Perrache (Lyon)") == nil)
        #expect(NavitiaParser.terminus(lyon, headsign: "Lyon (Lyon)")?.id == "stop_area:SNCF:lyon")
        let partDieu = StopArea(id: "pd", name: "Lyon Part-Dieu", coord: Coord(lat: "45.7", lon: "4.8"))
        #expect(NavitiaParser.terminus(partDieu, headsign: "Lyon Part Dieu (Lyon)")?.id == "pd")   // folded alike
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

    @Test func groupsByTerminusByNameAndSkipsDepartedTrains() {
        let trains = [
            train(17, 30, to: Self.lyon),                       // already left
            train(17, 47, to: Self.lyon),
            train(17, 52, to: Self.chambery, cancelled: true),
            train(18, 22, to: Self.chambery),
            train(18, 47, to: Self.lyon),
            train(19, 0, to: nil, headsign: "Rives (Rives)"),
        ]
        let lanes = StationLines.lanes(from: trains, now: at(17, 40))
        #expect(lanes.map(\.name) == ["Chambéry", "Lyon Part Dieu", "Rives (Rives)"])
        #expect(lanes[1].trains.map(\.scheduledDeparture) == [at(17, 47), at(18, 47)])
        // The cancelled 17:52 stays listed but is never the next one.
        #expect(lanes[0].trains.count == 2)
        #expect(lanes[0].next?.scheduledDeparture == at(18, 22))
        #expect(lanes[2].terminus == nil)
    }

    /// A train leaving must not reorder the lanes: termini without coordinates keep this order on the map,
    /// and a reshuffle on each departure both jumped the rows and cancelled the departure animation.
    @Test func aDepartureKeepsTheLaneOrder() {
        let trains = [
            train(17, 45, to: nil, headsign: "Rives (Rives)"),
            train(18, 30, to: nil, headsign: "Rives (Rives)"),
            train(17, 55, to: nil, headsign: "Lyon Perrache (Lyon)"),
            train(18, 10, to: nil, headsign: "Moirans (Moirans)"),
        ]
        let before = StationLines.lanes(from: trains, now: at(17, 40)).map(\.id)
        let after = StationLines.lanes(from: trains, now: at(17, 46)).map(\.id)   // the 17:45 to Rives left
        #expect(before == after)
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

    @Test func theBoardAsksTheWindowAndNamesTheFirstTrainFromTheMorningAtNight() async {
        let tomorrow = TrainDeparture(scheduledDeparture: at(5, 42).addingTimeInterval(24 * 3600), delayMinutes: 0,
                                      isCancelled: false, trainNumber: "1")
        let tonight = [train(18, 0, to: Self.lyon), train(18, 30, to: Self.lyon), train(19, 0, to: Self.lyon)]
        let evening = LiveStationBoard(calendar: paris, board: { _, _ in [tomorrow] }, window: { _, _ in tonight }, trip: { _ in [] })
        #expect(await evening.serviceDayBoard(for: grenoble, at: at(17, 40)) == StationDayBoard(state: .departures(tonight)))
        let night = LiveStationBoard(calendar: paris, board: { _, _ in [tomorrow] }, window: { _, _ in [] }, trip: { _ in [] })
        #expect(await night.serviceDayBoard(for: grenoble, at: at(23, 50))
            == StationDayBoard(state: .endOfService(firstTrain: tomorrow.scheduledDeparture), tomorrow: [tomorrow]))
    }

    @Test func theStationsMorningIsAskedOnceFromThreeOnlyWhenTonightIsNearlyDone() async {
        let asked = AskedDates()
        let evening = [train(18, 0, to: Self.lyon), train(18, 30, to: Self.lyon), train(19, 0, to: Self.lyon), train(23, 10, to: Self.lyon)]
        let day9 = { (h: Int, m: Int) in at(h, m).addingTimeInterval(24 * 3600) }
        let morning = [day9(6, 12), day9(5, 42), at(4, 0).addingTimeInterval(48 * 3600)].map {
            TrainDeparture(scheduledDeparture: $0, delayMinutes: 0, isCancelled: false, trainNumber: nil, terminus: Self.lyon)
        }
        let board = LiveStationBoard(calendar: paris, board: { _, _ in [] },
                                     window: { _, now in evening.filter { $0.scheduledDeparture > now } },
                                     tomorrow: { _, opens in await asked.add(opens); return morning }, trip: { _ in [] })

        // 17:50: four to go, no extra request.
        #expect(await board.serviceDayBoard(for: grenoble, at: at(17, 50)).tomorrow.isEmpty)
        #expect(await asked.dates.isEmpty)

        // 22:00: the 23:10 alone, so the morning from the next 03:00, sorted and cut to that service day.
        let late = await board.serviceDayBoard(for: grenoble, at: at(22, 0))
        #expect(late.state == .departures([evening[3]]))
        #expect(late.tomorrow.map(\.scheduledDeparture) == [day9(5, 42), day9(6, 12)])
        #expect(await asked.dates == [day9(3, 0)])
    }

    @Test func aFailedMorningLeavesTonightStanding() async {
        let tonight = [train(23, 10, to: Self.lyon)]
        let failing: LiveStationBoard.BoardFetch = { _, _ in throw TrainServiceError.offline }
        let board = LiveStationBoard(calendar: paris, board: { _, _ in [] }, window: { _, _ in tonight },
                                     tomorrow: failing, trip: { _ in [] })
        #expect(await board.serviceDayBoard(for: grenoble, at: at(22, 0)) == StationDayBoard(state: .departures(tonight)))
    }

    // MARK: Axis with the night folded

    @Test func withoutAMorningTheAxisIsTheWindow() {
        let axis = StationLines.axis(now: at(17, 40), tonight: false, lastTonight: at(23, 0), firstTomorrow: nil, calendar: paris)
        #expect(axis == StationLines.Axis(start: at(17, 40), end: at(20, 10)))
        #expect(axis.fraction(at(18, 55)) == 0.5)
    }

    @Test func theNightFoldsIntoABreakBeforeTwoHoursOfMorning() throws {
        let first = at(5, 16).addingTimeInterval(24 * 3600)
        let axis = StationLines.axis(now: at(22, 30), tonight: false, lastTonight: at(23, 21), firstTomorrow: first, calendar: paris)
        let gap = try #require(axis.gap)
        #expect(gap.start == at(23, 46))
        #expect(gap.end == first.addingTimeInterval(-15 * 60))
        #expect(axis.end == first.addingTimeInterval(2 * 3600))
        // 76 min of evening, 25 of break, 135 of morning on the track.
        #expect(abs(axis.fraction(gap.start) - 76.0 / 236) < 1e-9)
        #expect(abs(axis.fraction(gap.end) - 101.0 / 236) < 1e-9)
        #expect(axis.isFolded(at(2, 0).addingTimeInterval(24 * 3600)))
        #expect(!axis.isFolded(first))
    }

    @Test func withNothingLeftTonightTheRiverStartsAtTheBreak() {
        let first = at(5, 16).addingTimeInterval(24 * 3600)
        let axis = StationLines.axis(now: at(23, 40), tonight: false, lastTonight: nil, firstTomorrow: first, calendar: paris)
        #expect(axis.gap?.start == at(23, 40))
        #expect(axis.fraction(at(23, 40)) == 0)
    }

    @Test func aShortLookAheadKeepsItsWindowWhileTonightFillsIt() {
        let first = at(5, 16).addingTimeInterval(24 * 3600)
        let early = StationLines.axis(now: at(19, 0), tonight: false, lastTonight: at(22, 40), firstTomorrow: first, calendar: paris)
        #expect(early.gap == nil)
        #expect(early.end == at(21, 30))
        // TONIGHT reaches the last train anyway, so it breaks after it.
        let whole = StationLines.axis(now: at(19, 0), tonight: true, lastTonight: at(22, 40), firstTomorrow: first, calendar: paris)
        #expect(whole.gap?.start == at(23, 5))
    }

    // MARK: Map size

    /// Châtelet's eight lanes on one side of the line, on the folded Duo's ~420 pt of map: squeezing them
    /// in would put each chip on the next lane, so the pitch holds and the map grows past the viewport.
    @Test func aBusyStationScrollsRatherThanSqueeze() {
        let pitch = StationLines.pitch(rows: 9, height: 420 - 120)
        #expect(pitch == StationLines.minimumPitch)
        #expect(pitch - 2 * StationLines.labelOffset > 40)
        #expect(StationLines.pitch(rows: 9, height: 300, floor: StationLines.compactPitch) == 80)
        // Every lane above: the capsule (138 pt for eight exits) and its name need room under the axis row.
        let height = StationLines.mapHeight(above: 8, below: 0, pitch: pitch, capsuleHeight: 138)
        #expect(height == 60 + 8 * 96 + 129)
        #expect(height > 420)
        // A roomy screen spreads the rows, never past the mockup's pitch.
        #expect(StationLines.pitch(rows: 4, height: 900) == StationLines.maximumPitch)
        #expect(StationLines.pitch(rows: 4, height: 330) == 110)
        // Lanes on both sides cover the capsule: the plain 60 pt margins.
        #expect(StationLines.mapHeight(above: 2, below: 2, pitch: 110, capsuleHeight: 96) == 120 + 4 * 110)
    }

    @Test func aNarrowAxisKeepsItsMinimumScale() {
        let axis = StationLines.Axis(start: at(23, 54), end: at(23, 54).addingTimeInterval(150 * 60))
        #expect(axis.span == 150 * 60)
        #expect(StationLines.axisWidth(axis, available: 54, scale: StationLines.minimumScale) == 330)
        #expect(StationLines.axisWidth(axis, available: 600, scale: StationLines.minimumScale) == 600)
        #expect(StationLines.axisWidth(axis, available: 54, scale: 0) == 54)
        // The folded night counts as its 25 minutes of track, not seven hours.
        let folded = StationLines.Axis(start: at(23, 0), end: at(7, 0).addingTimeInterval(86_400),
                                       gap: DateInterval(start: at(23, 30), end: at(5, 0).addingTimeInterval(86_400)))
        #expect(folded.span == (30 + 25 + 120) * 60)
    }

    @Test func aNarrowCurveBandStillPeelsInsideIt() {
        let path = StationLines.LanePath(stationX: 22, exitY: 400, y: 380, curveEnd: 94, laneEnd: 600)
        #expect(path.peel.x == 58)
    }

    // MARK: Lane path

    @Test func theLanePathRunsFromTheCapsuleToTheTerminusByArcLength() {
        let path = StationLines.LanePath(stationX: 34, exitY: 400, y: 200, curveEnd: 356, laneEnd: 1060)
        #expect(path.point(at: 0) == CGPoint(x: 34, y: 400))
        let end = path.point(at: 1)
        #expect(abs(end.x - 1060) < 1e-9 && end.y == 200)
        // The S-curve is longer than its chord, shorter than its two legs.
        let curve = path.distance(toX: 356) - Double(path.peel.x - path.start.x)
        let chord = hypot(356 - Double(path.peel.x), 200.0)
        #expect(curve > chord && curve < 356 - Double(path.peel.x) + 200)
        // On the row, distance and x move one for one; a stop at 500 is 144 pt past the curve.
        #expect(abs(path.distance(toX: 500) - path.distance(toX: 356) - 144) < 1e-9)
        let stop = path.point(atDistance: path.distance(toX: 500))
        #expect(abs(stop.x - 500) < 1e-9 && stop.y == 200)
        // Halfway along the cubic is its centre of symmetry, halfway up.
        let middle = path.point(atDistance: Double(path.peel.x - path.start.x) + curve / 2)
        #expect(abs(middle.y - 300) < 0.5)
        #expect(abs(middle.x - (Double(path.peel.x) + 356) / 2) < 0.5)
    }

    @Test func theDistanceAlongThePathOnlyEverClimbs() {
        let path = StationLines.LanePath(stationX: 34, exitY: 420, y: 110, curveEnd: 300, laneEnd: 900)
        let ys = stride(from: 0.0, through: 1, by: 0.02).map { path.point(at: $0) }
        #expect(zip(ys, ys.dropFirst()).allSatisfy { $0.x <= $1.x && $0.y >= $1.y })
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

/// The dates the station tomorrow seam was asked from.
private actor AskedDates {
    private(set) var dates: [Date] = []
    func add(_ date: Date) { dates.append(date) }
}
