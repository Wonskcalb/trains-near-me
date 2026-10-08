import Foundation

/// Decodes `/journeys` responses requested with `data_freshness=base_schedule`.
/// In that mode cancelled trips stay in the results and realtime changes are only
/// described by the linked disruptions, which is what lets us show "CANCELLED" rows.
public enum NavitiaParser {
    public static func departures(from data: Data, origin: Station, destination: Station) throws(TrainServiceError) -> [TrainDeparture] {
        let response: JourneysResponse
        do {
            response = try decoder.decode(JourneysResponse.self, from: data)
        } catch {
            throw .malformedResponse
        }
        if let error = response.error {
            if noResultErrors.contains(error.id) { return [] }
            throw .malformedResponse
        }
        guard let journeys = response.journeys else { throw .malformedResponse }

        let disruptions = Dictionary((response.disruptions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<Date>()
        return journeys
            .compactMap { departure(for: $0, origin: origin, destination: destination, disruptions: disruptions) }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
            .filter { seen.insert($0.scheduledDeparture).inserted }
    }

    public static func stations(from data: Data) throws(TrainServiceError) -> [Station] {
        guard let response = try? decoder.decode(PlacesResponse.self, from: data) else { throw .malformedResponse }
        return (response.places ?? []).compactMap { place in
            guard let area = place.stopArea, let coord = area.coord,
                  let lat = Double(coord.lat), let lon = Double(coord.lon) else { return nil }
            return Station(id: area.id, name: area.name ?? place.name ?? area.id, latitude: lat, longitude: lon)
        }
    }

    static let noResultErrors: Set<String> = ["no_solution", "date_out_of_bounds", "no_origin_nor_destination"]

    /// Only a single direct train from origin to destination counts as serving the journey.
    static func departure(for journey: Journey, origin: Station, destination: Station, disruptions: [String: Disruption]) -> TrainDeparture? {
        let transit = journey.sections.filter { $0.type == "public_transport" }
        guard transit.count == 1, let section = transit.first,
              section.from?.stopAreaID == origin.id, section.to?.stopAreaID == destination.id,
              let departure = parseDate(section.baseDepartureDateTime ?? section.departureDateTime),
              let arrival = parseDate(section.baseArrivalDateTime ?? section.arrivalDateTime)
        else { return nil }

        let linked = (section.displayInformations?.links ?? [])
            .filter { $0.type == "disruption" || $0.rel == "disruptions" }
            .compactMap { $0.id.flatMap { disruptions[$0] } }
        let impactedStops = linked.flatMap { $0.impactedObjects ?? [] }.flatMap { $0.impactedStops ?? [] }
        let originStop = impactedStops.first { $0.stopPoint?.id == section.from?.stopPoint?.id }
        let destinationStop = impactedStops.first { $0.stopPoint?.id == section.to?.stopPoint?.id }

        let cancelled = journey.status == "NO_SERVICE"
            || linked.contains { $0.severity?.effect == "NO_SERVICE" }
            || originStop?.departureStatus == "deleted"
            || destinationStop?.arrivalStatus == "deleted"

        let delay: Int?
        if let base = originStop?.baseDepartureTime.flatMap(secondsOfDay),
           let amended = originStop?.amendedDepartureTime.flatMap(secondsOfDay) {
            var diff = amended - base
            if diff < -12 * 3600 { diff += 24 * 3600 }
            delay = max(0, diff / 60)
        } else if journey.status == "SIGNIFICANT_DELAYS" {
            delay = nil
        } else {
            delay = 0
        }

        let info = section.displayInformations
        return TrainDeparture(
            scheduledDeparture: departure,
            scheduledArrival: arrival,
            delayMinutes: delay,
            isCancelled: cancelled,
            trainNumber: info?.tripShortName ?? info?.headsign
        )
    }

    static func parseDate(_ string: String?) -> Date? {
        string.flatMap { dateFormatter.date(from: $0) }
    }

    static func secondsOfDay(_ hhmmss: String) -> Int? {
        guard hhmmss.count == 6, let value = Int(hhmmss) else { return nil }
        return (value / 10000) * 3600 + (value / 100 % 100) * 60 + value % 100
    }

    /// Navitia datetimes are naive local times of the coverage (Europe/Paris for SNCF).
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

struct JourneysResponse: Decodable {
    let journeys: [Journey]?
    let disruptions: [Disruption]?
    let error: APIError?
}

struct APIError: Decodable {
    let id: String
}

struct Journey: Decodable {
    let status: String?
    let sections: [Section]
}

struct Section: Decodable {
    let type: String
    let departureDateTime: String?
    let arrivalDateTime: String?
    let baseDepartureDateTime: String?
    let baseArrivalDateTime: String?
    let from: Place?
    let to: Place?
    let displayInformations: DisplayInformations?
}

struct Place: Decodable {
    let id: String
    let name: String?
    let stopPoint: StopPoint?
    let stopArea: StopArea?

    var stopAreaID: String? { stopArea?.id ?? stopPoint?.stopArea?.id }
}

struct StopPoint: Decodable {
    let id: String
    let stopArea: StopArea?
}

struct StopArea: Decodable {
    let id: String
    let name: String?
    let coord: Coord?
}

struct Coord: Decodable {
    let lat: String
    let lon: String
}

struct DisplayInformations: Decodable {
    let headsign: String?
    let tripShortName: String?
    let links: [Link]?
}

struct Link: Decodable {
    let id: String?
    let type: String?
    let rel: String?
}

struct Disruption: Decodable {
    let id: String
    let severity: Severity?
    let impactedObjects: [ImpactedObject]?
}

struct Severity: Decodable {
    let effect: String?
}

struct ImpactedObject: Decodable {
    let impactedStops: [ImpactedStop]?
}

struct ImpactedStop: Decodable {
    let stopPoint: StopPoint?
    let baseDepartureTime: String?
    let amendedDepartureTime: String?
    let departureStatus: String?
    let arrivalStatus: String?
}

struct PlacesResponse: Decodable {
    let places: [PlaceResult]?
}

struct PlaceResult: Decodable {
    let name: String?
    let stopArea: StopArea?
}
