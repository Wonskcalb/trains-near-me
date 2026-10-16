import Foundation

/// Live `TrainStopsProviding`: a thin wrapper over `SNCFClient.trip(vehicleJourneyID:)` for the full
/// stopping pattern the inspector draws. The seam keeps that rendering testable from a fixture.
public struct LiveTrainStops: TrainStopsProviding {
    public typealias Fetch = @Sendable (String) async throws(TrainServiceError) -> [TripStop]

    private let fetch: Fetch

    public init(fetch: @escaping Fetch) { self.fetch = fetch }

    /// The token is read per request so one typed after launch is used at once.
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared) {
        let fetch: Fetch = { id in try await SNCFClient(token: token(), session: session).trip(vehicleJourneyID: id) }
        self.init(fetch: fetch)
    }

    public func stops(forVehicleJourneyID id: String) async throws(TrainServiceError) -> [TripStop] {
        try await fetch(id)
    }
}
