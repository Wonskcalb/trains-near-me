import CoreLocation
import SNCFCore
import WidgetKit

/// What a widget shows: one configured journey, or everything leaving the station nearest to you.
enum Board: Equatable {
    case trip(Leg)
    /// nil while no station is known yet (no location, or none around).
    case radar(Station?)
}

struct DeparturesEntry: TimelineEntry {
    let date: Date
    let fetchedAt: Date
    /// nil until the trip widget has both of its stations.
    let board: Board?
    let state: BoardState
    /// Set when nearest-station mode is on but the configured order had to be used instead.
    var locationIssue: LocationIssue? = nil

    var isStale: Bool { RefreshPlanner.isStale(fetchedAt: fetchedAt, at: date) }

    /// Trains still to come. Kept past `staleAfter`: a schedule fetched an hour ago still says
    /// when the next train leaves, and the header marks how old the delays are.
    var upcoming: [TrainDeparture] {
        guard case .departures(let trains) = state else { return [] }
        return trains.filter { $0.expectedDeparture > date }
    }

    /// One short line for the Lock Screen, where there is no room for a title and a detail.
    var shortStatus: String {
        switch state {
        case .departures: return isStale ? "Out of date" : "No more trains"
        case .noTrains: return "No trains"
        case .endOfService: return "End of service"
        case .noService: return "All cancelled"
        case .unavailable(let error): return error.localizedDescription
        }
    }
}

enum LocationIssue: Error {
    case notAuthorized, unavailable
}

struct TripProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry { .tripPreview }

    func snapshot(for configuration: JourneyIntent, in context: Context) async -> DeparturesEntry {
        context.isPreview ? .tripPreview : await fetch(configuration, now: .now)
    }

    func timeline(for configuration: JourneyIntent, in context: Context) async -> Timeline<DeparturesEntry> {
        let now = Date.now
        let entry = await fetch(configuration, now: now)
        guard entry.board != nil else { return Timeline(entries: [entry], policy: .never) }

        var flip: Date?
        if let journey = configuration.journey, journey.direction == .automatic, !journey.nearestStationAsDeparture {
            flip = Calendar.current.nextDate(after: now, matching: DateComponents(hour: journey.switchMinute / 60, minute: journey.switchMinute % 60), matchingPolicy: .nextTime)
        }
        return makeTimeline(entry, now: now, flip: flip)
    }

    private func fetch(_ configuration: JourneyIntent, now: Date) async -> DeparturesEntry {
        guard let journey = configuration.journey else {
            return DeparturesEntry(date: now, fetchedAt: now, board: nil, state: .noTrains)
        }
        var location: CLLocation?
        var issue: LocationIssue?
        if journey.nearestStationAsDeparture {
            switch await currentLocation() {
            case .success(let fix): location = fix
            case .failure(let failure): issue = failure
            }
        }
        let leg = JourneySelector.leg(for: journey, at: now, location: location)
        let state: BoardState
        do {
            state = .from(try await SNCFClient(token: SharedSettings.token).departures(from: leg.from, to: leg.to, at: now), now: now)
        } catch {
            state = .unavailable(error)
        }
        return DeparturesEntry(date: now, fetchedAt: now, board: .trip(leg), state: state, locationIssue: issue)
    }
}

struct RadarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry { .radarPreview }

    func snapshot(for configuration: RadarIntent, in context: Context) async -> DeparturesEntry {
        context.isPreview ? .radarPreview : await fetch(now: .now)
    }

    func timeline(for configuration: RadarIntent, in context: Context) async -> Timeline<DeparturesEntry> {
        let now = Date.now
        return makeTimeline(await fetch(now: now), now: now, flip: nil)
    }

    /// Two requests: the station around you, then its board. Both only on reload, so about
    /// twice the trip widget's budget, still far below the free tier's 5 000 requests a day.
    private func fetch(now: Date) async -> DeparturesEntry {
        func entry(_ station: Station?, _ state: BoardState) -> DeparturesEntry {
            DeparturesEntry(date: now, fetchedAt: now, board: .radar(station), state: state)
        }
        guard case .success(let location) = await currentLocation() else {
            return entry(nil, .unavailable(.noLocation))
        }
        let client = SNCFClient(token: SharedSettings.token)
        do {
            guard let station = try await client.nearestStation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) else {
                return entry(nil, .unavailable(.noStationNearby))
            }
            return entry(station, .from(try await client.departures(from: station, at: now), now: now))
        } catch {
            return entry(nil, .unavailable(error))
        }
    }
}

/// One entry now, one just after each train leaves, one when the data goes stale.
func makeTimeline(_ entry: DeparturesEntry, now: Date, flip: Date?) -> Timeline<DeparturesEntry> {
    var entries = [entry]
    if case .departures(let trains) = entry.state {
        entries = RefreshPlanner.entryDates(fetchedAt: now, departures: trains).map {
            DeparturesEntry(date: $0, fetchedAt: now, board: entry.board, state: entry.state, locationIssue: entry.locationIssue)
        }
    }
    var reload = RefreshPlanner.nextRefresh(fetchedAt: now, state: entry.state)
    if let flip { reload = min(reload, flip) }
    return Timeline(entries: entries, policy: .after(reload))
}

/// One coarse fix, used to pick a station; only a position rounded to ~100 m ever reaches SNCF.
func currentLocation() async -> Result<CLLocation, LocationIssue> {
    let manager = CLLocationManager()
    // macOS only ever reports "always" for a widget; iOS only ever reports "when in use".
    #if os(macOS)
    let allowed: [CLAuthorizationStatus] = [.authorizedAlways]
    #else
    let allowed: [CLAuthorizationStatus] = [.authorizedAlways, .authorizedWhenInUse]
    #endif
    guard allowed.contains(manager.authorizationStatus) else { return .failure(.notAuthorized) }
    if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -15 * 60 { return .success(cached) }
    let fix = await withTaskGroup(of: CLLocation?.self) { group in
        group.addTask {
            let updates = CLLocationUpdate.liveUpdates()
            return try? await updates.first { $0.location != nil }?.location
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
    return fix.map { .success($0) } ?? .failure(.unavailable)
}

extension DeparturesEntry {
    static var tripPreview: DeparturesEntry { preview(.trip(Leg(from: previewStations.0, to: previewStations.1))) }
    static var radarPreview: DeparturesEntry { preview(.radar(previewStations.0)) }

    static let previewStations = (Station(id: "a", name: "Grenoble", latitude: 0, longitude: 0),
                                  Station(id: "b", name: "Voiron", latitude: 0, longitude: 0))

    static func preview(_ board: Board) -> DeparturesEntry {
        let now = Date.now
        let directions = ["Valence Ville", "Lyon Part-Dieu", "Chambéry", "Annecy"]
        let trains = zip([(8, 0, 25), (38, 12, 24), (68, 23, 26), (98, 0, 25)], directions).map { plan, direction in
            let (offset, delay, duration) = plan
            let departure = now.addingTimeInterval(TimeInterval(offset * 60))
            if case .radar = board {
                return TrainDeparture(scheduledDeparture: departure, direction: direction, delayMinutes: delay, isCancelled: false, trainNumber: nil)
            }
            return TrainDeparture(scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(TimeInterval(duration * 60)),
                                  delayMinutes: delay, isCancelled: false, trainNumber: nil)
        }
        return DeparturesEntry(date: now, fetchedAt: now, board: board, state: .departures(trains))
    }
}
