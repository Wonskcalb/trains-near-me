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
    public let scheduledArrival: Date
    /// nil when SNCF signals a disruption without an amended time.
    public let delayMinutes: Int?
    public let isCancelled: Bool
    public let trainNumber: String?

    public init(scheduledDeparture: Date, scheduledArrival: Date, delayMinutes: Int?, isCancelled: Bool, trainNumber: String?) {
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.delayMinutes = delayMinutes
        self.isCancelled = isCancelled
        self.trainNumber = trainNumber
    }

    public var expectedDeparture: Date {
        scheduledDeparture.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60))
    }

    public var duration: TimeInterval { scheduledArrival.timeIntervalSince(scheduledDeparture) }

    public var status: DepartureStatus { .from(delayMinutes: delayMinutes, cancelled: isCancelled) }
}

public enum BoardState: Equatable, Sendable {
    case departures([TrainDeparture])
    case noTrains
    case noService
    case unavailable(TrainServiceError)

    public static func from(_ departures: [TrainDeparture]) -> BoardState {
        if departures.isEmpty { return .noTrains }
        if departures.allSatisfy(\.isCancelled) { return .noService }
        return .departures(departures)
    }
}

public enum TrainServiceError: Error, Equatable, Sendable {
    case missingToken
    case unauthorized
    case quotaExceeded
    case offline
    case serverUnavailable
    case malformedResponse
}

public protocol TrainService: Sendable {
    func departures(from: Station, to: Station, at: Date) async throws(TrainServiceError) -> [TrainDeparture]
}
