import Foundation

/// Live `StationBoardProviding`: one station's board from the departures endpoint, plus the short
/// "via …" line for a row. The via list costs a `trip()` request, so it is fetched only when a row asks
/// and cached by vehicle-journey id for the session — a view cache, not persisted.
public struct LiveStationBoard: StationBoardProviding {
    public typealias BoardFetch = @Sendable (Station, Date) async throws(TrainServiceError) -> [TrainDeparture]
    public typealias TripFetch = @Sendable (String) async throws(TrainServiceError) -> [TripStop]

    private let fetchBoard: BoardFetch
    private let fetchTrip: TripFetch
    private let calendar: Calendar
    /// The Wall and the board rows only show a couple of intermediate stops, so the via line is capped.
    private let maxVia: Int
    private let cache = ViaCache()

    public init(calendar: Calendar = .current, maxVia: Int = 3, board: @escaping BoardFetch, trip: @escaping TripFetch) {
        self.calendar = calendar
        self.maxVia = max(0, maxVia)
        self.fetchBoard = board
        self.fetchTrip = trip
    }

    /// Production wiring: the station board and, on demand, each row's stopping pattern.
    public init(token: String? = SharedSettings.token, session: URLSession = .shared,
                calendar: Calendar = .current, maxVia: Int = 3) {
        let board: BoardFetch = { station, now in
            try await SNCFClient(token: token, session: session).departures(from: station, at: now)
        }
        let trip: TripFetch = { id in
            try await SNCFClient(token: token, session: session).trip(vehicleJourneyID: id)
        }
        self.init(calendar: calendar, maxVia: maxVia, board: board, trip: trip)
    }

    public func board(for station: Station, at now: Date) async -> BoardState {
        do { return BoardState.from(try await fetchBoard(station, now), now: now, calendar: calendar) }
        catch { return .unavailable(error) }
    }

    public func via(forVehicleJourneyID id: String) async -> [String] {
        let fetchTrip = self.fetchTrip
        let maxVia = self.maxVia
        return await cache.via(id) {
            let stops = (try? await fetchTrip(id)) ?? []
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
/// finished list, so two rows asking for the same train at once still cost a single `trip()` request.
actor ViaCache {
    private var tasks: [String: Task<[String], Never>] = [:]

    func via(_ id: String, compute: @escaping @Sendable () async -> [String]) async -> [String] {
        if let task = tasks[id] { return await task.value }
        let task = Task { await compute() }
        tasks[id] = task
        return await task.value
    }
}
