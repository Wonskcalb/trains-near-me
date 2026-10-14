import CoreLocation
import Foundation
import Testing
@testable import SNCFCore

let grenoble = Station(id: "stop_area:SNCF:87747006", name: "Grenoble", latitude: 45.191463, longitude: 5.714466)
let voiron = Station(id: "stop_area:SNCF:87747337", name: "Voiron", latitude: 45.364105, longitude: 5.590006)

func at(_ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: hour, minute: minute))!
}

var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
}

@Suite struct Direction {
    func leg(_ mode: DirectionMode, at date: Date, switchMinute: Int = 13 * 60) -> Leg {
        let config = JourneyConfiguration(stationA: grenoble, stationB: voiron, direction: mode, switchMinute: switchMinute)
        return JourneySelector.leg(for: config, at: date, location: nil, calendar: paris)
    }

    @Test func fixedForward() { #expect(leg(.forward, at: at(18, 0)) == Leg(from: grenoble, to: voiron)) }
    @Test func fixedReverse() { #expect(leg(.reverse, at: at(8, 0)) == Leg(from: voiron, to: grenoble)) }
    @Test func automaticBeforeSwitch() { #expect(leg(.automatic, at: at(12, 59)).from == grenoble) }
    @Test func automaticAtAndAfterSwitch() {
        #expect(leg(.automatic, at: at(13, 0)).from == voiron)
        #expect(leg(.automatic, at: at(23, 59)).from == voiron)
    }
    @Test func customSwitchTime() {
        #expect(leg(.automatic, at: at(15, 29), switchMinute: 15 * 60 + 30).from == grenoble)
        #expect(leg(.automatic, at: at(15, 30), switchMinute: 15 * 60 + 30).from == voiron)
    }
}

@Suite struct Position {
    func leg(_ location: CLLocation?, direction: DirectionMode = .forward) -> Leg {
        let config = JourneyConfiguration(stationA: grenoble, stationB: voiron, direction: direction, nearestStationAsDeparture: true)
        return JourneySelector.leg(for: config, at: at(18, 0), location: location, calendar: paris)
    }

    @Test func nearerToA() { #expect(leg(CLLocation(latitude: 45.19, longitude: 5.72)) == Leg(from: grenoble, to: voiron)) }
    @Test func nearerToB() { #expect(leg(CLLocation(latitude: 45.36, longitude: 5.59)) == Leg(from: voiron, to: grenoble)) }
    @Test func tieGoesToA() {
        let same = Station(id: "x", name: "Twin", latitude: grenoble.latitude, longitude: grenoble.longitude)
        let config = JourneyConfiguration(stationA: grenoble, stationB: same, nearestStationAsDeparture: true)
        let leg = JourneySelector.leg(for: config, at: at(18, 0), location: CLLocation(latitude: 45, longitude: 5), calendar: paris)
        #expect(leg.from == grenoble)
    }
    @Test func noLocationFallsBackToDirection() { #expect(leg(nil, direction: .reverse).from == voiron) }

    /// Regression: configured Voiron → Grenoble with nearest-station on, user in Grenoble.
    @Test(arguments: [DirectionMode.forward, .reverse, .automatic])
    func locationOverridesConfiguredOrder(direction: DirectionMode) {
        let config = JourneyConfiguration(stationA: voiron, stationB: grenoble, direction: direction, nearestStationAsDeparture: true)
        let inGrenoble = CLLocation(latitude: 45.1885, longitude: 5.7245)
        for time in [at(8, 0), at(15, 9)] {
            #expect(JourneySelector.leg(for: config, at: time, location: inGrenoble, calendar: paris) == Leg(from: grenoble, to: voiron))
        }
    }
}

@Suite struct DelayMapping {
    @Test(arguments: [
        (0, DepartureStatus.onTime), (5, .onTime), (10, .onTime),
        (11, .delayed), (19, .delayed),
        (20, .severelyDelayed), (21, .severelyDelayed),
    ])
    func bands(delay: Int, expected: DepartureStatus) {
        #expect(DepartureStatus.from(delayMinutes: delay, cancelled: false) == expected)
    }

    @Test func cancellationWinsOverDelay() { #expect(DepartureStatus.from(delayMinutes: 30, cancelled: true) == .cancelled) }
    @Test func missingDelayIsUnknown() { #expect(DepartureStatus.from(delayMinutes: nil, cancelled: false) == .unknown) }
}

@Suite struct Parsing {
    func mixed() throws -> [TrainDeparture] {
        try NavitiaParser.departures(from: fixture("journeys_mixed"), origin: grenoble, destination: voiron)
    }

    @Test func onlyDirectTrainsServingTheJourney() throws {
        #expect(try mixed().map(\.trainNumber) == ["17601", "17603", "17605", "17607", "17609"])
    }

    @Test func onTime() throws {
        let train = try mixed()[0]
        #expect(train.scheduledDeparture == at(17, 42))
        #expect(train.duration == TimeInterval(25 * 60))
        #expect(train.delayMinutes == 0)
        #expect(train.status == .onTime)
    }

    @Test func delayed() throws {
        let train = try mixed()[1]
        #expect(train.delayMinutes == 12)
        #expect(train.status == .delayed)
        #expect(train.expectedDeparture == at(18, 24))
    }

    @Test func severelyDelayed() throws { #expect(try mixed()[2].delayMinutes == 23) }

    @Test func cancelled() throws { #expect(try mixed()[3].status == .cancelled) }

    @Test func missingRealtime() throws {
        let train = try mixed()[4]
        #expect(train.delayMinutes == nil)
        #expect(train.status == .unknown)
    }

    @Test func unavailableService() throws {
        let trains = try NavitiaParser.departures(from: fixture("journeys_all_cancelled"), origin: grenoble, destination: voiron)
        #expect(BoardState.from(trains, now: at(17, 40), calendar: paris) == .noService)
    }

    @Test func noSolutionMeansNoTrains() throws {
        let trains = try NavitiaParser.departures(from: fixture("no_solution"), origin: grenoble, destination: voiron)
        #expect(BoardState.from(trains, now: at(17, 40), calendar: paris) == .noTrains)
    }

    @Test func malformed() {
        #expect(throws: TrainServiceError.malformedResponse) {
            try NavitiaParser.departures(from: Data("{\"journeys\": 3}".utf8), origin: grenoble, destination: voiron)
        }
    }

    @Test func stationBoardListsEveryDirection() throws {
        let board = try NavitiaParser.stopDepartures(from: fixture("stop_departures"))
        #expect(board.map(\.direction) == ["Valence Ville (Valence)", "Lyon Part Dieu (Lyon)",
                                           "Chambéry - Challes-les-Eaux (Chambéry)", "Annecy (Annecy)"])
        #expect(board[0].scheduledDeparture == at(17, 42))
        #expect(board[0].duration == nil)
        #expect(board[0].status == .onTime)
        #expect(board[1].delayMinutes == 12)
        #expect(board[2].status == .cancelled)
        #expect(board[3].status == .unknown)
    }

    @Test func stationBoardCarriesTheVehicleJourneyID() throws {
        let board = try NavitiaParser.stopDepartures(from: fixture("stop_departures"))
        #expect(board[0].vehicleJourneyID == "vehicle_journey:SNCF:2026-10-15:96601:1187:Train")
        // Only the rows whose links carried one; the rest stay nil and are not tappable.
        #expect(board[1].vehicleJourneyID == nil)
    }

    @Test func tripStopsListEveryCallingPoint() throws {
        let stops = try NavitiaParser.tripStops(from: fixture("vehicle_journey"))
        #expect(stops.count == 10)
        #expect(stops.first?.name == "Grenoble")
        #expect(stops.first?.time == "05:12")
        #expect(stops.last?.name == "Genève Cornavin")
        #expect(stops.last?.time == "07:40")
        #expect(stops.allSatisfy { !$0.isSkipped })
    }

    /// SNCF names every TER after its region ("REGIONAURA"), so the brand alone is unreadable
    /// and the physical mode has to finish the job.
    @Test func serviceNamesAreReadable() throws {
        let board = try NavitiaParser.stopDepartures(from: fixture("stop_departures"))
        #expect(board.map(\.mode) == ["TER", "TGV", "TGV", "Car"])
        #expect(try mixed().allSatisfy { $0.mode == "TER" })
        #expect(NavitiaParser.mode(commercial: "OUIGO", physical: "Train grande vitesse") == "OUIGO")
        #expect(NavitiaParser.mode(commercial: "INTERCITES", physical: "TER / Intercités") == "Intercités")
        #expect(NavitiaParser.mode(commercial: nil, physical: nil) == nil)
    }

    @Test func nearbySearchKeepsStopAreasInDistanceOrder() throws {
        #expect(try NavitiaParser.nearbyStations(from: fixture("places_nearby")) == [grenoble, voiron])
    }

    @Test func stationSearchKeepsStopAreasOnly() throws {
        #expect(try NavitiaParser.stations(from: fixture("places")) == [grenoble])
    }

    /// Regression: station search used to surface "SNCFCore.TrainServiceError error 0".
    @Test func errorsAreReadable() {
        #expect(TrainServiceError.missingToken.localizedDescription == "Add your SNCF API token in the Trains near me app.")
    }

    /// A Lock Screen complication clips a full sentence, so every error has a terse form that fits.
    @Test func errorsHaveATerseFormForComplications() {
        for error in [TrainServiceError.missingToken, .unauthorized, .quotaExceeded, .offline,
                      .serverUnavailable, .malformedResponse, .noLocation, .noStationNearby] {
            #expect(error.terse.count <= 16)
        }
    }

    /// The refresh button redraws this while the new trains are fetched, so it has to survive
    /// the trip through the App Group.
    @Test func cachedBoardRoundTrip() throws {
        let board = CachedBoard(fetchedAt: at(17, 40), origin: grenoble, destination: nil, trains: [
            TrainDeparture(scheduledDeparture: at(17, 42), direction: "Valence Ville", delayMinutes: 12, isCancelled: false, trainNumber: "17601"),
        ])
        let restored = try JSONDecoder().decode(CachedBoard.self, from: JSONEncoder().encode(board))
        #expect(restored == board)
    }

    @Test func stationIdentifierRoundTrip() {
        #expect(Station(entityIdentifier: grenoble.entityIdentifier) == grenoble)
    }
}

@Suite struct ServiceDay {
    func train(_ date: Date, cancelled: Bool = false) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: date, scheduledArrival: date.addingTimeInterval(1500), delayMinutes: 0, isCancelled: cancelled, trainNumber: nil)
    }
    func tomorrow(_ hour: Int, _ minute: Int) -> Date { at(hour, minute).addingTimeInterval(86400) }

    @Test func tomorrowsTrainsAreNotListedToday() {
        let state = BoardState.from([train(at(22, 12)), train(tomorrow(5, 58))], now: at(21, 0), calendar: paris)
        #expect(state == .departures([train(at(22, 12))]))
    }

    @Test func endOfServiceGivesTheFirstRunningTrain() {
        let trains = [train(tomorrow(5, 28), cancelled: true), train(tomorrow(5, 58)), train(tomorrow(6, 28))]
        #expect(BoardState.from(trains, now: at(23, 30), calendar: paris) == .endOfService(firstTrain: tomorrow(5, 58)))
    }

    @Test func trainAfterMidnightStillBelongsToTonight() {
        let state = BoardState.from([train(tomorrow(0, 15)), train(tomorrow(5, 58))], now: at(23, 30), calendar: paris)
        #expect(state == .departures([train(tomorrow(0, 15))]))
    }

    @Test func rightAfterMidnightTheEveningServiceContinues() {
        let state = BoardState.from([train(tomorrow(0, 45)), train(tomorrow(5, 58))], now: tomorrow(0, 10), calendar: paris)
        #expect(state == .departures([train(tomorrow(0, 45))]))
    }

    @Test func remainingTrainsAllCancelledIsNoServiceNotEndOfService() {
        let trains = [train(at(22, 12), cancelled: true), train(at(22, 42), cancelled: true), train(tomorrow(5, 58))]
        #expect(BoardState.from(trains, now: at(21, 0), calendar: paris) == .noService)
    }
}

@Suite struct Refresh {
    func train(_ date: Date) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: date, scheduledArrival: date.addingTimeInterval(1500), delayMinutes: 0, isCancelled: false, trainNumber: nil)
    }

    func reload(_ state: BoardState, at date: Date = at(17, 40)) -> Date {
        RefreshPlanner.nextRefresh(fetchedAt: date, state: state)
    }

    @Test func reloadLandsJustBeforeTheNextTrain() {
        #expect(reload(.departures([train(at(18, 30))])) == at(18, 25))
    }

    @Test func aTrainEveryQuarterHourStillRespectsTheReloadBudget() {
        let trains = [at(17, 45), at(18, 0), at(18, 15), at(18, 30)].map(train)
        // Five minutes before the next train would be three reloads in the next half hour, which
        // empties the daily budget by mid-afternoon. The 20-minute floor wins instead.
        #expect(reload(.departures(trains)) == at(18, 0))
    }

    @Test func sparseTrainsNeverWaitMoreThanAnHour() {
        #expect(reload(.departures([train(at(22, 0))])) == at(18, 40))
    }

    @Test func theNightCostsOneReload() {
        let firstTrain = at(5, 58).addingTimeInterval(86400)
        #expect(reload(.endOfService(firstTrain: firstTrain), at: at(23, 40)) == firstTrain.addingTimeInterval(-5 * 60))
    }

    @Test func errorsAreRetriedSooner() {
        #expect(reload(.unavailable(.offline)) == at(17, 55))
    }

    @Test func entriesDropDepartedTrainsAndOutliveTheStaleMark() throws {
        let trains = try NavitiaParser.departures(from: fixture("journeys_mixed"), origin: grenoble, destination: voiron)
        let dates = RefreshPlanner.entryDates(fetchedAt: at(17, 40), departures: trains)
        #expect(dates.first == at(17, 40))
        // One entry a minute after each train leaves, and one at the 30-minute stale mark.
        #expect(dates.contains(at(17, 43)))
        #expect(dates.contains(at(18, 10)))
        // The last train is still listed long after the delays went stale.
        #expect(dates.last == trains.last?.expectedDeparture.addingTimeInterval(60))
        #expect(dates.last ?? .distantPast > at(18, 10))
        #expect(RefreshPlanner.isStale(fetchedAt: at(17, 40), at: at(18, 10)))
    }
}

/// The app's saved journeys travel to the widget as JSON in the App Group, so a journey has to
/// survive the round trip whole — a dropped switch time or direction would silently change the leg.
@Suite struct SavedJourneys {
    @Test func survivesTheRoundTrip() throws {
        let journey = JourneyConfiguration(stationA: grenoble, stationB: voiron, direction: .automatic,
                                           switchMinute: 17 * 60 + 45, nearestStationAsDeparture: true)
        let data = try JSONEncoder().encode([journey])
        #expect(try JSONDecoder().decode([JourneyConfiguration].self, from: data) == [journey])
    }
}

/// The large widget plots the next trains as dots along a track: the window runs from the first to the
/// hour after the last, and each time maps to a fraction across it. Hours fall where the labels go.
@Suite struct TimeTrack {
    @Test func windowRunsToTheHourAfterTheLastTrain() {
        let layout = TimeTrackLayout(times: [at(17, 42), at(18, 12), at(20, 42)], calendar: paris)
        #expect(layout.start == at(17, 42))
        #expect(layout.end == at(21, 0))               // 20:42 rounded up to the next whole hour
        #expect(layout.hours == [at(18, 0), at(19, 0), at(20, 0), at(21, 0)])
    }

    @Test func fractionIsLinearAndClamped() {
        let layout = TimeTrackLayout(times: [at(17, 42), at(20, 42)], calendar: paris)
        #expect(layout.fraction(of: at(17, 42)) == 0)
        #expect(layout.fraction(of: at(21, 0)) == 1)
        #expect(abs(layout.fraction(of: at(18, 0)) - 18.0 / 198.0) < 0.0001)   // 198 min window
        #expect(layout.fraction(of: at(17, 0)) == 0)   // before the start clamps to 0
        #expect(layout.fraction(of: at(22, 0)) == 1)   // after the end clamps to 1
    }

    @Test func aSingleTrainStillGivesAWindow() {
        let layout = TimeTrackLayout(times: [at(18, 20)], calendar: paris)
        #expect(layout.end > layout.start)
        #expect(layout.fraction(of: at(18, 20)) == 0)
    }
}
