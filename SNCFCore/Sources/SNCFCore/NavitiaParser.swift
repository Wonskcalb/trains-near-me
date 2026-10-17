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

        let disruptions = byID(response.disruptions)
        var seen = Set<Date>()
        return journeys
            .compactMap { departure(for: $0, origin: origin, destination: destination, disruptions: disruptions) }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
            .filter { seen.insert($0.scheduledDeparture).inserted }
    }

    /// Decodes a `/stop_areas/{id}/departures` response, requested with the same
    /// `data_freshness=base_schedule` trick so cancelled trains stay in the board.
    public static func stopDepartures(from data: Data) throws(TrainServiceError) -> [TrainDeparture] {
        let response: StopDeparturesResponse
        do {
            response = try decoder.decode(StopDeparturesResponse.self, from: data)
        } catch {
            throw .malformedResponse
        }
        if let error = response.error {
            if noResultErrors.contains(error.id) { return [] }
            throw .malformedResponse
        }
        guard let departures = response.departures else { throw .malformedResponse }

        let disruptions = byID(response.disruptions)
        return departures
            .compactMap { departure(for: $0, disruptions: disruptions) }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    public static func stations(from data: Data) throws(TrainServiceError) -> [Station] {
        guard let response = try? decoder.decode(PlacesResponse.self, from: data) else { throw .malformedResponse }
        return (response.places ?? []).compactMap(station(from:))
    }

    /// `/coord/{lon};{lat}/places_nearby` answers in distance order, nearest first.
    public static func nearbyStations(from data: Data) throws(TrainServiceError) -> [Station] {
        guard let response = try? decoder.decode(PlacesNearbyResponse.self, from: data) else { throw .malformedResponse }
        return (response.placesNearby ?? []).compactMap(station(from:))
    }

    static func station(from place: PlaceResult) -> Station? {
        guard let area = place.stopArea, let coord = area.coord,
              let lat = Double(coord.lat), let lon = Double(coord.lon) else { return nil }
        return Station(id: area.id, name: area.name ?? place.name ?? area.id, latitude: lat, longitude: lon)
    }

    static let noResultErrors: Set<String> = ["no_solution", "date_out_of_bounds", "no_origin_nor_destination", "no_departure"]

    /// Only a single direct train from origin to destination counts as serving the journey.
    static func departure(for journey: Journey, origin: Station, destination: Station, disruptions: [String: Disruption]) -> TrainDeparture? {
        let transit = journey.sections.filter { $0.type == "public_transport" }
        guard transit.count == 1, let section = transit.first,
              section.from?.stopAreaID == origin.id, section.to?.stopAreaID == destination.id,
              let departure = parseDate(section.baseDepartureDateTime ?? section.departureDateTime),
              let arrival = parseDate(section.baseArrivalDateTime ?? section.arrivalDateTime)
        else { return nil }

        let linked = linkedDisruptions(section.displayInformations, disruptions)
        let stops = impactedStops(linked)
        let originStop = stops.first { $0.stopPoint?.id == section.from?.stopPoint?.id }
        let destinationStop = stops.first { $0.stopPoint?.id == section.to?.stopPoint?.id }

        let cancelled = journey.status == "NO_SERVICE"
            || isCancelled(linked, at: originStop)
            || destinationStop?.arrivalStatus == "deleted"

        let info = section.displayInformations
        return TrainDeparture(
            scheduledDeparture: departure,
            scheduledArrival: arrival,
            mode: mode(commercial: info?.commercialMode, physical: info?.physicalMode),
            delayMinutes: delay(at: originStop, significantDelays: journey.status == "SIGNIFICANT_DELAYS"),
            isCancelled: cancelled,
            trainNumber: info?.tripShortName ?? info?.headsign,
            vehicleJourneyID: section.links?.first { $0.type == "vehicle_journey" }?.id
        )
    }

    /// One row of a station board: no arrival time, but a direction to show instead.
    static func departure(for board: BoardDeparture, disruptions: [String: Disruption]) -> TrainDeparture? {
        let times = board.stopDateTime
        guard let departure = parseDate(times?.baseDepartureDateTime ?? times?.departureDateTime) else { return nil }

        let linked = linkedDisruptions(board.displayInformations, disruptions)
        let stop = impactedStops(linked).first { $0.stopPoint?.id == board.stopPoint?.id }
        let info = board.displayInformations

        return TrainDeparture(
            scheduledDeparture: departure,
            direction: info?.direction,
            mode: mode(commercial: info?.commercialMode, physical: info?.physicalMode),
            delayMinutes: delay(at: stop, significantDelays: linked.contains { $0.severity?.effect == "SIGNIFICANT_DELAYS" }),
            isCancelled: isCancelled(linked, at: stop),
            trainNumber: info?.tripShortName ?? info?.headsign,
            vehicleJourneyID: board.links?.first { $0.type == "vehicle_journey" }?.id,
            terminus: terminus(board.route?.direction?.stopArea, headsign: info?.direction)
        )
    }

    /// `route.direction` is the route's end, which a short working of the same route never reaches: it
    /// only names the train's terminus when the train's own headsign is that station ("Lyon Part Dieu
    /// (Lyon)" against stop_area "Lyon Part Dieu"). The town in brackets is dropped and the rest must be
    /// equal: a prefix let stop_area "Lyon" claim a train to "Lyon Perrache (Lyon)". Otherwise nil, and
    /// the headsign is resolved on demand.
    static func terminus(_ area: StopArea?, headsign: String?) -> Station? {
        guard let area, let name = area.name, let coord = area.coord,
              let lat = Double(coord.lat), let lon = Double(coord.lon) else { return nil }
        if let headsign {
            let station = headsign.components(separatedBy: " (").first ?? headsign
            guard folded(station) == folded(name) else { return nil }
        }
        return Station(id: area.id, name: name, latitude: lat, longitude: lon)
    }

    /// Letters and digits only, case and accents dropped: "Part-Dieu" and "Part Dieu" are one name.
    static func folded(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Decodes a `/vehicle_journeys/{id}` response into the train's full stopping pattern.
    public static func tripStops(from data: Data) throws(TrainServiceError) -> [TripStop] {
        let response: VehicleJourneysResponse
        do {
            response = try decoder.decode(VehicleJourneysResponse.self, from: data)
        } catch {
            throw .malformedResponse
        }
        if response.error != nil { throw .malformedResponse }
        guard let stops = response.vehicleJourneys?.first?.stopTimes else { throw .malformedResponse }
        return stops.compactMap { stop in
            guard let name = stop.stopPoint?.name else { return nil }
            // The terminus only arrives, the origin only departs; otherwise the two times match.
            let time = (stop.departureTime?.isEmpty == false ? stop.departureTime : stop.arrivalTime) ?? stop.arrivalTime
            return TripStop(name: name, time: hourMinute(time), isSkipped: stop.skippedStop ?? false)
        }
    }

    /// SNCF answers with the commercial brand, which is a regional code for every TER
    /// ("REGIONAURA", "TERGV"…), and with a normalised physical mode ("TER / Intercités",
    /// "Train grande vitesse"). Neither is presentable on its own, so they are read in order
    /// of what a traveller actually looks for: the national brand first, the family second.
    static func mode(commercial: String?, physical: String?) -> String? {
        let brand = (commercial ?? "").uppercased()
        let family = (physical ?? "").folding(options: .diacriticInsensitive, locale: .init(identifier: "fr_FR")).uppercased()
        for (needle, label) in [("OUIGO", "OUIGO"), ("TGV", "TGV"), ("INTERCIT", "Intercités"), ("EUROSTAR", "Eurostar"), ("LYRIA", "Lyria"), ("TER", "TER")] where brand.contains(needle) {
            return label
        }
        // "Car TER" is a coach replacing a train, and saying "TER" would hide that, so road first.
        if family.contains("CAR") || family.contains("BUS") { return "Car" }
        if family.contains("TER") { return "TER" }
        if family.contains("GRANDE VITESSE") { return "TGV" }
        if family.contains("INTERCIT") { return "Intercités" }
        return commercial?.isEmpty == false ? commercial : physical
    }

    static func byID(_ disruptions: [Disruption]?) -> [String: Disruption] {
        Dictionary((disruptions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func linkedDisruptions(_ info: DisplayInformations?, _ disruptions: [String: Disruption]) -> [Disruption] {
        (info?.links ?? [])
            .filter { $0.type == "disruption" || $0.rel == "disruptions" }
            .compactMap { $0.id.flatMap { disruptions[$0] } }
    }

    static func impactedStops(_ linked: [Disruption]) -> [ImpactedStop] {
        linked.flatMap { $0.impactedObjects ?? [] }.flatMap { $0.impactedStops ?? [] }
    }

    static func isCancelled(_ linked: [Disruption], at stop: ImpactedStop?) -> Bool {
        linked.contains { $0.severity?.effect == "NO_SERVICE" } || stop?.departureStatus == "deleted"
    }

    /// nil means "delayed by an unknown amount": SNCF announced the delay without an amended time.
    static func delay(at stop: ImpactedStop?, significantDelays: Bool) -> Int? {
        guard let base = stop?.baseDepartureTime.flatMap(secondsOfDay),
              let amended = stop?.amendedDepartureTime.flatMap(secondsOfDay) else {
            return significantDelays ? nil : 0
        }
        var diff = amended - base
        if diff < -12 * 3600 { diff += 24 * 3600 }
        return max(0, diff / 60)
    }

    static func parseDate(_ string: String?) -> Date? {
        string.flatMap { dateFormatter.date(from: $0) }
    }

    static func secondsOfDay(_ hhmmss: String) -> Int? {
        guard hhmmss.count == 6, let value = Int(hhmmss) else { return nil }
        return (value / 10000) * 3600 + (value / 100 % 100) * 60 + value % 100
    }

    /// A Navitia "HHMMSS" time of day as "HH:MM"; empty when the field is missing or malformed.
    static func hourMinute(_ hhmmss: String?) -> String {
        guard let s = hhmmss, s.count == 6 else { return "" }
        return "\(s.prefix(2)):\(s.dropFirst(2).prefix(2))"
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
    /// A public-transport section links its `vehicle_journey`, the same id a station board carries.
    let links: [Link]?
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
    let name: String?
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
    let commercialMode: String?
    let physicalMode: String?
    let direction: String?
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

struct StopDeparturesResponse: Decodable {
    let departures: [BoardDeparture]?
    let disruptions: [Disruption]?
    let error: APIError?
}

struct BoardDeparture: Decodable {
    let stopDateTime: StopDateTime?
    let displayInformations: DisplayInformations?
    let stopPoint: StopPoint?
    /// At `depth=2`, `route.direction.stop_area` is the terminus with its id and coordinates.
    let route: Route?
    /// Top-level links carry the `vehicle_journey` id used to fetch the train's full run.
    let links: [Link]?
}

struct Route: Decodable {
    let direction: RouteDirection?
}

struct RouteDirection: Decodable {
    let stopArea: StopArea?
}

struct StopDateTime: Decodable {
    let departureDateTime: String?
    let baseDepartureDateTime: String?
}

struct PlacesResponse: Decodable {
    let places: [PlaceResult]?
}

struct PlacesNearbyResponse: Decodable {
    let placesNearby: [PlaceResult]?
}

struct PlaceResult: Decodable {
    let name: String?
    let stopArea: StopArea?
}

struct VehicleJourneysResponse: Decodable {
    let vehicleJourneys: [VehicleJourney]?
    let error: APIError?
}

struct VehicleJourney: Decodable {
    let stopTimes: [StopTime]?
}

struct StopTime: Decodable {
    let arrivalTime: String?
    let departureTime: String?
    let skippedStop: Bool?
    let stopPoint: StopPoint?
}
