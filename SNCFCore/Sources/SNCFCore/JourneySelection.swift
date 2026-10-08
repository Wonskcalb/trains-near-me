import CoreLocation
import Foundation

public enum DirectionMode: String, Codable, Sendable {
    case forward
    case reverse
    case automatic
}

public struct JourneyConfiguration: Equatable, Sendable {
    public var stationA: Station
    public var stationB: Station
    public var direction: DirectionMode
    /// Minutes after midnight at which `.automatic` flips to B → A.
    public var switchMinute: Int
    public var nearestStationAsDeparture: Bool

    public init(stationA: Station, stationB: Station, direction: DirectionMode = .forward, switchMinute: Int = 13 * 60, nearestStationAsDeparture: Bool = false) {
        self.stationA = stationA
        self.stationB = stationB
        self.direction = direction
        self.switchMinute = switchMinute
        self.nearestStationAsDeparture = nearestStationAsDeparture
    }
}

public struct Leg: Equatable, Sendable {
    public let from: Station
    public let to: Station

    public init(from: Station, to: Station) {
        self.from = from
        self.to = to
    }
}

public enum JourneySelector {
    /// Nearest-station mode wins when a location is known; otherwise the direction mode applies.
    public static func leg(for config: JourneyConfiguration, at date: Date, location: CLLocation?, calendar: Calendar = .current) -> Leg {
        let forward = Leg(from: config.stationA, to: config.stationB)
        let reverse = Leg(from: config.stationB, to: config.stationA)

        if config.nearestStationAsDeparture, let location {
            return nearestIsA(config.stationA, config.stationB, to: location) ? forward : reverse
        }
        switch config.direction {
        case .forward: return forward
        case .reverse: return reverse
        case .automatic:
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return minute < config.switchMinute ? forward : reverse
        }
    }

    /// Ties go to A so the result is deterministic.
    static func nearestIsA(_ a: Station, _ b: Station, to location: CLLocation) -> Bool {
        let da = location.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
        let db = location.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        return da <= db
    }
}
