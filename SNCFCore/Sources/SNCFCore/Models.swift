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

public struct TrainDeparture: Hashable, Sendable {
    public let scheduledDeparture: Date
    /// nil on a station board: the departures endpoint only says when the train leaves.
    public let scheduledArrival: Date?
    /// Headsign of the train's final stop; nil for a journey, where the arrival is known instead.
    public let direction: String?
    /// nil when SNCF signals a disruption without an amended time.
    public let delayMinutes: Int?
    public let isCancelled: Bool
    public let trainNumber: String?

    public init(scheduledDeparture: Date, scheduledArrival: Date? = nil, direction: String? = nil, delayMinutes: Int?, isCancelled: Bool, trainNumber: String?) {
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.direction = direction
        self.delayMinutes = delayMinutes
        self.isCancelled = isCancelled
        self.trainNumber = trainNumber
    }

    public var expectedDeparture: Date {
        scheduledDeparture.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60))
    }

    public var duration: TimeInterval? { scheduledArrival?.timeIntervalSince(scheduledDeparture) }

    public var status: DepartureStatus { .from(delayMinutes: delayMinutes, cancelled: isCancelled) }
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
            guard let first = departures.first(where: { !$0.isCancelled }) else { return .noService }
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
}
