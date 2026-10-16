import Foundation

#if canImport(MapKit)
import MapKit
#endif

/// The live "LEAVE HOME IN" provider for Wall mode. It reads the pinned station and the per-station walk
/// time from `SharedSettings`, fetches the leg's board, and picks the first train you can still make.
///
/// The board fetch sits behind a `Board` closure and the walk-time refinement behind a `WalkETA` one, so
/// the catch-the-train logic is exercised by fixtures alone — no SNCF API, no MapKit — in the tests. The
/// production `init(token:)` wires those seams to `SNCFClient` and, where available, `MKDirections`.
public struct LiveLeaveBy: LeaveByProviding {
    /// A leg's board at a moment. Returns a `BoardState` so the same service-day filtering the rest of
    /// the app relies on is reused, rather than a parallel notion of "today's trains".
    public typealias Board = @Sendable (_ leg: Leg, _ now: Date) async -> BoardState
    /// A refined walk time in minutes to a station, or nil to fall back to the stored setting.
    public typealias WalkETA = @Sendable (_ station: Station) async -> Int?

    private let board: Board
    private let walkETA: WalkETA

    init(board: @escaping Board, walkETA: @escaping WalkETA = { _ in nil }) {
        self.board = board
        self.walkETA = walkETA
    }

    /// Production: the board from `SNCFClient.departures`, the walk time from MapKit when it answers. The
    /// token is read per request so one typed after launch is used at once.
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared,
                calendar: Calendar = SNCFTime.calendar) {
        self.init(
            board: { leg, now in
                let client = SNCFClient(token: token(), session: session)
                guard let trains = try? await client.departures(from: leg.from, to: leg.to, at: now) else {
                    return .noTrains
                }
                return BoardState.from(trains, now: now, calendar: calendar)
            },
            walkETA: { station in await Self.walkMinutes(to: station) })
    }

    public func pinnedStation() async -> Station? { SharedSettings.pinnedStation }

    public func pin(_ station: Station?) async { SharedSettings.pinnedStation = station }

    public func leaveBy(toCatch leg: Leg, at now: Date) async -> LeaveBy? {
        let stored = SharedSettings[walkMinutesFor: leg.from.id]
        // The board is the hot path; the MapKit refinement runs alongside it and never holds it up.
        async let boardState = board(leg, now)
        async let refined = walkETA(leg.from)
        let walk = await refined ?? stored

        guard case .departures(let trains) = await boardState else { return nil }
        let offset = TimeInterval(-walk * 60)
        guard let train = trains.first(where: {
            !$0.isCancelled && $0.expectedDeparture.addingTimeInterval(offset) >= now
        }) else { return nil }
        return LeaveBy(train: train, walkMinutes: walk, leaveAt: train.expectedDeparture.addingTimeInterval(offset))
    }

    #if canImport(MapKit)
    /// The walking ETA from the user's current position to the station, rounded up to a whole minute.
    /// nil on any failure — no location, no route, MapKit error — so the caller keeps the stored setting.
    static func walkMinutes(to station: Station) async -> Int? {
        guard let origin = await LocationFix.shared.current() else { return nil }
        let request = MKDirections.Request()
        request.transportType = .walking
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)))
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return max(1, Int((eta.expectedTravelTime / 60).rounded(.up)))
    }
    #else
    static func walkMinutes(to station: Station) async -> Int? { nil }
    #endif
}
