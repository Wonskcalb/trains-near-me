import CoreLocation
import Foundation

/// Live `StationSearching`: SNCF's `places` endpoint for the search (it already matches loosely —
/// accents, case, partial words), `places_nearby` around the device for NEAR ME. Both seams take the
/// token per request so one typed after launch is used at once.
public struct LiveStationSearch: StationSearching {
    private let token: @Sendable () -> String?
    private let session: URLSession
    private let location: @Sendable () async -> CLLocation?

    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared,
                location: @escaping @Sendable () async -> CLLocation? = { await LocationFix.shared.current() }) {
        self.token = token
        self.session = session
        self.location = location
    }

    public func search(_ query: String) async throws(TrainServiceError) -> [Station] {
        let query = query.trimmingCharacters(in: .whitespaces)
        // One letter matches half of France and still costs a request from the 5 000-a-day tier.
        guard query.count >= 2 else { return [] }
        return try await SNCFClient(token: token(), session: session).searchStations(query)
    }

    public func nearest() async throws(TrainServiceError) -> NearbyStation {
        guard let fix = await location() else { throw .noLocation }
        guard let station = try await SNCFClient(token: token(), session: session)
            .nearestStation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        else { throw .noStationNearby }
        let distance = fix.distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
        return NearbyStation(station: station, distance: distance)
    }
}
