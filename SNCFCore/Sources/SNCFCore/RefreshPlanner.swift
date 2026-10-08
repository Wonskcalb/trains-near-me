import Foundation

/// WidgetKit grants roughly 40–70 reloads per widget per day, so asking more often than
/// every 15 minutes buys nothing; 1 reload ≈ 1 SNCF request keeps us far below 5 000/day.
public enum RefreshPlanner {
    public static let refreshInterval: TimeInterval = 15 * 60
    public static let idleRefreshInterval: TimeInterval = 60 * 60
    /// Past this age the widget stops showing trains instead of presenting old data as current.
    public static let staleAfter: TimeInterval = 30 * 60

    /// One entry now, one just after each train leaves (so it drops off the list), one when data goes stale.
    public static func entryDates(fetchedAt: Date, departures: [TrainDeparture]) -> [Date] {
        let staleDate = fetchedAt.addingTimeInterval(staleAfter)
        let departureDates = departures
            .map { $0.expectedDeparture.addingTimeInterval(60) }
            .filter { $0 > fetchedAt && $0 < staleDate }
        return Array(Set([fetchedAt, staleDate] + departureDates)).sorted()
    }

    public static func nextRefresh(fetchedAt: Date, state: BoardState) -> Date {
        switch state {
        case .noTrains, .noService: fetchedAt.addingTimeInterval(idleRefreshInterval)
        case .departures, .unavailable: fetchedAt.addingTimeInterval(refreshInterval)
        }
    }

    public static func isStale(fetchedAt: Date, at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) >= staleAfter
    }
}
