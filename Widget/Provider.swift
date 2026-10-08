import CoreLocation
import SNCFCore
import WidgetKit

struct DeparturesEntry: TimelineEntry {
    let date: Date
    let fetchedAt: Date
    /// nil until both stations are configured.
    let leg: Leg?
    let state: BoardState
    /// Set when nearest-station mode is on but the configured order had to be used instead.
    var locationIssue: LocationIssue? = nil
}

enum LocationIssue: Error {
    case notAuthorized, unavailable
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry { .preview }

    func snapshot(for configuration: JourneyIntent, in context: Context) async -> DeparturesEntry {
        context.isPreview ? .preview : await fetch(configuration, now: .now)
    }

    func timeline(for configuration: JourneyIntent, in context: Context) async -> Timeline<DeparturesEntry> {
        let now = Date.now
        let entry = await fetch(configuration, now: now)
        guard entry.leg != nil else { return Timeline(entries: [entry], policy: .never) }

        var entries = [entry]
        if case .departures(let trains) = entry.state {
            entries = RefreshPlanner.entryDates(fetchedAt: now, departures: trains).map {
                DeparturesEntry(date: $0, fetchedAt: now, leg: entry.leg, state: entry.state, locationIssue: entry.locationIssue)
            }
        }
        var reload = RefreshPlanner.nextRefresh(fetchedAt: now, state: entry.state)
        if let journey = configuration.journey, journey.direction == .automatic, !journey.nearestStationAsDeparture,
           let flip = Calendar.current.nextDate(after: now, matching: DateComponents(hour: journey.switchMinute / 60, minute: journey.switchMinute % 60), matchingPolicy: .nextTime) {
            reload = min(reload, flip)
        }
        return Timeline(entries: entries, policy: .after(reload))
    }

    private func fetch(_ configuration: JourneyIntent, now: Date) async -> DeparturesEntry {
        guard let journey = configuration.journey else {
            return DeparturesEntry(date: now, fetchedAt: now, leg: nil, state: .noTrains)
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
            state = .from(try await SNCFClient(token: SharedSettings.token).departures(from: leg.from, to: leg.to, at: now))
        } catch {
            state = .unavailable(error)
        }
        return DeparturesEntry(date: now, fetchedAt: now, leg: leg, state: state, locationIssue: issue)
    }

    /// One coarse fix, only to compare distances to the two stations; never leaves the Mac.
    private func currentLocation() async -> Result<CLLocation, LocationIssue> {
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedAlways else { return .failure(.notAuthorized) }
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
}

extension DeparturesEntry {
    static var preview: DeparturesEntry {
        let now = Date.now
        let a = Station(id: "a", name: "Grenoble", latitude: 0, longitude: 0)
        let b = Station(id: "b", name: "Voiron", latitude: 0, longitude: 0)
        let trains = [(8, 0, 25), (38, 12, 24), (68, 23, 26), (98, 0, 25)].map { offset, delay, duration in
            let departure = now.addingTimeInterval(TimeInterval(offset * 60))
            return TrainDeparture(scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(TimeInterval(duration * 60)),
                                  delayMinutes: delay, isCancelled: false, trainNumber: nil)
        }
        return DeparturesEntry(date: now, fetchedAt: now, leg: Leg(from: a, to: b), state: .departures(trains))
    }
}
