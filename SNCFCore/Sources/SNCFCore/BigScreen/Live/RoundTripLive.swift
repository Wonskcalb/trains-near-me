import Foundation

/// The live round-trip provider: fetch the outbound board, pick an outbound, fetch the reverse leg from
/// that arrival onward, then let `RoundTripPlanner` tag the returns. The network sits behind the
/// `departures` seam so the provider's own logic (reverse leg, arrival window, re-plan) is fixture-testable
/// with no live call. Phase 2 wires this in; there is deliberately no `BigScreenData.live` here yet.
public struct RoundTripLive: RoundTripPlanning {
    private let calendar: Calendar
    private let departures: @Sendable (Leg, Date) async -> [TrainDeparture]

    /// Production: the token every other call site builds its `SNCFClient` from, plus the calendar whose
    /// 03:00 service day pins a `TrainIdentity`. A failed fetch degrades to an empty board (the protocol
    /// cannot throw), which reads as "nothing runs".
    public init(token: String?, session: URLSession = .shared, calendar: Calendar = .current) {
        self.calendar = calendar
        self.departures = { leg, date in
            (try? await SNCFClient(token: token, session: session).departures(from: leg.from, to: leg.to, at: date)) ?? []
        }
    }

    /// Testable seam: fixtures answer `departures` directly, no network.
    init(calendar: Calendar = .current, departures: @escaping @Sendable (Leg, Date) async -> [TrainDeparture]) {
        self.calendar = calendar
        self.departures = departures
    }

    public func roundTrip(outbound: Leg, pick: TrainIdentity?, stay minimumStay: TimeInterval, at now: Date) async -> RoundTripPlan {
        let outboundOptions = await departures(outbound, now)
        let selected = RoundTripPlanner.selectedOutbound(from: outboundOptions, pick: pick, at: now, calendar: calendar)
        let returnLeg = Leg(from: outbound.to, to: outbound.from)
        // Fetch the way back from the chosen arrival onward (or from `now` when nothing runs out), so the
        // board starts where the journey back can begin; the planner tags each return against arrival + stay,
        // keeping the first few "too early" rows the mockup shows before the first that fits.
        let returns = await departures(returnLeg, selected?.expectedArrival ?? now)
        return RoundTripPlanner.plan(outbound: outbound, outboundOptions: outboundOptions,
                                     returnOptions: returns, pick: pick, stay: minimumStay,
                                     at: now, calendar: calendar)
    }
}
