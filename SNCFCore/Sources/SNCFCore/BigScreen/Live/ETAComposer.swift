import Foundation

/// Pure "Share ETA" text: one line a rider can forward, built only from the train and its leg. No fetch
/// and no state is the whole point — a `ShareLink` in the inspector calls it straight through. Times are
/// Europe/Paris in 24-hour form, like the station clock and the rest of the app's split-flap: an SNCF
/// train leaves at the time printed on the board, whatever zone the reader happens to be in.
public struct ETAComposer: ETAComposing {
    public init() {}

    public func shareText(for train: TrainDeparture, leg: Leg) -> String {
        let scheduled = Self.time.string(from: train.scheduledDeparture)
        let who = Self.who(train)

        // A cancelled train has no meaningful arrival, so a cancellation reads as its own sentence.
        if train.isCancelled {
            return "The \(scheduled)\(who.map { " (\($0))" } ?? "") to \(leg.to.name) is cancelled"
        }

        var line = "On the \(scheduled)"
        if let who { line += " (\(who))" }
        // A station board carries no arrival, so name the destination rather than invent a time.
        if let arrival = train.expectedArrival {
            line += ", arriving \(leg.to.name) \(Self.time.string(from: arrival))"
        } else {
            line += ", to \(leg.to.name)"
        }
        if let delay = train.delayMinutes, delay > 0 {
            line += ", running \(delay) min late"
        } else {
            line += ", on time"
        }
        return line
    }

    /// "TER 17655", or whichever half the row carries; nil when it has neither (a bare preview row).
    private static func who(_ train: TrainDeparture) -> String? {
        let text = [train.mode, train.trainNumber].compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static let time = SNCFTime.hhmmFormatter
}
