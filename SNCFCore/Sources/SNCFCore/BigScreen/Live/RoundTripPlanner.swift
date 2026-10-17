import Foundation

// The round-trip pairing, as pure logic: given the outbound options, the way-back options, which outbound
// is chosen and the minimum stay, decide how each return sits against "you arrive, then stay at least N".
// No network — `RoundTripLive` does the fetching and hands the two boards here. Everything is compared on
// EXPECTED departure/arrival (the amended time a traveller actually catches), and the returns come back
// sorted by that, so a delay that reorders the board can't make the tags go backwards.
public enum RoundTripPlanner {

    /// Choose the outbound, tag the returns, and package the plan. `returnLeg` is the reverse of `outbound`.
    /// `returnBoard` is the whole way back as fetched; only the trains from the chosen arrival on are
    /// listed, so a re-pick or a new stay re-plans from the same two boards without a request.
    /// `returnsCoverServiceDay` says the board runs to the 03:00 close: only then is its last train tonight
    /// truly the LAST TRAIN, rather than the last one a capped answer happened to hold.
    public static func plan(outbound: Leg,
                            outboundOptions: [TrainDeparture],
                            returnOptions returnBoard: [TrainDeparture],
                            pick: TrainIdentity?,
                            stay minimumStay: TimeInterval,
                            at now: Date,
                            returnsCoverServiceDay: Bool = false,
                            calendar: Calendar = SNCFTime.calendar) -> RoundTripPlan {
        let selected = selectedOutbound(from: outboundOptions, pick: pick, at: now, calendar: calendar)
        let arrival = selected?.expectedArrival
        let returns = arrival.map { arrival in returnBoard.filter { $0.expectedDeparture >= arrival } } ?? returnBoard
        let tonight = BoardState.serviceDay(of: now, calendar: calendar)
        return RoundTripPlan(outbound: outbound,
                             returnLeg: Leg(from: outbound.to, to: outbound.from),
                             minimumStay: minimumStay,
                             outboundOptions: outboundOptions,
                             selectedOutbound: selected,
                             returnOptions: tagReturns(returns, arrival: arrival, stay: minimumStay) { trains in
                                 // The last train back runs tonight; a morning row past 03:00 never is it.
                                 guard returnsCoverServiceDay else { return nil }
                                 return trains.lastIndex {
                                     !$0.isCancelled && BoardState.serviceDay(of: $0.scheduledDeparture, calendar: calendar) == tonight
                                 }
                             },
                             returnBoard: returnBoard,
                             returnsCoverServiceDay: returnsCoverServiceDay)
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
    /// `tooEarly`* then `firstThatFits` then `laterBy` (non-decreasing minutes) then `lastTrain`. `lastIndex`
    /// picks the row that is the service day's last train, nil when the list does not show it.
    static func tagReturns(_ returns: [TrainDeparture], arrival: Date?, stay minimumStay: TimeInterval,
                           lastIndex: ([TrainDeparture]) -> Int?) -> [ReturnOption] {
        let sorted = returns.sorted {
            $0.expectedDeparture != $1.expectedDeparture
                ? $0.expectedDeparture < $1.expectedDeparture
                : $0.scheduledDeparture < $1.scheduledDeparture
        }
        guard !sorted.isEmpty else { return [] }
        let lastIndex = lastIndex(sorted)

        // Nothing runs out, so there is no arrival to pair against: nothing can fit. Dim every row but keep
        // the last train back marked — it is still the board's last useful row.
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
                // Precedence: the last train is LAST TRAIN whenever it is catchable by time, and that wins
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

public extension RoundTripPlan {
    /// The same two boards planned again for another outbound or stay: what the stepper and a re-pick
    /// call, so neither costs a request.
    func replanned(pick: TrainIdentity?, stay: TimeInterval, at now: Date,
                   calendar: Calendar = SNCFTime.calendar) -> RoundTripPlan {
        RoundTripPlanner.plan(outbound: outbound, outboundOptions: outboundOptions, returnOptions: returnBoard,
                              pick: pick, stay: stay, at: now, returnsCoverServiceDay: returnsCoverServiceDay,
                              calendar: calendar)
    }
}
