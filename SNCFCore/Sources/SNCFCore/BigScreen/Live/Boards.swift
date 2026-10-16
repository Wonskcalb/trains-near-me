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

    private let favorites: @Sendable () -> [JourneyConfiguration]
    private let location: @Sendable () async -> CLLocation?
    private let fetch: Fetch
    private let calendar: Calendar
    /// WidgetKit grants few reloads and the free SNCF tier few requests, so a sidebar of many saved
    /// journeys must not open one socket each: the group never runs more than this many fetches at once.
    private let maxConcurrent: Int

    public init(favorites: @escaping @Sendable () -> [JourneyConfiguration] = { SharedSettings.favorites },
                location: @escaping @Sendable () async -> CLLocation? = { await LocationFix.shared.current() },
                calendar: Calendar = .current,
                maxConcurrent: Int = 4,
                fetch: @escaping Fetch) {
        self.favorites = favorites
        self.location = location
        self.calendar = calendar
        self.maxConcurrent = max(1, maxConcurrent)
        self.fetch = fetch
    }

    /// Production wiring: one direct-journeys request per saved journey, `base_schedule` as always.
    public init(token: String? = SharedSettings.token,
                session: URLSession = .shared,
                favorites: @escaping @Sendable () -> [JourneyConfiguration] = { SharedSettings.favorites },
                location: @escaping @Sendable () async -> CLLocation? = { await LocationFix.shared.current() },
                calendar: Calendar = .current,
                maxConcurrent: Int = 4) {
        let fetch: Fetch = { leg, now in
            try await SNCFClient(token: token, session: session).departures(from: leg.from, to: leg.to, at: now)
        }
        self.init(favorites: favorites, location: location, calendar: calendar, maxConcurrent: maxConcurrent, fetch: fetch)
    }

    public func boards(at now: Date) async -> [JourneyBoard] {
        let journeys = favorites()
        guard !journeys.isEmpty else { return [] }
        // The one location fix is resolved once and shared, not fetched per journey.
        let location = await location()
        let fetch = self.fetch
        let calendar = self.calendar

        return await withTaskGroup(of: (Int, JourneyBoard).self) { group in
            // Indexed so the result keeps the saved order whatever order the fetches finish in.
            var boards = [JourneyBoard?](repeating: nil, count: journeys.count)
            var next = 0

            func start(_ index: Int) {
                let config = journeys[index]
                let leg = JourneySelector.leg(for: config, at: now, location: location, calendar: calendar)
                group.addTask {
                    let state: BoardState
                    do throws(TrainServiceError) {
                        state = BoardState.from(try await fetch(leg, now), now: now, calendar: calendar)
                    } catch {
                        state = .unavailable(error)
                    }
                    return (index, JourneyBoard(journey: config, leg: leg, state: state, fetchedAt: now))
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
