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
    private let fetchTrip: TripFetch
    private let observe: Observe
    private let calendar: Calendar
    /// The Wall and the board rows only show a couple of intermediate stops, so the via line is capped.
    private let maxVia: Int
    private let cache = ViaCache()

    /// `window` answers `serviceDayBoard`; nil reuses `board`, which is all a test seam needs.
    public init(calendar: Calendar = SNCFTime.calendar, maxVia: Int = 3, observe: @escaping Observe = { _ in },
                board: @escaping BoardFetch, window: BoardFetch? = nil, trip: @escaping TripFetch) {
        self.calendar = calendar
        self.maxVia = max(0, maxVia)
        self.observe = observe
        self.fetchBoard = board
        self.fetchWindow = window ?? board
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
        let trip: TripFetch = { id in
            try await SNCFClient(token: token(), session: session).trip(vehicleJourneyID: id)
        }
        self.init(calendar: calendar, maxVia: maxVia,
                  observe: { await TrainWatcher.shared.reevaluate(against: $0) },
                  board: board, window: window, trip: trip)
    }

    public func board(for station: Station, at now: Date) async -> BoardState {
        do {
            let trains = try await fetchBoard(station, now)
            await observe(trains)
            return BoardState.from(trains, now: now, calendar: calendar)
        } catch {
            return .unavailable(error)
        }
    }

    /// After the last train the window to 03:00 is empty, and only the count-based board reaches into
    /// tomorrow for the first train the night treatment shows: that second request is paid at night only.
    public func serviceDayBoard(for station: Station, at now: Date) async -> BoardState {
        do {
            let trains = try await fetchWindow(station, now)
            if trains.isEmpty { return await board(for: station, at: now) }
            await observe(trains)
            return BoardState.from(trains, now: now, calendar: calendar)
        } catch {
            return .unavailable(error)
        }
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
