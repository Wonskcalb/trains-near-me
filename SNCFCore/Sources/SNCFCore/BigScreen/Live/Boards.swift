import CoreLocation
import Foundation

/// Live `JourneyBoardsProviding`: every saved journey fetched together, each resolved to its current
/// direction, and a failed one degraded to `.unavailable` so one dead journey never drops the rest of
/// the sidebar. The fetch is a seam the tests fill with fixtures; production builds an `SNCFClient` per
/// call, the way the widget and the app already do.
public struct LiveJourneyBoards: JourneyBoardsProviding {
    /// Direct trains for a resolved leg at a time. Typed-throws so a journey's failure carries the
    /// `TrainServiceError` into its `.unavailable` state instead of being swallowed.
    public typealias Fetch = @Sendable (Leg, Date) async throws(TrainServiceError) -> [TrainDeparture]
    /// Handed every raw board as it lands, before it collapses into a `BoardState` (which drops cancelled
    /// rows on a dead day): production re-checks watched trains here.
    public typealias Observe = @Sendable ([TrainDeparture], Leg) async -> Void

    private let favorites: @Sendable () -> [JourneyConfiguration]
    private let location: @Sendable () async -> CLLocation?
    private let fetch: Fetch
    /// The first trains from the next 03:00, asked only when tonight is nearly done. Its own seam because
    /// production asks it by count, not by window: the morning only needs its first few.
    private let fetchTomorrow: Fetch
    private let observe: Observe
    private let calendar: Calendar
    /// The free SNCF tier is 5 000 requests a day, so a sidebar of many saved journeys must not open one
    /// socket each: the group never runs more than this many fetches at once.
    private let maxConcurrent: Int
    /// The sidebar, the detail screen and the menu bar all ask for every board on the same appear or ⌘R;
    /// within this window they share one round of requests instead of each paying for it.
    private let memoLifetime: TimeInterval
    private let memo = BoardsMemo()
    private let mornings = MorningMemo()

    public init(favorites: @escaping @Sendable () -> [JourneyConfiguration] = { SharedSettings.favorites },
                location: @escaping @Sendable () async -> CLLocation? = { await LocationFix.shared.current() },
                calendar: Calendar = SNCFTime.calendar,
                maxConcurrent: Int = 4,
                memoLifetime: TimeInterval = 60,
                observe: @escaping Observe = { _, _ in },
                tomorrow: @escaping Fetch = { _, _ in [] },
                fetch: @escaping Fetch) {
        self.favorites = favorites
        self.location = location
        self.calendar = calendar
        self.maxConcurrent = max(1, maxConcurrent)
        self.memoLifetime = memoLifetime
        self.observe = observe
        self.fetchTomorrow = tomorrow
        self.fetch = fetch
    }

    /// Production wiring: one direct-journeys request per saved journey, `base_schedule` as always. The
    /// token is read per fetch so one typed in Settings after launch is used straight away, and every
    /// raw board goes past the shared `TrainWatcher` — the Mac and iPad have no other foreground check.
    public init(token: @escaping @Sendable () -> String? = { SharedSettings.token },
                session: URLSession = .shared,
                favorites: @escaping @Sendable () -> [JourneyConfiguration] = { SharedSettings.favorites },
                location: @escaping @Sendable () async -> CLLocation? = { await LocationFix.shared.current() },
                calendar: Calendar = SNCFTime.calendar,
                maxConcurrent: Int = 4) {
        let fetch: Fetch = { leg, now in
            // The rest of the service day (to the next 03:00, at least Lanes' 4 h window) in the same single
            // request: `min_nb_journeys` alone stops at a dozen trains, about 2 h on a busy line, so Lanes
            // drew empty track where its service-day minimap showed trains.
            try await SNCFClient(token: token(), session: session)
                .departures(from: leg.from, to: leg.to, at: now, within: BoardState.restOfServiceDay(after: now, atLeast: 4 * 3600, calendar: calendar))
        }
        // A count, not a window: only the morning's first few trains are drawn after the split.
        let tomorrow: Fetch = { leg, opens in
            try await SNCFClient(token: token(), session: session)
                .departures(from: leg.from, to: leg.to, at: opens, count: Self.tomorrowCount)
        }
        self.init(favorites: favorites, location: location, calendar: calendar, maxConcurrent: maxConcurrent,
                  observe: { trains, leg in await TrainWatcher.shared.reevaluate(against: trains, to: leg) },
                  tomorrow: tomorrow, fetch: fetch)
    }

    /// How many of tomorrow's first trains a late board carries: about the first two hours of a busy line.
    static let tomorrowCount = 6

    public func boards(at now: Date) async -> [JourneyBoard] {
        let journeys = favorites()
        guard !journeys.isEmpty else { return [] }
        return await memo.value(for: journeys, at: now, lifetime: memoLifetime) { await fetchAll(journeys, at: now) }
    }

    public func invalidate() async { await memo.clear() }

    /// The first trains of the next service day on one leg, for a screen that shows the morning before
    /// tonight is nearly done (Lanes' TOMORROW AM). One request per leg and morning: the timetable for a
    /// morning does not change through the evening, and its delays are not known yet anyway.
    public func morning(for leg: Leg, at now: Date) async -> [TrainDeparture] {
        let opens = BoardState.nextServiceDayStart(after: now, calendar: calendar)
        let fetchTomorrow = self.fetchTomorrow
        let calendar = self.calendar
        return await mornings.value("\(leg.from.id)>\(leg.to.id)@\(Int(opens.timeIntervalSince1970))") {
            guard let trains = try? await fetchTomorrow(leg, opens) else { return nil }
            let day = BoardState.serviceDay(of: opens, calendar: calendar)
            return trains.filter { BoardState.serviceDay(of: $0.scheduledDeparture, calendar: calendar) == day }
                .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        }
    }

    public func board(for leg: Leg, at now: Date) async -> JourneyBoard {
        await Self.board(JourneyConfiguration(stationA: leg.from, stationB: leg.to), leg: leg, at: now,
                         fetch: fetch, tomorrow: fetchTomorrow, observe: observe, calendar: calendar)
    }

    private static func board(_ config: JourneyConfiguration, leg: Leg, at now: Date, fetch: Fetch, tomorrow: Fetch,
                              observe: Observe, calendar: Calendar) async -> JourneyBoard {
        let state: BoardState
        do throws(TrainServiceError) {
            let trains = try await fetch(leg, now)
            await observe(trains, leg)
            state = BoardState.from(trains, now: now, calendar: calendar)
        } catch {
            state = .unavailable(error)
        }
        guard state.tonightIsNearlyDone(at: now) else {
            return JourneyBoard(journey: config, leg: leg, state: state, fetchedAt: now)
        }
        // The extra request, one per journey and only late: the board memo keeps a round of them to one.
        // A failure here only loses the morning; tonight's board stands.
        let opens = BoardState.nextServiceDayStart(after: now, calendar: calendar)
        let day = BoardState.serviceDay(of: opens, calendar: calendar)
        let morning = ((try? await tomorrow(leg, opens)) ?? [])
            .filter { BoardState.serviceDay(of: $0.scheduledDeparture, calendar: calendar) == day }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        // After the last train the window may hold nothing runnable (only a cancelled first train of
        // tomorrow): the morning just fetched names the first one, as the station board does.
        var named = state
        if state == .noTrains, let first = morning.first(where: { !$0.isCancelled }) {
            named = .endOfService(firstTrain: first.scheduledDeparture)
        }
        return JourneyBoard(journey: config, leg: leg, state: named, fetchedAt: now,
                            tomorrow: Array(morning.prefix(tomorrowCount)))
    }

    private func fetchAll(_ journeys: [JourneyConfiguration], at now: Date) async -> [JourneyBoard] {
        // The one location fix is resolved once and shared, not fetched per journey.
        let location = await location()
        let fetch = self.fetch
        let tomorrow = self.fetchTomorrow
        let observe = self.observe
        let calendar = self.calendar

        return await withTaskGroup(of: (Int, JourneyBoard).self) { group in
            // Indexed so the result keeps the saved order whatever order the fetches finish in.
            var boards = [JourneyBoard?](repeating: nil, count: journeys.count)
            var next = 0

            func start(_ index: Int) {
                let config = journeys[index]
                let leg = JourneySelector.leg(for: config, at: now, location: location, calendar: calendar)
                group.addTask {
                    (index, await Self.board(config, leg: leg, at: now, fetch: fetch, tomorrow: tomorrow,
                                             observe: observe, calendar: calendar))
                }
            }

            let window = min(maxConcurrent, journeys.count)
            while next < window { start(next); next += 1 }
            for await (index, board) in group {
                boards[index] = board
                if next < journeys.count { start(next); next += 1 }
            }
            return boards.compactMap { $0 }
        }
    }
}

extension BoardState {
    /// Seconds from `now` to the next 03:00, when the service day closes, floored at `atLeast` so a
    /// window asked at 02:30 still reaches past the night. Set by wall-clock hour, so DST nights hold.
    static func restOfServiceDay(after now: Date, atLeast minimum: TimeInterval, calendar: Calendar) -> TimeInterval {
        max(nextServiceDayStart(after: now, calendar: calendar).timeIntervalSince(now), minimum)
    }

    /// The 03:00 that closes `now`'s service day and opens the next one.
    public static func nextServiceDayStart(after now: Date, calendar: Calendar = SNCFTime.calendar) -> Date {
        let dayStart = serviceDay(of: now, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: dayStart)
            .flatMap { calendar.date(bySettingHour: 3, minute: 0, second: 0, of: $0) } ?? now.addingTimeInterval(24 * 3600)
    }
}

public extension BoardState {
    /// Whether tonight is close enough to over that a big screen should carry on into tomorrow: fewer
    /// than three trains still to run (cancelled ones don't count), or none left at all. After about
    /// 23:00 the rest-of-service-day window holds no morning trains, so this is what pays for the
    /// extra request. An unavailable board says nothing about tonight, so it never asks.
    func tonightIsNearlyDone(at now: Date) -> Bool {
        switch self {
        case .endOfService, .noService, .noTrains: true
        case .unavailable: false
        case .departures(let trains): trains.filter { !$0.isCancelled && $0.expectedDeparture > now }.count < 3
        }
    }

    /// Whether `date` falls in a later 03:00 service day than `now`, so the 00:15 train is still tonight.
    static func isLaterServiceDay(_ date: Date, than now: Date, calendar: Calendar = SNCFTime.calendar) -> Bool {
        serviceDay(of: date, calendar: calendar) > serviceDay(of: now, calendar: calendar)
    }
}

/// The last round of boards, held as its task so callers arriving while it is still in flight wait for
/// it rather than starting their own. Keyed on the saved journeys too, so an edit is never answered with
/// the old list.
actor BoardsMemo {
    private var entry: (journeys: [JourneyConfiguration], at: Date, task: Task<[JourneyBoard], Never>)?

    func value(for journeys: [JourneyConfiguration], at now: Date, lifetime: TimeInterval,
               compute: @escaping @Sendable () async -> [JourneyBoard]) async -> [JourneyBoard] {
        if let entry, entry.journeys == journeys, abs(now.timeIntervalSince(entry.at)) < lifetime {
            return await entry.task.value
        }
        let task = Task { await compute() }
        entry = (journeys, now, task)
        return await task.value
    }

    func clear() { entry = nil }
}

/// Each leg's next morning, held as its task so a second ask while the first is in flight shares it. A
/// failed fetch (nil) is dropped once it lands, so the next ask tries again. Keyed by leg and morning, so
/// yesterday's entries are simply never asked for again (a handful of small arrays for the session).
actor MorningMemo {
    private var tasks: [String: Task<[TrainDeparture]?, Never>] = [:]

    func value(_ key: String, compute: @escaping @Sendable () async -> [TrainDeparture]?) async -> [TrainDeparture] {
        let task = tasks[key] ?? Task { await compute() }
        tasks[key] = task
        guard let trains = await task.value else {
            tasks[key] = nil
            return []
        }
        return trains
    }
}
