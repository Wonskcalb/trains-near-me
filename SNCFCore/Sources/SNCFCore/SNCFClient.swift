import Foundation

/// api.sncf.com (Navitia). Free tier: 5 000 requests/day, token sent as Basic-auth username.
public struct SNCFClient {
    /// Enough journeys for a whole evening: the timeline keeps listing them even when the system
    /// grants no reload, and a longer list costs the same single request.
    public static let departuresPerRequest = 12
    /// A busy station board burns through departures faster, so it asks for more.
    public static let boardDeparturesPerRequest = 20
    /// Radar mode: how far to look for a station around you.
    public static let searchRadiusKilometres = 20

    let token: String?
    let session: URLSession
    let baseURL = URL(string: "https://api.sncf.com/v1/coverage/sncf/")!

    public init(token: String?, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func departures(from: Station, to: Station, at date: Date) async throws(TrainServiceError) -> [TrainDeparture] {
        let data = try await get("journeys", [
            "from": from.id,
            "to": to.id,
            "datetime": NavitiaParser.dateFormatter.string(from: date),
            "datetime_represents": "departure",
            "data_freshness": "base_schedule",
            "max_nb_transfers": "0",
            "direct_path": "none",
            "min_nb_journeys": String(Self.departuresPerRequest),
        ])
        return try NavitiaParser.departures(from: data, origin: from, destination: to)
    }

    /// Radar mode: every train leaving one station, whatever its destination.
    public func departures(from station: Station, at date: Date) async throws(TrainServiceError) -> [TrainDeparture] {
        let data = try await get("stop_areas/\(station.id)/departures", [
            "from_datetime": NavitiaParser.dateFormatter.string(from: date),
            "data_freshness": "base_schedule",
            "count": String(Self.boardDeparturesPerRequest),
            "disable_geojson": "true",
        ])
        return try NavitiaParser.stopDepartures(from: data)
    }

    /// The station closest to a position. Coordinates are rounded to three decimals
    /// (~100 m) before they reach SNCF, which is plenty to pick the right station.
    public func nearestStation(latitude: Double, longitude: Double) async throws(TrainServiceError) -> Station? {
        let coord = "\(rounded(longitude));\(rounded(latitude))"
        let data = try await get("coord/\(coord)/places_nearby", [
            "type[]": "stop_area",
            "count": "5",
            "distance": String(Self.searchRadiusKilometres * 1000),
            "disable_geojson": "true",
        ])
        return try NavitiaParser.nearbyStations(from: data).first
    }

    private func rounded(_ degrees: Double) -> String {
        String(format: "%.3f", degrees)
    }

    public func searchStations(_ query: String) async throws(TrainServiceError) -> [Station] {
        let data = try await get("places", ["q": query, "type[]": "stop_area", "count": "10"])
        return try NavitiaParser.stations(from: data)
    }

    private func get(_ path: String, _ query: [String: String]) async throws(TrainServiceError) -> Data {
        guard let token, !token.isEmpty else { throw .missingToken }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Basic " + Data("\(token):".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw .offline
        } catch {
            throw .serverUnavailable
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        // Navitia answers "no_solution" / "date_out_of_bounds" with 404 + a JSON error body; the parser handles it.
        case 200..<300, 404: return data
        case 401, 403: throw .unauthorized
        case 429: throw .quotaExceeded
        default: throw .serverUnavailable
        }
    }
}
