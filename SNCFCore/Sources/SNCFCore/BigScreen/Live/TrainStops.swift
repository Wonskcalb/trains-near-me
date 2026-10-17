import Foundation

/// Live `TrainStopsProviding`: `SNCFClient.trip(vehicleJourneyID:)` for the full stopping pattern the
/// inspector and the Lanes popover draw, cached by vehicle-journey id for the session like `ViaCache`:
/// ↑↓ back over a row, ⌘R or reopening a popover would otherwise ask SNCF for the same run again. The
/// stops are timetable facts (the delays live on the board), so a cached run never goes stale.
public struct LiveTrainStops: TrainStopsProviding {
    public typealias Fetch = @Sendable (String) async throws(TrainServiceError) -> [TripStop]

    private let fetch: Fetch
    private let cache = StopsCache()

    public init(fetch: @escaping Fetch) { self.fetch = fetch }

    /// The token is read per request so one typed after launch is used at once.
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared) {
        let fetch: Fetch = { id in try await SNCFClient(token: token(), session: session).trip(vehicleJourneyID: id) }
        self.init(fetch: fetch)
    }

    public func stops(forVehicleJourneyID id: String) async throws(TrainServiceError) -> [TripStop] {
        let fetch = self.fetch
        return try await cache.stops(id) { () async throws(TrainServiceError) in try await fetch(id) }.get()
    }
}

/// The in-flight lookup per vehicle journey, so two views asking for one train at once share a request.
/// A failure is dropped once it lands, so the next ask tries again instead of keeping the error.
actor StopsCache {
    private var tasks: [String: Task<Result<[TripStop], TrainServiceError>, Never>] = [:]

    func stops(_ id: String,
               compute: @escaping @Sendable () async throws(TrainServiceError) -> [TripStop]) async -> Result<[TripStop], TrainServiceError> {
        let task = tasks[id] ?? Task {
            do throws(TrainServiceError) { return .success(try await compute()) } catch { return .failure(error) }
        }
        tasks[id] = task
        let result = await task.value
        if case .failure = result { tasks[id] = nil }
        return result
    }
}
