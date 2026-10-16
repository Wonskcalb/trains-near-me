import Foundation

/// Live `ServiceDayProviding`: the whole service day of one leg, summarised into the last train tonight,
/// the first tomorrow, and the 24-hour histogram the Lanes minimap draws — then cached in the App Group
/// for the day so the histogram is fetched once. Only timetable facts are cached; delays are real time
/// and are read off the live board by the screens.
public struct LiveServiceDay: ServiceDayProviding {
    /// Every train of the leg from the given 03:00 service-day start onward, plus at least the first few
    /// of the next morning (for "FIRST TOMORROW").
    public typealias Fetch = @Sendable (Leg, Date) async -> [TrainDeparture]

    private let fetch: Fetch
    private let calendar: Calendar
    /// The App-Group suite name, nil without a group (a free Apple account on iOS): the summary is then
    /// recomputed each call instead of cached, which costs only a few extra requests a day. A name rather
    /// than a `UserDefaults` because the provider must stay `Sendable`.
    private let cacheSuite: String?

    public init(calendar: Calendar = SNCFTime.calendar, cacheSuite: String? = SharedSettings.appGroupSuiteName,
                fetch: @escaping Fetch) {
        self.calendar = calendar
        self.cacheSuite = cacheSuite
        self.fetch = fetch
    }

    /// Production wiring: the 24 h window from 03:00 in one `journeys` request (`min_nb_journeys` alone
    /// stops at a dozen trains), and a second ordinary one from the next 03:00 for tomorrow's first train.
    /// `base_schedule` keeps cancelled trips in the count, as everywhere else in the app. The token is read
    /// per fetch so one typed after launch is picked up.
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token }, session: URLSession = .shared,
                calendar: Calendar = SNCFTime.calendar, cacheSuite: String? = SharedSettings.appGroupSuiteName) {
        self.init(calendar: calendar, cacheSuite: cacheSuite) { leg, start in
            let client = SNCFClient(token: token(), session: session)
            guard let day = try? await client.departures(from: leg.from, to: leg.to, at: start, within: 24 * 3600) else { return [] }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
            let next = (try? await client.departures(from: leg.from, to: leg.to, at: tomorrow)) ?? []
            return day + next
        }
    }

    public func summary(for leg: Leg, at now: Date) async -> ServiceDaySummary? {
        let dayStart = BoardState.serviceDay(of: now, calendar: calendar)
        if let cached = cachedSummary(leg: leg, dayStart: dayStart) { return cached }
        // `dayStart` is local midnight; the service day itself opens at 03:00. Set by wall-clock hour, not
        // +3 h, so a DST night still starts at 03:00.
        let opens = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: dayStart) ?? dayStart.addingTimeInterval(3 * 3600)
        let trains = await fetch(leg, opens)
        guard let summary = Self.summarise(trains, dayStart: dayStart, calendar: calendar) else { return nil }
        store(summary, leg: leg, dayStart: dayStart)
        return summary
    }

    /// Pure, so the bucketing and the 03:00 boundary are tested without the network. `dayStart` is the
    /// service day's own `BoardState.serviceDay` value (local midnight of the day that owns it).
    static func summarise(_ trains: [TrainDeparture], dayStart: Date, calendar: Calendar) -> ServiceDaySummary? {
        guard !trains.isEmpty else { return nil }
        let sorted = trains.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        let tonight = sorted.filter { BoardState.serviceDay(of: $0.scheduledDeparture, calendar: calendar) == dayStart }
        guard !tonight.isEmpty else { return nil }
        let tomorrow = sorted.filter { BoardState.serviceDay(of: $0.scheduledDeparture, calendar: calendar) > dayStart }

        // Index 0 is 03:00–04:00; a 00:xx–02:xx train belongs to the tail of the same service day.
        var perHour = [Int](repeating: 0, count: ServiceDaySummary.hourBucketCount)
        for train in tonight {
            let hour = calendar.component(.hour, from: train.scheduledDeparture)
            perHour[(hour - 3 + 24) % 24] += 1
        }

        return ServiceDaySummary(
            lastTonight: tonight.last { !$0.isCancelled }?.scheduledDeparture,
            firstTomorrow: tomorrow.first { !$0.isCancelled }?.scheduledDeparture,
            trainsPerHour: perHour)
    }

    // MARK: App-Group cache, keyed per leg and service day

    private static let keyPrefix = "bigscreen.serviceday."

    private func key(leg: Leg, dayStart: Date) -> String {
        "\(Self.keyPrefix)\(leg.from.id)>\(leg.to.id)@\(Int(dayStart.timeIntervalSince1970))"
    }

    private func cachedSummary(leg: Leg, dayStart: Date) -> ServiceDaySummary? {
        guard let cacheSuite, let defaults = UserDefaults(suiteName: cacheSuite),
              let data = defaults.data(forKey: key(leg: leg, dayStart: dayStart)),
              let stored = try? JSONDecoder().decode(StoredServiceDaySummary.self, from: data) else { return nil }
        return stored.summary
    }

    /// Writing today's entry also drops every other day's, so the group holds one summary per leg at most
    /// rather than one per leg per day forever.
    private func store(_ summary: ServiceDaySummary, leg: Leg, dayStart: Date) {
        guard let cacheSuite, let defaults = UserDefaults(suiteName: cacheSuite),
              let data = try? JSONEncoder().encode(StoredServiceDaySummary(summary)) else { return }
        let today = "@\(Int(dayStart.timeIntervalSince1970))"
        for stale in defaults.dictionaryRepresentation().keys where stale.hasPrefix(Self.keyPrefix) && !stale.hasSuffix(today) {
            defaults.removeObject(forKey: stale)
        }
        defaults.set(data, forKey: key(leg: leg, dayStart: dayStart))
    }

    /// The stored keys, for the cache tests.
    static func cachedKeys(in suite: String) -> [String] {
        (UserDefaults(suiteName: suite)?.dictionaryRepresentation().keys).map { $0.filter { $0.hasPrefix(keyPrefix) } } ?? []
    }
}

/// `ServiceDaySummary` is a frozen contract without `Codable`; this mirror lets a day's summary
/// round-trip through the App Group without touching the contract.
private struct StoredServiceDaySummary: Codable {
    let lastTonight: Date?
    let firstTomorrow: Date?
    let trainsPerHour: [Int]

    init(_ summary: ServiceDaySummary) {
        lastTonight = summary.lastTonight
        firstTomorrow = summary.firstTomorrow
        trainsPerHour = summary.trainsPerHour
    }

    var summary: ServiceDaySummary {
        ServiceDaySummary(lastTonight: lastTonight, firstTomorrow: firstTomorrow, trainsPerHour: trainsPerHour)
    }
}
