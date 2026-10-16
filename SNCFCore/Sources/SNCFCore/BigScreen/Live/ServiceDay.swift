import Foundation

/// Live `ServiceDayProviding`: one day-long journeys fetch per leg, summarised into the last train
/// tonight, the first tomorrow, how many of tonight's trains run late, and the 24-hour histogram the
/// Lanes minimap draws — then cached in the App Group for the day so the histogram is fetched once.
public struct LiveServiceDay: ServiceDayProviding {
    public typealias Fetch = @Sendable (Leg, Date) async -> [TrainDeparture]

    private let fetch: Fetch
    private let calendar: Calendar
    /// The App-Group suite name, nil without a group (a free Apple account on iOS): the summary is then
    /// recomputed each call instead of cached, which costs only a few extra requests a day. A name rather
    /// than a `UserDefaults` because the provider must stay `Sendable`.
    private let cacheSuite: String?

    public init(calendar: Calendar = .current, cacheSuite: String? = BigScreenAppGroup.suiteName, fetch: @escaping Fetch) {
        self.calendar = calendar
        self.cacheSuite = cacheSuite
        self.fetch = fetch
    }

    /// Production wiring: the whole service day in one `journeys` request; `base_schedule` keeps
    /// cancelled trips in the count, as everywhere else in the app.
    public init(token: String? = SharedSettings.token, session: URLSession = .shared,
                calendar: Calendar = .current, cacheSuite: String? = BigScreenAppGroup.suiteName) {
        self.init(calendar: calendar, cacheSuite: cacheSuite) { leg, at in
            (try? await SNCFClient(token: token, session: session).departures(from: leg.from, to: leg.to, at: at)) ?? []
        }
    }

    public func summary(for leg: Leg, at now: Date) async -> ServiceDaySummary? {
        let dayStart = BoardState.serviceDay(of: now, calendar: calendar)
        if let cached = cachedSummary(leg: leg, dayStart: dayStart) { return cached }
        // Fetch from the 03:00 service-day start so tonight's last train, tomorrow's first and the whole
        // histogram are in one response rather than only the trains after `now`.
        let trains = await fetch(leg, dayStart)
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
            // Running but late; cancellations are the "N DISRUPTED" chip's separate count.
            disruptedCount: tonight.filter { $0.status == .delayed || $0.status == .severelyDelayed }.count,
            trainsPerHour: perHour)
    }

    // MARK: App-Group cache, keyed per leg and service day

    private func key(leg: Leg, dayStart: Date) -> String {
        "bigscreen.serviceday.\(leg.from.id)>\(leg.to.id)@\(Int(dayStart.timeIntervalSince1970))"
    }

    private func cachedSummary(leg: Leg, dayStart: Date) -> ServiceDaySummary? {
        guard let cacheSuite, let defaults = UserDefaults(suiteName: cacheSuite),
              let data = defaults.data(forKey: key(leg: leg, dayStart: dayStart)),
              let stored = try? JSONDecoder().decode(StoredServiceDaySummary.self, from: data) else { return nil }
        return stored.summary
    }

    private func store(_ summary: ServiceDaySummary, leg: Leg, dayStart: Date) {
        guard let cacheSuite, let defaults = UserDefaults(suiteName: cacheSuite),
              let data = try? JSONEncoder().encode(StoredServiceDaySummary(summary)) else { return }
        defaults.set(data, forKey: key(leg: leg, dayStart: dayStart))
    }
}

/// `ServiceDaySummary` is a frozen contract without `Codable`; this mirror lets a day's summary
/// round-trip through the App Group without touching the contract.
private struct StoredServiceDaySummary: Codable {
    let lastTonight: Date?
    let firstTomorrow: Date?
    let disruptedCount: Int
    let trainsPerHour: [Int]

    init(_ summary: ServiceDaySummary) {
        lastTonight = summary.lastTonight
        firstTomorrow = summary.firstTomorrow
        disruptedCount = summary.disruptedCount
        trainsPerHour = summary.trainsPerHour
    }

    var summary: ServiceDaySummary {
        ServiceDaySummary(lastTonight: lastTonight, firstTomorrow: firstTomorrow,
                          disruptedCount: disruptedCount, trainsPerHour: trainsPerHour)
    }
}

/// The App Group suite name, read the same way `SharedSettings` does (Info.plist `SNCFAppGroup`), so the
/// service-day cache lands in the group the app and widgets share. Duplicated rather than reaching into
/// `SharedSettings.defaults`, which is `internal` to that file; a shared accessor there would retire this.
public enum BigScreenAppGroup {
    public static var suiteName: String? {
        Bundle.main.object(forInfoDictionaryKey: "SNCFAppGroup") as? String
    }
}
