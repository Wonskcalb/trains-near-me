import Foundation

// The round-trip pairing, as pure logic: given the outbound options, the way-back options, which outbound
// is chosen and the minimum stay, decide how each return sits against "you arrive, then stay at least N".
// No network — `RoundTripLive` does the fetching and hands the two boards here. Everything is compared on
// EXPECTED departure/arrival (the amended time a traveller actually catches), and the returns come back
// sorted by that, so a delay that reorders the board can't make the tags go backwards.
public enum RoundTripPlanner {

    /// Choose the outbound, tag the returns, and package the plan. `returnLeg` is the reverse of `outbound`.
    public static func plan(outbound: Leg,
                            outboundOptions: [TrainDeparture],
                            returnOptions returns: [TrainDeparture],
                            pick: TrainIdentity?,
                            stay minimumStay: TimeInterval,
                            at now: Date,
                            calendar: Calendar = .current) -> RoundTripPlan {
        let selected = selectedOutbound(from: outboundOptions, pick: pick, at: now, calendar: calendar)
        return RoundTripPlan(outbound: outbound,
                             returnLeg: Leg(from: outbound.to, to: outbound.from),
                             minimumStay: minimumStay,
                             outboundOptions: outboundOptions,
                             selectedOutbound: selected,
                             returnOptions: tagReturns(returns, arrival: selected?.expectedArrival, stay: minimumStay))
    }

    /// The chosen outbound: the one matching `pick` when it is still on the board (an explicit choice wins,
    /// even if it has since been cancelled or has left), otherwise the next upcoming non-cancelled train.
    public static func selectedOutbound(from options: [TrainDeparture], pick: TrainIdentity?,
                                        at now: Date, calendar: Calendar) -> TrainDeparture? {
        if let pick, let picked = options.first(where: { TrainIdentity($0, calendar: calendar) == pick }) {
            return picked
        }
        return options
            .filter { !$0.isCancelled && $0.expectedDeparture >= now }
            .min { $0.expectedDeparture < $1.expectedDeparture }
    }

    /// Tag each return against `arrival + stay`. Ordered by expected departure the fit never goes backwards:
    /// `tooEarly`* then `firstThatFits` then `laterBy` (non-decreasing minutes) then `lastTrain`.
    static func tagReturns(_ returns: [TrainDeparture], arrival: Date?, stay minimumStay: TimeInterval) -> [ReturnOption] {
        let sorted = returns.sorted {
            $0.expectedDeparture != $1.expectedDeparture
                ? $0.expectedDeparture < $1.expectedDeparture
                : $0.scheduledDeparture < $1.scheduledDeparture
        }
        guard !sorted.isEmpty else { return [] }
        let lastIndex = sorted.count - 1

        // Nothing runs out, so there is no arrival to pair against: nothing can fit. Dim every row but keep
        // the final one as the last train back — it is still the board's last useful row.
        guard let arrival else {
            return sorted.enumerated().map { index, train in
                ReturnOption(train: train, fit: index == lastIndex ? .lastTrain : .tooEarly)
            }
        }

        let threshold = arrival + minimumStay
        // The first return you can actually make: earliest expected departure at or after the threshold that
        // is not cancelled. A cancelled return is never the first-that-fits, so this is also the re-plan —
        // when the natural first choice is cancelled (or delayed past a later train) the tag lands on the
        // next one that fits, which is what `RoundTripPlan.pairedReturn` reads.
        let fitIndex = sorted.firstIndex { !$0.isCancelled && $0.expectedDeparture >= threshold }

        return sorted.enumerated().map { index, train in
            let fit: ReturnFit
            if index == lastIndex, train.expectedDeparture >= threshold {
                // Precedence: the final row is LAST TRAIN whenever it is catchable by time, and that wins
                // over first-that-fits / later-by on that one row. Consequence: on a day whose only fitting
                // return is also the last of the service day, it is tagged `lastTrain`, so there is no
                // `firstThatFits` and `pairedReturn` is nil.
                fit = .lastTrain
            } else if index == fitIndex {
                fit = .firstThatFits
            } else if let fitIndex, index > fitIndex {
                // How much longer you would stay than the first-that-fits train. Non-negative because the
                // list is sorted by expected departure and this row comes after the anchor.
                let longer = train.expectedDeparture.timeIntervalSince(sorted[fitIndex].expectedDeparture)
                fit = .laterBy(minutes: Int((longer / 60).rounded()))
            } else {
                // Before the one you catch: either genuinely before the threshold, or a cancelled return
                // that precedes it. Both read as "not this one" — dimmed, TOO EARLY.
                fit = .tooEarly
            }
            return ReturnOption(train: train, fit: fit)
        }
    }
}
