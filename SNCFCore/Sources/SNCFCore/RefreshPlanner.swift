import Foundation

/// WidgetKit grants roughly 40–70 reloads per widget per day. Asking at a fixed interval spends
/// that budget uniformly — including all night, when nothing moves — and the system then starts
/// refusing reloads during the evening rush, which is exactly when a delay matters. So reloads are
/// asked for just before a train leaves, never closer together than `minimumGap`, and not at all
/// between the last train of the day and the first of the next.
public enum RefreshPlanner {
    /// Retry delay after an error, and fallback when the fetched list runs out.
    public static let refreshInterval: TimeInterval = 15 * 60
    public static let idleRefreshInterval: TimeInterval = 60 * 60
    /// A delay is worth knowing shortly before the train leaves, not two hours earlier.
    public static let leadTime: TimeInterval = 5 * 60
    /// The budget knob. 20 min caps a dense service day at about 3 reloads an hour; raise it if
    /// the system starts refusing reloads (the timestamp then stays orange for long stretches).
    public static let minimumGap: TimeInterval = 20 * 60
    /// Past this age the delays are no longer trustworthy and the widget says so. The schedule
    /// itself stays useful for hours, so the trains keep being listed.
    public static let staleAfter: TimeInterval = 30 * 60

    /// One entry now, one just after each train leaves (so it drops off the list), one when
    /// the delays go stale. A single fetch therefore keeps the widget right for the whole
    /// evening, however long the system takes to grant the next reload.
    public static func entryDates(fetchedAt: Date, departures: [TrainDeparture]) -> [Date] {
        let departureDates = departures
            .map { $0.expectedDeparture.addingTimeInterval(60) }
            .filter { $0 > fetchedAt }
        return Array(Set([fetchedAt, fetchedAt.addingTimeInterval(staleAfter)] + departureDates)).sorted()
    }

    public static func nextRefresh(fetchedAt: Date, state: BoardState) -> Date {
        switch state {
        case .departures(let trains):
            let next = trains
                .first { $0.expectedDeparture > fetchedAt.addingTimeInterval(leadTime) }
                .map { $0.expectedDeparture.addingTimeInterval(-leadTime) }
                ?? fetchedAt.addingTimeInterval(refreshInterval)
            return clamp(next, from: fetchedAt.addingTimeInterval(minimumGap), to: fetchedAt.addingTimeInterval(idleRefreshInterval))
        case .endOfService(let firstTrain):
            // Nothing runs until tomorrow: one reload before the first train beats polling all night.
            return max(firstTrain.addingTimeInterval(-leadTime), fetchedAt.addingTimeInterval(refreshInterval))
        case .noTrains, .noService:
            return fetchedAt.addingTimeInterval(idleRefreshInterval)
        case .unavailable:
            return fetchedAt.addingTimeInterval(refreshInterval)
        }
    }

    static func clamp(_ date: Date, from: Date, to: Date) -> Date { min(max(date, from), to) }

    /// When a screen that polls on its own (the menu-bar label, which runs all day and night) should fetch
    /// again: every `refreshInterval` while a train still runs tonight, then nothing until `staleAfter`
    /// before the morning's first, or an idle hour when there is no first train to name.
    public static func nextPoll(after fetchedAt: Date, state: BoardState, tomorrow: [TrainDeparture]) -> Date {
        let retry = fetchedAt.addingTimeInterval(refreshInterval)
        if case .unavailable = state { return retry }
        if case .departures(let trains) = state, trains.contains(where: { !$0.isCancelled && $0.expectedDeparture > fetchedAt }) {
            return retry
        }
        var first = tomorrow.first { !$0.isCancelled }?.expectedDeparture
        if first == nil, case .endOfService(let firstTrain) = state { first = firstTrain }
        guard let first else { return fetchedAt.addingTimeInterval(idleRefreshInterval) }
        return max(first.addingTimeInterval(-staleAfter), retry)
    }

    public static func isStale(fetchedAt: Date, at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) >= staleAfter
    }
}
