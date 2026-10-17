import Foundation

/// Live `StationBoardProviding`: one station's board from the departures endpoint, plus the short
/// "via …" line for a row. The via list costs a `trip()` request, so it is fetched only when a row asks
/// and cached by vehicle-journey id for the session — a view cache, not persisted.
public struct LiveStationBoard: StationBoardProviding {
    public typealias BoardFetch = @Sendable (Station, Date) async throws(TrainServiceError) -> [TrainDeparture]
    public typealias TripFetch = @Sendable (String) async throws(TrainServiceError) -> [TripStop]
    /// Handed every raw board before it collapses into a `BoardState`: production re-checks watched trains.
    public typealias Observe = @Sendable ([TrainDeparture]) async -> Void

    private let fetchBoard: BoardFetch
    private let fetchWindow: BoardFetch
    /// The first trains from the next 03:00, asked only when tonight is nearly done.
    private let fetchTomorrow: BoardFetch
    private let fetchTrip: TripFetch
    private let observe: Observe
    private let calendar: Calendar
    /// The Wall and the board rows only show a couple of intermediate stops, so the via line is capped.
    private let maxVia: Int
    private let cache = ViaCache()

    /// `window` answers `serviceDayBoard` and `tomorrow` its late morning; nil reuses `board`, which is
    /// all a test seam needs.
    public init(calendar: Calendar = SNCFTime.calendar, maxVia: Int = 3, observe: @escaping Observe = { _ in },
                board: @escaping BoardFetch, window: BoardFetch? = nil, tomorrow: BoardFetch? = nil,
                trip: @escaping TripFetch) {
        self.calendar = calendar
        self.maxVia = max(0, maxVia)
        self.observe = observe
        self.fetchBoard = board
        self.fetchWindow = window ?? board
        self.fetchTomorrow = tomorrow ?? board
        self.fetchTrip = trip
    }

    /// Production wiring: the station board and, on demand, each row's stopping pattern. The token is read
    /// per request so one typed after launch is used at once.
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared,
                calendar: Calendar = SNCFTime.calendar, maxVia: Int = 3) {
        let board: BoardFetch = { station, now in
            try await SNCFClient(token: token(), session: session).departures(from: station, at: now)
        }
        let window: BoardFetch = { station, now in
            try await SNCFClient(token: token(), session: session)
                .departures(from: station, at: now, within: BoardState.restOfServiceDay(after: now, atLeast: 2 * 3600, calendar: calendar))
        }
        // A count, not a window: only the morning's first trains are drawn after the break.
        let tomorrow: BoardFetch = { station, opens in
            try await SNCFClient(token: token(), session: session).departures(from: station, at: opens, count: Self.tomorrowCount)
        }
        let trip: TripFetch = { id in
            try await SNCFClient(token: token(), session: session).trip(vehicleJourneyID: id)
        }
        self.init(calendar: calendar, maxVia: maxVia,
                  observe: { await TrainWatcher.shared.reevaluate(against: $0) },
                  board: board, window: window, tomorrow: tomorrow, trip: trip)
    }

    /// How many of tomorrow's first trains a late board carries: a station sends every terminus at once,
    /// so it takes a few times a journey's six to cover the morning's first two hours.
    static let tomorrowCount = 30

    public func board(for station: Station, at now: Date) async -> BoardState {
        do {
            let trains = try await fetchBoard(station, now)
            await observe(trains)
            return BoardState.from(trains, now: now, calendar: calendar)
        } catch {
            return .unavailable(error)
        }
    }

    /// Late in the evening a second, count-based request from the next 03:00 brings the morning, as the
    /// journey boards do: it is paid only when tonight is nearly done. After the last train the window to
    /// 03:00 is empty and that same morning names the first train, so the night never costs a third.
    public func serviceDayBoard(for station: Station, at now: Date) async -> StationDayBoard {
        var state: BoardState
        do {
            let trains = try await fetchWindow(station, now)
            await observe(trains)
            state = BoardState.from(trains, now: now, calendar: calendar)
        } catch {
            return StationDayBoard(state: .unavailable(error))
        }
        guard state.tonightIsNearlyDone(at: now) else { return StationDayBoard(state: state) }
        // A failure here only loses the morning; tonight's board stands.
        let opens = BoardState.nextServiceDayStart(after: now, calendar: calendar)
        let day = BoardState.serviceDay(of: opens, calendar: calendar)
        let morning = ((try? await fetchTomorrow(station, opens)) ?? [])
            .filter { BoardState.serviceDay(of: $0.scheduledDeparture, calendar: calendar) == day }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        if state == .noTrains, let first = morning.first(where: { !$0.isCancelled }) {
            state = .endOfService(firstTrain: first.scheduledDeparture)
        }
        return StationDayBoard(state: state, tomorrow: morning)
    }

    public func via(forVehicleJourneyID id: String) async -> [String] {
        let fetchTrip = self.fetchTrip
        let maxVia = self.maxVia
        return await cache.via(id) {
            guard let stops = try? await fetchTrip(id) else { return nil }
            return Self.via(from: stops, max: maxVia)
        }
    }

    /// The intermediate stops of a run, as a short "via" list: everything it calls at between origin and
    /// terminus, dropping the stops it only passes, capped so the line stays one row.
    static func via(from stops: [TripStop], max: Int) -> [String] {
        guard stops.count > 2 else { return [] }
        return Array(stops.dropFirst().dropLast().filter { !$0.isSkipped }.map(\.name).prefix(max))
    }
}

/// Per-session cache of via lists keyed by vehicle-journey id. It holds the in-flight task, not just the
/// finished list, so two rows asking for the same train at once still cost a single `trip()` request. A
/// failed lookup (nil) is dropped once it lands, so a row that hit a network blip asks again next time
/// instead of reading "direct" for the rest of the session.
actor ViaCache {
    private var tasks: [String: Task<[String]?, Never>] = [:]

    func via(_ id: String, compute: @escaping @Sendable () async -> [String]?) async -> [String] {
        let task = tasks[id] ?? Task { await compute() }
        tasks[id] = task
        guard let via = await task.value else {
            tasks[id] = nil
            return []
        }
        return via
    }
}
