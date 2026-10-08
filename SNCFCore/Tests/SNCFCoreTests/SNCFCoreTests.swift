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
        #expect(train.duration == 25 * 60)
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

    @Test func stationSearchKeepsStopAreasOnly() throws {
        #expect(try NavitiaParser.stations(from: fixture("places")) == [grenoble])
    }

    /// Regression: station search used to surface "SNCFCore.TrainServiceError error 0".
    @Test func errorsAreReadable() {
        #expect(TrainServiceError.missingToken.localizedDescription == "Add your SNCF API token in the Trains near me app.")
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
    @Test func entriesDropDepartedTrainsAndEndStale() throws {
        let trains = try NavitiaParser.departures(from: fixture("journeys_mixed"), origin: grenoble, destination: voiron)
        let dates = RefreshPlanner.entryDates(fetchedAt: at(17, 40), departures: trains)
        #expect(dates.first == at(17, 40))
        #expect(dates.contains(at(17, 43)))
        #expect(dates.last == at(18, 10))
        #expect(RefreshPlanner.isStale(fetchedAt: at(17, 40), at: at(18, 10)))
    }
}
