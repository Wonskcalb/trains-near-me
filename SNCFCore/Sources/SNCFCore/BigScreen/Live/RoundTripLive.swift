import Foundation

/// The live round-trip provider: fetch the outbound board and the way back, then let `RoundTripPlanner`
/// pick the outbound and tag the returns. The way back is fetched once, from the earliest outbound arrival
/// to the 03:00 close, so the plan it returns can be re-planned for any other pick or stay
/// (`RoundTripPlan.replanned`) without a request. The network sits behind the `departures` seam so the
/// provider's own logic is fixture-testable with no live call; `BigScreenData.live()` builds the production one.
public struct RoundTripLive: RoundTripPlanning {
    /// A leg's direct trains from a date: the default dozen when `within` is nil, else that many seconds.
    typealias Departures = @Sendable (_ leg: Leg, _ from: Date, _ within: TimeInterval?) async -> [TrainDeparture]

    private let calendar: Calendar
    private let departures: Departures

    /// Production: the token every other call site builds its `SNCFClient` from (read per request, so one
    /// typed after launch counts), plus the calendar whose 03:00 service day pins a `TrainIdentity`. A
    /// failed fetch degrades to an empty board (the protocol cannot throw), which reads as "nothing runs".
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared,
                calendar: Calendar = SNCFTime.calendar) {
        self.calendar = calendar
        self.departures = { leg, date, within in
            let client = SNCFClient(token: token(), session: session)
            if let within { return (try? await client.departures(from: leg.from, to: leg.to, at: date, within: within)) ?? [] }
            return (try? await client.departures(from: leg.from, to: leg.to, at: date)) ?? []
        }
    }

    /// Testable seam: fixtures answer `departures` directly, no network.
    init(calendar: Calendar = SNCFTime.calendar, departures: @escaping Departures) {
        self.calendar = calendar
        self.departures = departures
    }

    public func roundTrip(outbound: Leg, pick: TrainIdentity?, stay minimumStay: TimeInterval, at now: Date) async -> RoundTripPlan {
        let outboundOptions = await departures(outbound, now, nil)
        // From the soonest arrival any outbound pick can give, to the end of the service day: one request
        // that holds every return any pick could pair with, and that runs to the real last train (a count
        // alone stopped at a dozen and tagged the twelfth LAST TRAIN).
        let from = outboundOptions.compactMap(\.expectedArrival).filter { $0 >= now }.min() ?? now
        let window = BoardState.restOfServiceDay(after: from, atLeast: 4 * 3600, calendar: calendar)
        let returns = await departures(Leg(from: outbound.to, to: outbound.from), from, window)
        return RoundTripPlanner.plan(outbound: outbound, outboundOptions: outboundOptions,
                                     returnOptions: returns, pick: pick, stay: minimumStay,
                                     at: now, returnsCoverServiceDay: true, calendar: calendar)
    }
}
