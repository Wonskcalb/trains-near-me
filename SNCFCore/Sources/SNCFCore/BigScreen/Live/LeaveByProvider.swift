import Foundation

#if canImport(MapKit)
import MapKit
#endif

/// The live "LEAVE HOME IN" provider for Wall mode: the pinned station, and the walk to a station. The
/// countdown itself is `firstCatchable(in:walk:now:)` over the board the Wall already holds, so it moves
/// on at every minute tick and never costs a request of its own.
///
/// The walk is the figure the user picked for that station; MapKit's walking ETA only stands in for a
/// station never set, and the stored default for when MapKit has no answer. Both sources sit behind
/// closures, so the tests never touch MapKit or the real defaults.
public struct LiveLeaveBy: LeaveByProviding {
    /// A walking ETA in minutes to a station, nil when there is none.
    public typealias WalkETA = @Sendable (_ station: Station) async -> Int?
    /// The walk the user set for a station id, nil while it is still the default.
    public typealias StoredWalk = @Sendable (_ stationID: String) -> Int?

    private let walkETA: WalkETA
    private let storedWalk: StoredWalk

    init(walkETA: @escaping WalkETA = { _ in nil },
         storedWalk: @escaping StoredWalk = { SharedSettings.walkMinutesIfSet(for: $0) }) {
        self.walkETA = walkETA
        self.storedWalk = storedWalk
    }

    /// Production: the stored walk, else MapKit's when it answers.
    public init() {
        self.init(walkETA: { await Self.walkMinutes(to: $0) })
    }

    public func pinnedStation() async -> Station? { SharedSettings.pinnedStation }

    public func pin(_ station: Station?) async { SharedSettings.pinnedStation = station }

    public func walkMinutes(to station: Station) async -> Int {
        if let set = storedWalk(station.id) { return set }
        return await walkETA(station) ?? SharedSettings.defaultWalkMinutes
    }

    /// The first train you can still walk to: not cancelled, and leaving no sooner than the walk from now.
    /// Pure, so the Wall re-runs it from the trains it holds at each minute.
    public static func firstCatchable(in trains: [TrainDeparture], walk: Int, now: Date) -> LeaveBy? {
        let offset = TimeInterval(-walk * 60)
        guard let train = trains.first(where: {
            !$0.isCancelled && $0.expectedDeparture.addingTimeInterval(offset) >= now
        }) else { return nil }
        return LeaveBy(train: train, walkMinutes: walk, leaveAt: train.expectedDeparture.addingTimeInterval(offset))
    }

    #if canImport(MapKit)
    /// The walking ETA from the user's position to the station, rounded up to a whole minute; nil on any
    /// failure. The origin is rounded to three decimals (about 100 m) first, as the SNCF nearest-station
    /// call is: the purpose string promises no more than that leaves the device, and a walk of minutes
    /// does not need it finer.
    static func walkMinutes(to station: Station) async -> Int? {
        guard let origin = await LocationFix.shared.current() else { return nil }
        let request = MKDirections.Request()
        request.transportType = .walking
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: rounded(origin.coordinate)))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)))
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return max(1, Int((eta.expectedTravelTime / 60).rounded(.up)))
    }

    static func rounded(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (coordinate.latitude * 1000).rounded() / 1000,
                               longitude: (coordinate.longitude * 1000).rounded() / 1000)
    }
    #else
    static func walkMinutes(to station: Station) async -> Int? { nil }
    #endif
}
