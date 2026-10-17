import Foundation

// The Phase-0 fake: every provider answered from the big-screen mockups, verbatim. One fixed world —
// Thursday 15 October 2026, 17:40 Europe/Paris, the Grenoble ↔ Voiron journey (reverses at 13:00) —
// drives Main, Lanes, Wall, Duo, DuoWidget and MenuBar. Numbers, times, via-lists, the 17655 stopping
// pattern, the round trip and the leave-by are lifted straight from Design/BigScreen/*.dc.html, so
// previews, the screenshot build and the tests all show exactly what was designed, with no network.

/// The canned data behind `BigScreenData.fake`, exposed so tests can assert against the same anchor.
public enum BigScreenFixtures {
    public static let calendar = SNCFTime.calendar

    /// Thu 15 Oct 2026, 17:40 — "now" in every mockup.
    public static func at(_ hour: Int, _ minute: Int, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    public static let now = at(17, 40)

    // MARK: Stations

    public static let grenoble = Station(id: "stop_area:SNCF:87747006", name: "Grenoble", latitude: 45.191463, longitude: 5.714466)
    public static let voiron = Station(id: "stop_area:SNCF:87747337", name: "Voiron", latitude: 45.364105, longitude: 5.590006)
    public static let lyon = Station(id: "stop_area:SNCF:87723197", name: "Lyon Part-Dieu", latitude: 45.760460, longitude: 4.859496)
    public static let chambery = Station(id: "stop_area:SNCF:87741086", name: "Chambéry", latitude: 45.571156, longitude: 5.920660)
    public static let valence = Station(id: "stop_area:SNCF:87747279", name: "Valence Ville", latitude: 44.926650, longitude: 4.893466)

    /// What the fake "Go to station" search can find: the journey stations plus a few on the same lines.
    public static let searchableStations = [
        grenoble, voiron, lyon, chambery, valence,
        Station(id: "stop_area:SNCF:87686006", name: "Paris Gare de Lyon", latitude: 48.844922, longitude: 2.373462),
        Station(id: "stop_area:SNCF:87747402", name: "Moirans", latitude: 45.325010, longitude: 5.567470),
        Station(id: "stop_area:SNCF:87747469", name: "Saint-Égrève–St-Robert", latitude: 45.233140, longitude: 5.680580),
    ]

    // MARK: Train builders

    private static func journeyTrain(_ h: Int, _ m: Int, arr: (Int, Int), number: String,
                                     delay: Int? = 0, cancelled: Bool = false, mode: String = "TER") -> TrainDeparture {
        TrainDeparture(scheduledDeparture: at(h, m), scheduledArrival: at(arr.0, arr.1), mode: mode,
                       delayMinutes: delay, isCancelled: cancelled, trainNumber: number,
                       vehicleJourneyID: "vehicle_journey:fake:\(number)")
    }

    private static func stationTrain(_ h: Int, _ m: Int, to direction: String, number: String, vj: String,
                                     delay: Int? = 0, cancelled: Bool = false, mode: String = "TER") -> TrainDeparture {
        TrainDeparture(scheduledDeparture: at(h, m), scheduledArrival: nil, direction: direction, mode: mode,
                       delayMinutes: delay, isCancelled: cancelled, trainNumber: number, vehicleJourneyID: vj)
    }

    // MARK: Journey boards (Main centre board, Lanes, sidebars)

    /// Grenoble → Voiron, the primary journey. The anchor board: 17655 +12, 17657 cancelled, 17661 +24.
    /// Shared by Main, MenuBar and the extra-tall widget.
    public static let grenobleVoironTrains = [
        journeyTrain(17, 42, arr: (18, 7), number: "17653"),
        journeyTrain(18, 12, arr: (18, 36), number: "17655", delay: 12),
        journeyTrain(18, 42, arr: (19, 8), number: "17657", cancelled: true),
        journeyTrain(19, 12, arr: (19, 37), number: "17659"),
        journeyTrain(19, 42, arr: (20, 7), number: "17661", delay: 24),
        journeyTrain(20, 42, arr: (21, 7), number: "17663"),
    ]

    /// Grenoble → Lyon Part-Dieu, 1 h 17 each, one +15 (Lanes lane 2).
    public static let grenobleLyonTrains = [
        journeyTrain(17, 47, arr: (19, 4), number: "17614"),
        journeyTrain(18, 47, arr: (20, 4), number: "17616", delay: 15),
        journeyTrain(19, 47, arr: (21, 4), number: "17618"),
        journeyTrain(20, 47, arr: (22, 4), number: "17620"),
    ]

    /// Voiron → Valence Ville, 1 h 10 each (Lanes lane 4, "FOLLOWS YOU").
    public static let voironValenceTrains = [
        journeyTrain(18, 16, arr: (19, 26), number: "17851"),
        journeyTrain(19, 16, arr: (20, 26), number: "17855"),
        journeyTrain(20, 16, arr: (21, 26), number: "17859"),
    ]

    public static let journeyBoards: [JourneyBoard] = [
        JourneyBoard(journey: JourneyConfiguration(stationA: grenoble, stationB: voiron, direction: .automatic),
                     leg: Leg(from: grenoble, to: voiron),
                     state: BoardState.from(grenobleVoironTrains, now: now, calendar: calendar), fetchedAt: now),
        JourneyBoard(journey: JourneyConfiguration(stationA: grenoble, stationB: lyon, direction: .forward),
                     leg: Leg(from: grenoble, to: lyon),
                     state: BoardState.from(grenobleLyonTrains, now: now, calendar: calendar), fetchedAt: now),
        JourneyBoard(journey: JourneyConfiguration(stationA: grenoble, stationB: chambery, direction: .forward),
                     leg: Leg(from: grenoble, to: chambery), state: .noService, fetchedAt: now),
        JourneyBoard(journey: JourneyConfiguration(stationA: voiron, stationB: valence, nearestStationAsDeparture: true),
                     leg: Leg(from: voiron, to: valence),
                     state: BoardState.from(voironValenceTrains, now: now, calendar: calendar), fetchedAt: now),
    ]

    // MARK: Late evening (the end-of-service split)

    /// 22:30 the same Thursday: Grenoble → Voiron has its last train (22:42) to go, Lyon and Valence are
    /// over for the night, Chambéry is still dead. Every board carries the next morning, as the live
    /// provider fills it once tonight is nearly done.
    public static let lateNow = at(22, 30)

    private static func morning(_ times: [(Int, Int)], minutes: Int, from number: Int, delayed: [Int: Int] = [:]) -> [TrainDeparture] {
        times.enumerated().map { index, time in
            let departure = at(time.0, time.1, day: 16)
            return TrainDeparture(scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(TimeInterval(minutes * 60)),
                                  mode: "TER", delayMinutes: delayed[index] ?? 0, isCancelled: false,
                                  trainNumber: String(number + 2 * index), vehicleJourneyID: "vehicle_journey:fake:\(number + 2 * index)")
        }
    }

    /// The first trains of Fri 16 Oct, one per lane; Grenoble → Voiron opens at 05:42 like the summary says.
    public static let grenobleVoironTomorrow = morning([(5, 42), (6, 12), (6, 42), (7, 12), (7, 42), (8, 12)], minutes: 25, from: 17601)
    public static let grenobleLyonTomorrow = morning([(6, 17), (6, 47), (7, 47)], minutes: 77, from: 17602, delayed: [1: 15])
    public static let grenobleChamberyTomorrow = morning([(6, 5), (7, 5)], minutes: 45, from: 17701)
    public static let voironValenceTomorrow = morning([(6, 16), (7, 16)], minutes: 70, from: 17801)

    /// Grenoble → Voiron's last train tonight, the "LAST 22:42" of the service-day summary.
    public static let grenobleVoironLast = journeyTrain(22, 42, arr: (23, 7), number: "17669")

    public static let lateJourneyBoards: [JourneyBoard] = [
        JourneyBoard(journey: journeyBoards[0].journey, leg: journeyBoards[0].leg,
                     state: BoardState.from([grenobleVoironLast], now: lateNow, calendar: calendar),
                     fetchedAt: lateNow, tomorrow: grenobleVoironTomorrow),
        JourneyBoard(journey: journeyBoards[1].journey, leg: journeyBoards[1].leg,
                     state: BoardState.from(grenobleLyonTomorrow, now: lateNow, calendar: calendar),
                     fetchedAt: lateNow, tomorrow: grenobleLyonTomorrow),
        JourneyBoard(journey: journeyBoards[2].journey, leg: journeyBoards[2].leg, state: .noService,
                     fetchedAt: lateNow, tomorrow: grenobleChamberyTomorrow),
        JourneyBoard(journey: journeyBoards[3].journey, leg: journeyBoards[3].leg,
                     state: BoardState.from(voironValenceTomorrow, now: lateNow, calendar: calendar),
                     fetchedAt: lateNow, tomorrow: voironValenceTomorrow),
    ]

    // MARK: Station board (Wall — pinned station Voiron) and its via lists

    public static let voironStationTrains = [
        stationTrain(17, 46, to: "Grenoble", number: "17652", vj: "vehicle_journey:fake:17652"),
        stationTrain(17, 58, to: "Lyon Part-Dieu", number: "17614", vj: "vehicle_journey:fake:17614v"),
        stationTrain(18, 16, to: "Grenoble", number: "17654", vj: "vehicle_journey:fake:17654", delay: 12),
        stationTrain(18, 16, to: "Valence Ville", number: "17851", vj: "vehicle_journey:fake:17851"),
        stationTrain(18, 46, to: "Grenoble", number: "17656", vj: "vehicle_journey:fake:17656", cancelled: true),
        stationTrain(18, 58, to: "Lyon Part-Dieu", number: "17618", vj: "vehicle_journey:fake:17618v", delay: 24),
        stationTrain(19, 16, to: "Grenoble", number: "17658", vj: "vehicle_journey:fake:17658"),
        stationTrain(19, 21, to: "Paris Gare de Lyon", number: "6926", vj: "vehicle_journey:fake:6926", mode: "TGV"),
        stationTrain(19, 46, to: "Grenoble", number: "17660", vj: "vehicle_journey:fake:17660"),
    ]

    public static let voironBoard = BoardState.from(voironStationTrains, now: now, calendar: calendar)

    /// Voiron at 22:30 (`lateNow`), as the live station board answers once tonight is nearly done: two
    /// trains to go, then the first of Fri 16 Oct on the same four lines, with a +12 and a cancellation.
    private static func lateStationTrain(_ h: Int, _ m: Int, day: Int = 15, to terminus: Station, number: String,
                                         delay: Int = 0, cancelled: Bool = false) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: at(h, m, day: day), direction: terminus.name, mode: "TER", delayMinutes: delay,
                       isCancelled: cancelled, trainNumber: number, vehicleJourneyID: "vehicle_journey:fake:\(number)",
                       terminus: terminus)
    }

    public static let voironLateTrains = [
        lateStationTrain(22, 46, to: grenoble, number: "17669"),
        lateStationTrain(23, 21, to: lyon, number: "17630"),
    ]

    /// Up the Lyon line with it, so the late river splits the way the 17:40 one does.
    private static let standre = Station(id: "stop_area:SNCF:87747345", name: "St-André-le-Gaz", latitude: 45.545100, longitude: 5.528600)

    public static let voironStationTomorrow = [
        lateStationTrain(5, 16, day: 16, to: grenoble, number: "17601"),
        lateStationTrain(5, 46, day: 16, to: lyon, number: "17602"),
        lateStationTrain(5, 52, day: 16, to: valence, number: "17801"),
        lateStationTrain(6, 16, day: 16, to: grenoble, number: "17603"),
        lateStationTrain(6, 21, day: 16, to: lyon, number: "17604", delay: 12),
        lateStationTrain(6, 31, day: 16, to: standre, number: "17701"),
        lateStationTrain(6, 46, day: 16, to: grenoble, number: "17605"),
        lateStationTrain(6, 52, day: 16, to: valence, number: "17803", cancelled: true),
        lateStationTrain(7, 16, day: 16, to: grenoble, number: "17607"),
        lateStationTrain(7, 21, day: 16, to: lyon, number: "17606"),
        lateStationTrain(7, 31, day: 16, to: standre, number: "17703"),
    ]

    public static let viaByVehicle: [String: [String]] = [
        "vehicle_journey:fake:17652": ["Moirans", "Saint-Égrève–St-Robert"],
        "vehicle_journey:fake:17614v": ["Rives", "La Tour-du-Pin", "Bourgoin-Jallieu"],
        "vehicle_journey:fake:17654": ["Moirans"],
        "vehicle_journey:fake:17851": ["Moirans", "Saint-Marcellin", "Romans-Bourg-de-Péage"],
        "vehicle_journey:fake:17656": ["Moirans", "Saint-Égrève–St-Robert"],
        "vehicle_journey:fake:17618v": ["Rives", "Bourgoin-Jallieu"],
        "vehicle_journey:fake:17658": ["Moirans", "Saint-Égrève–St-Robert"],
        "vehicle_journey:fake:6926": [],
        "vehicle_journey:fake:17660": ["Moirans"],
    ]

    // MARK: Stopping pattern (Main inspector — 17655, base-schedule times)

    /// The run of 17655, Grenoble → Lyon Part-Dieu, as `trip()` returns it: base-schedule "HH:MM". The
    /// inspector draws the +12 amendment on top; the stored times stay the timetable's own.
    public static let stops17655 = [
        TripStop(name: "Grenoble", time: "18:12", isSkipped: false),
        TripStop(name: "Saint-Égrève–St-Robert", time: "18:19", isSkipped: false),
        TripStop(name: "Moirans", time: "18:28", isSkipped: false),
        TripStop(name: "Voiron", time: "18:36", isSkipped: false),
        TripStop(name: "Rives", time: "18:42", isSkipped: false),
        TripStop(name: "La Tour-du-Pin", time: "19:02", isSkipped: false),
        TripStop(name: "Bourgoin-Jallieu", time: "19:13", isSkipped: false),
        TripStop(name: "Lyon Part-Dieu", time: "19:41", isSkipped: false),
    ]

    public static let stopsByVehicle: [String: [TripStop]] = ["vehicle_journey:fake:17655": stops17655]

    // MARK: Service day (Lanes minimap + station-hall footer, for Grenoble → Voiron)

    /// Trains per hour from 03:00, read off the Lanes minimap bars (0/1/2/3). Sums to 32.
    public static let trainsPerHour = [0, 0, 1, 2, 3, 3, 2, 1, 1, 2, 2, 1, 1, 2, 3, 3, 2, 1, 1, 1, 0, 0, 0, 0]

    public static let serviceDaySummary = ServiceDaySummary(
        lastTonight: at(22, 42), firstTomorrow: at(5, 42, day: 16), trainsPerHour: trainsPerHour)

    // MARK: Round trip (Duo): outbound Voiron → Grenoble, way back Grenoble → Voiron

    public static let roundTripOutbound = [
        journeyTrain(17, 46, arr: (18, 11), number: "17652"),
        journeyTrain(18, 16, arr: (18, 41), number: "17654", delay: 12),
        journeyTrain(18, 46, arr: (19, 11), number: "17656", cancelled: true),
        journeyTrain(19, 16, arr: (19, 41), number: "17658"),
        journeyTrain(19, 46, arr: (20, 11), number: "17660"),
    ]

    /// The Duo mockup's way back, which the planner tags: one too early, the first that fits, two later,
    /// and the last train of the day (the board runs to the 03:00 close).
    public static let roundTripReturns = [
        TrainDeparture(scheduledDeparture: at(20, 6), scheduledArrival: at(20, 31), mode: "TER",
                       delayMinutes: 0, isCancelled: false, trainNumber: nil, vehicleJourneyID: nil),
        journeyTrain(20, 42, arr: (21, 7), number: "17663"),
        journeyTrain(21, 12, arr: (21, 37), number: "17665"),
        journeyTrain(21, 42, arr: (22, 7), number: "17667"),
        journeyTrain(22, 42, arr: (23, 7), number: "17669"),
    ]

    public static let roundTripPlan = RoundTripPlanner.plan(
        outbound: Leg(from: voiron, to: grenoble), outboundOptions: roundTripOutbound,
        returnOptions: roundTripReturns, pick: nil, stay: 150 * 60, at: now,
        returnsCoverServiceDay: true, calendar: calendar)

    public static func isGrenobleVoiron(_ leg: Leg) -> Bool {
        let ids = Set([leg.from.id, leg.to.id])
        return ids == Set([grenoble.id, voiron.id])
    }
}

// MARK: - Fake conformances

struct FakeJourneyBoards: JourneyBoardsProviding {
    let all: [JourneyBoard]
    func boards(at now: Date) async -> [JourneyBoard] { all }
    /// The saved board for that leg when the mockup has one, otherwise an empty unsaved board.
    func board(for leg: Leg, at now: Date) async -> JourneyBoard {
        all.first { $0.leg.from.id == leg.from.id && $0.leg.to.id == leg.to.id }
            ?? JourneyBoard(journey: JourneyConfiguration(stationA: leg.from, stationB: leg.to), leg: leg, state: .noTrains, fetchedAt: now)
    }
    /// The late-evening fixture's mornings, the only ones the mockup draws.
    func morning(for leg: Leg, at now: Date) async -> [TrainDeparture] {
        BigScreenFixtures.lateJourneyBoards.first { $0.leg.from.id == leg.from.id && $0.leg.to.id == leg.to.id }?.tomorrow ?? []
    }
}

/// One canned board (the pinned station); the `station` argument is ignored, there is only one in the fake.
struct FakeStationBoard: StationBoardProviding {
    let state: BoardState
    var tomorrow: [TrainDeparture] = []
    let viaByVehicle: [String: [String]]
    func board(for station: Station, at now: Date) async -> BoardState { state }
    func serviceDayBoard(for station: Station, at now: Date) async -> StationDayBoard { StationDayBoard(state: state, tomorrow: tomorrow) }
    func via(forVehicleJourneyID id: String) async -> [String] { viaByVehicle[id] ?? [] }
}

struct FakeTrainStops: TrainStopsProviding {
    let stopsByVehicle: [String: [TripStop]]
    func stops(forVehicleJourneyID id: String) async throws(TrainServiceError) -> [TripStop] {
        stopsByVehicle[id] ?? []
    }
}

struct FakeServiceDay: ServiceDayProviding {
    let main: ServiceDaySummary
    func summary(for leg: Leg, at now: Date) async -> ServiceDaySummary? {
        BigScreenFixtures.isGrenobleVoiron(leg) ? main : nil
    }
}

/// The one Duo scenario, re-planned for the pick and the stay asked, as the live plan is.
struct FakeRoundTrip: RoundTripPlanning {
    let plan: RoundTripPlan
    func roundTrip(outbound: Leg, pick: TrainIdentity?, stay minimumStay: TimeInterval, at now: Date) async -> RoundTripPlan {
        plan.replanned(pick: pick, stay: minimumStay, at: now)
    }
}

/// An actor so the pinned station survives across calls, like the real App-Group-backed setting will.
actor FakeLeaveBy: LeaveByProviding {
    private var pinned: Station?

    init(pinned: Station?) {
        self.pinned = pinned
    }

    func pinnedStation() -> Station? { pinned }
    func pin(_ station: Station?) { pinned = station }
    /// The mockup's "6 min walk to the platform".
    func walkMinutes(to station: Station) -> Int { 6 }
}

/// Watch state is per-instance and in-memory; the real one writes through the App Group and schedules a
/// local notification.
actor FakeTrainWatching: TrainWatching {
    private var set: Set<TrainIdentity> = []
    func isWatched(_ identity: TrainIdentity) -> Bool { set.contains(identity) }
    func watch(_ identity: TrainIdentity) { set.insert(identity) }
    func watch(_ train: TrainDeparture, to leg: Leg?) {
        if let identity = TrainIdentity(train) { set.insert(identity) }
    }
    func unwatch(_ identity: TrainIdentity) { set.remove(identity) }
    func watched() -> Set<TrainIdentity> { set }
}

/// A handful of stations, so the "Go to station" field and the journey editor have something to find
/// offline. Matched the way Navitia matches enough to feel the same: case and accents ignored.
struct FakeStationSearch: StationSearching {
    let stations: [Station]
    let near: NearbyStation

    func search(_ query: String) async throws(TrainServiceError) -> [Station] {
        Self.filter(stations, query)
    }

    func nearest() async throws(TrainServiceError) -> NearbyStation { near }

    static func filter(_ stations: [Station], _ query: String) -> [Station] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }
        return stations.filter { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

struct FakeETA: ETAComposing {
    func shareText(for train: TrainDeparture, leg: Leg) -> String {
        var line = ""
        if let mode = train.mode { line += mode + " " }
        if let number = train.trainNumber { line += number + " · " }
        line += "\(leg.from.name) → \(leg.to.name)"
        var lines = [line]
        if train.isCancelled {
            lines.append("Cancelled")
        } else {
            var leaves = "Leaves \(Self.time.string(from: train.expectedDeparture))"
            if let delay = train.delayMinutes, delay > 0 {
                leaves += " (was \(Self.time.string(from: train.scheduledDeparture)), +\(delay) min)"
            }
            lines.append(leaves)
            if let arrival = train.expectedArrival {
                lines.append("Arrives \(Self.time.string(from: arrival))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let time = SNCFTime.hhmmFormatter
}

extension BigScreenData {
    /// The fake at 22:30 (`BigScreenFixtures.lateNow`): every journey board past or near its end of
    /// service and carrying tomorrow's first trains, and Voiron's station board the same. The other
    /// providers are the 17:40 ones.
    public static let fakeLateEvening: BigScreenData = makeFake(late: true)

    static func makeFake(late: Bool = false) -> BigScreenData {
        BigScreenData(
            journeyBoards: FakeJourneyBoards(all: late ? BigScreenFixtures.lateJourneyBoards : BigScreenFixtures.journeyBoards),
            stationBoard: late
                ? FakeStationBoard(state: BoardState.from(BigScreenFixtures.voironLateTrains, now: BigScreenFixtures.lateNow,
                                                          calendar: BigScreenFixtures.calendar),
                                   tomorrow: BigScreenFixtures.voironStationTomorrow, viaByVehicle: [:])
                : FakeStationBoard(state: BigScreenFixtures.voironBoard, viaByVehicle: BigScreenFixtures.viaByVehicle),
            trainStops: FakeTrainStops(stopsByVehicle: BigScreenFixtures.stopsByVehicle),
            serviceDay: FakeServiceDay(main: BigScreenFixtures.serviceDaySummary),
            roundTrip: FakeRoundTrip(plan: BigScreenFixtures.roundTripPlan),
            leaveBy: FakeLeaveBy(pinned: BigScreenFixtures.voiron),
            watching: FakeTrainWatching(),
            eta: FakeETA(),
            stationSearch: FakeStationSearch(stations: BigScreenFixtures.searchableStations,
                                             near: NearbyStation(station: BigScreenFixtures.voiron, distance: 850)))
    }
}
