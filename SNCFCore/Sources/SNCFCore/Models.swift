import Foundation

public struct Station: Hashable, Codable, Sendable {
    /// Navitia stop_area id, e.g. "stop_area:SNCF:87747006".
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum DepartureStatus: Equatable, Sendable {
    case onTime
    case delayed
    case severelyDelayed
    case cancelled
    /// SNCF reports a disruption but no usable delay figure.
    case unknown

    /// The spec's bands overlap at 10 and 20: 10 counts as on time, 20 as severe.
    public static func from(delayMinutes: Int?, cancelled: Bool) -> DepartureStatus {
        if cancelled { return .cancelled }
        guard let delay = delayMinutes else { return .unknown }
        switch delay {
        case ..<11: return .onTime
        case 11..<20: return .delayed
        default: return .severelyDelayed
        }
    }
}

public struct TrainDeparture: Hashable, Codable, Sendable {
    public let scheduledDeparture: Date
    /// nil on a station board: the departures endpoint only says when the train leaves.
    public let scheduledArrival: Date?
    /// Headsign of the train's final stop; nil for a journey, where the arrival is known instead.
    public let direction: String?
    /// Short service name: TER, TGV, OUIGO, Intercités… See `NavitiaParser.mode(commercial:physical:)`.
    public let mode: String?
    /// nil when SNCF signals a disruption without an amended time.
    public let delayMinutes: Int?
    public let isCancelled: Bool
    public let trainNumber: String?
    /// The train's Navitia vehicle_journey id, carried by station-board and journey rows alike so its
    /// full list of stops can be fetched on tap. nil on boards cached by an older build.
    public let vehicleJourneyID: String?
    /// The stop_area the train runs to, on a station board asked at `depth=2`: what a journey to that
    /// terminus is opened with. Optional so boards cached by an older build, which never had it, decode.
    public let terminus: Station?

    public init(scheduledDeparture: Date, scheduledArrival: Date? = nil, direction: String? = nil, mode: String? = nil, delayMinutes: Int?, isCancelled: Bool, trainNumber: String?, vehicleJourneyID: String? = nil, terminus: Station? = nil) {
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.direction = direction
        self.mode = mode
        self.delayMinutes = delayMinutes
        self.isCancelled = isCancelled
        self.trainNumber = trainNumber
        self.vehicleJourneyID = vehicleJourneyID
        self.terminus = terminus
    }

    public var expectedDeparture: Date {
        scheduledDeparture.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60))
    }

    public var duration: TimeInterval? { scheduledArrival?.timeIntervalSince(scheduledDeparture) }

    public var status: DepartureStatus { .from(delayMinutes: delayMinutes, cancelled: isCancelled) }
}

/// One stop of a train's run, for the full-trip sheet. The time is already the local "HH:MM": the
/// vehicle_journeys endpoint answers with times of day, not full datetimes.
public struct TripStop: Hashable, Codable, Sendable {
    public let name: String
    /// When the train calls here, "HH:MM".
    public let time: String
    /// Served but not boardable (Navitia `skipped_stop`): shown struck through.
    public let isSkipped: Bool

    public init(name: String, time: String, isSkipped: Bool) {
        self.name = name
        self.time = time
        self.isSkipped = isSkipped
    }

    /// Whether this stop is that station. The stop is named by its stop_point and the station by its
    /// stop_area, which SNCF does not always spell alike ("Part-Dieu" / "Part Dieu"), so names are folded.
    public func isAt(_ station: Station) -> Bool {
        NavitiaParser.folded(name) == NavitiaParser.folded(station.name)
    }
}

public enum BoardState: Equatable, Sendable {
    case departures([TrainDeparture])
    /// Today's service is over; SNCF already returned the next service day's trains.
    case endOfService(firstTrain: Date)
    case noTrains
    case noService
    case unavailable(TrainServiceError)

    /// Only trains of the current service day are listed; later ones mean the day is over.
    public static func from(_ departures: [TrainDeparture], now: Date, calendar: Calendar = .current) -> BoardState {
        if departures.isEmpty { return .noTrains }
        let today = serviceDay(of: now, calendar: calendar)
        let todays = departures.filter { serviceDay(of: $0.scheduledDeparture, calendar: calendar) == today }
        if todays.isEmpty {
            // Nothing left today is the end of service, never "no service": these trains all belong to a
            // later day, and a short answer holding only a cancelled first train (06:39 cancelled, the
            // 07:24 beyond the window) says nothing about whether tomorrow runs. Without a train to name,
            // it is just "no train found"; a caller that fetched the morning names the first one.
            guard let first = departures.first(where: { !$0.isCancelled }) else { return .noTrains }
            return .endOfService(firstTrain: first.scheduledDeparture)
        }
        if todays.allSatisfy(\.isCancelled) { return .noService }
        return .departures(todays)
    }

    /// Night trains up to 03:00 still belong to the previous evening's service.
    static func serviceDay(of date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-3 * 3600))
    }
}

/// SNCF runs on Europe/Paris whatever zone the device is in. One calendar for everything that must agree
/// across processes and devices — a watched train's `.numbered` identity, the service day the big-screen
/// providers cut on — so a Mac set to another zone still matches the identity the iPhone recorded.
public enum SNCFTime {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
}

public enum TrainServiceError: Error, Equatable, Sendable {
    case missingToken
    case unauthorized
    case quotaExceeded
    case offline
    case serverUnavailable
    case malformedResponse
    /// Radar mode only: no usable location, or no station around it.
    case noLocation
    case noStationNearby
}

extension TrainServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingToken: "Add your SNCF API token in the Trains near me app."
        case .unauthorized: "The SNCF API token was rejected."
        case .quotaExceeded: "SNCF API daily quota reached."
        case .offline: "No internet connection."
        case .serverUnavailable: "The SNCF API is not responding."
        case .malformedResponse: "Unexpected response from the SNCF API."
        case .noLocation: "No location: allow it in Trains near me."
        case .noStationNearby: "No station within \(SNCFClient.searchRadiusKilometres) km."
        }
    }

    /// A couple of words, for a Lock Screen complication where `errorDescription` never fits.
    public var terse: String {
        switch self {
        case .missingToken: "No token"
        case .unauthorized: "Token refused"
        case .quotaExceeded: "Quota reached"
        case .offline: "Offline"
        case .serverUnavailable: "SNCF down"
        case .malformedResponse: "Data error"
        case .noLocation: "No location"
        case .noStationNearby: "No station near"
        }
    }
}
