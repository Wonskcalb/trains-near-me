import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// What an alert reports, so the scheduling side can word the notification. Kept out of the decision:
/// `TrainWatcher.alert(from:to:)` works this out with no notification framework in sight, which is the
/// only part worth a test.
public enum WatchAlert: Equatable, Sendable {
    /// The train crossed into a different band (on time ↔ delayed ↔ severely delayed); the new one carried.
    case bandChanged(to: DepartureStatus)
    /// The train was cancelled.
    case cancelled
}

/// Live `TrainWatching`. The watched set and each train's last-seen status live in the App Group (so a
/// watch survives relaunch, mirroring `SharedSettings`); watching schedules a local reminder before the
/// train leaves and, on every refresh, an alert whenever a watched train changes delay band or is
/// cancelled.
///
/// Re-evaluation (`reevaluate(against:…)`) runs from the app and from iOS background app refresh — never
/// by reloading widgets. The WidgetKit reload budget (≈40–70/day) is for drawing, not for this; this type
/// never imports WidgetKit. Every authorization and scheduling call is gated by `schedulesNotifications`
/// (off in tests) so `UNUserNotificationCenter.current()`, which needs a real app bundle, is only reached
/// on device.
public actor TrainWatcher: TrainWatching {
    private let defaults: UserDefaults?
    private let schedulesNotifications: Bool
    private let eta = ETAComposer()
    /// A reminder lands this long before the train is expected to leave.
    /// ponytail: one sensible lead; make it a setting if anyone ever asks.
    private let reminderLead: TimeInterval = 15 * 60

    private var watchedSet: Set<TrainIdentity>
    /// The status each watched train last showed, to spot a band change on the next refresh. The raw
    /// delay/cancellation is stored rather than `DepartureStatus`, which is not `Codable`. Internal, not
    /// private, so tests can confirm re-evaluation records and persists it.
    var lastSeen: [TrainIdentity: WatchedStatus]
    private var didRequestAuthorization = false

    /// The App Group suite, shaped per platform in Info.plist, mirroring `SharedSettings`. nil — no group,
    /// a free Apple account on iOS — degrades to in-memory only: watching still works for the session.
    public static var appGroupSuiteName: String? {
        Bundle.main.object(forInfoDictionaryKey: "SNCFAppGroup") as? String
    }

    public init(suiteName: String? = TrainWatcher.appGroupSuiteName, schedulesNotifications: Bool = true) {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) }
        self.defaults = defaults
        self.schedulesNotifications = schedulesNotifications
        self.watchedSet = Self.decode(Set<TrainIdentity>.self, from: defaults, key: Keys.watched) ?? []
        self.lastSeen = Self.decode([TrainIdentity: WatchedStatus].self, from: defaults, key: Keys.lastSeen) ?? [:]
    }

    // MARK: TrainWatching

    public func isWatched(_ identity: TrainIdentity) -> Bool { watchedSet.contains(identity) }
    public func watched() -> Set<TrainIdentity> { watchedSet }

    public func watch(_ identity: TrainIdentity) async {
        watchedSet.insert(identity)
        save()
        await ensureAuthorization()
    }

    public func unwatch(_ identity: TrainIdentity) async {
        watchedSet.remove(identity)
        lastSeen[identity] = nil
        save()
        cancelReminder(identity)
    }

    // MARK: Watching a concrete train — what the inspector calls, holding the TrainDeparture and its leg

    /// Watch a train the UI already has in hand: persists the identity, records its status so the first
    /// band change is measured from now, and schedules the departure reminder. A row with nothing stable
    /// to watch (no vehicle-journey id, no number) is ignored.
    public func watch(_ train: TrainDeparture, to leg: Leg? = nil, calendar: Calendar = .current) async {
        guard let identity = TrainIdentity(train, calendar: calendar) else { return }
        watchedSet.insert(identity)
        lastSeen[identity] = WatchedStatus(train)
        save()
        await ensureAuthorization()
        await scheduleReminder(for: train, identity: identity, to: leg)
    }

    // MARK: Re-evaluation — every board refresh / iOS background refresh, never a widget reload

    /// Compare a freshly fetched board against what each watched train last looked like, fire an alert on
    /// a band change or cancellation, and move the reminder to the new expected time. Pass the raw
    /// departures (a `.departures` board, or the array behind one): `base_schedule` keeps cancelled rows,
    /// so cancellations are visible here. `leg` only names the destination in the notification text.
    public func reevaluate(against trains: [TrainDeparture], to leg: Leg? = nil, calendar: Calendar = .current) async {
        for train in trains {
            guard let identity = TrainIdentity(train, calendar: calendar), watchedSet.contains(identity) else { continue }
            if let alert = Self.alert(from: lastSeen[identity]?.status, to: train.status) {
                await fire(alert, for: train, to: leg)
            }
            lastSeen[identity] = WatchedStatus(train)
            await scheduleReminder(for: train, identity: identity, to: leg)
        }
        save()
    }

    // MARK: The pure decision — the tested part

    /// Whether a status change is worth an alert. The rule is keyed on the *band*, not the minute count,
    /// so a train slipping from +12 to +16 (both "delayed") stays quiet — only crossing into a new band
    /// (on time ↔ delayed ↔ severely delayed), or being cancelled, pings the rider. A first sighting
    /// (`previous == nil`) only alerts if the train is already cancelled; otherwise it is just recorded.
    /// Cancelled → cancelled never re-fires.
    public static func alert(from previous: DepartureStatus?, to current: DepartureStatus) -> WatchAlert? {
        if current == previous { return nil }
        if current == .cancelled { return .cancelled }
        guard previous != nil else { return nil }   // first sighting, not cancelled: record only
        return .bandChanged(to: current)
    }

    // MARK: Persistence

    private enum Keys {
        static let watched = "bigscreen.watch.identities"
        static let lastSeen = "bigscreen.watch.lastSeen"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults?, key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(watchedSet) { defaults.set(data, forKey: Keys.watched) }
        if let data = try? JSONEncoder().encode(lastSeen) { defaults.set(data, forKey: Keys.lastSeen) }
    }

    // MARK: Notifications (gated, so tests and macOS never reach UNUserNotificationCenter.current())

    /// Permission is asked on first watch, not at launch, so the prompt lands when the rider opts in.
    private func ensureAuthorization() async {
        guard schedulesNotifications, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        #if canImport(UserNotifications)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        #endif
    }

    private func scheduleReminder(for train: TrainDeparture, identity: TrainIdentity, to leg: Leg?) async {
        guard schedulesNotifications else { return }
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID(identity)])
        let interval = train.expectedDeparture.addingTimeInterval(-reminderLead).timeIntervalSinceNow
        guard !train.isCancelled, interval > 0 else { return }   // nothing to remind for a past lead or a cancellation
        let content = UNMutableNotificationContent()
        content.title = "Leaving soon"
        content.body = body(for: train, to: leg)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: reminderID(identity), content: content, trigger: trigger))
        #endif
    }

    private func cancelReminder(_ identity: TrainIdentity) {
        guard schedulesNotifications else { return }
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID(identity)])
        #endif
    }

    private func fire(_ alert: WatchAlert, for train: TrainDeparture, to leg: Leg?) async {
        guard schedulesNotifications else { return }
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = alert == .cancelled ? "Train cancelled" : "Delay update"
        content.body = body(for: train, to: leg)
        content.sound = .default
        // A nil trigger delivers at once — this runs from a refresh, so "now" is the right moment.
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "bigscreen.watch.alert.\(UUID().uuidString)", content: content, trigger: nil))
        #endif
    }

    /// Reuse the share line for notification bodies when the leg is known (it reads well either way);
    /// fall back to the time and number on a station-board re-evaluation, which carries no leg.
    private func body(for train: TrainDeparture, to leg: Leg?) -> String {
        if let leg { return eta.shareText(for: train, leg: leg) }
        let who = [train.mode, train.trainNumber].compactMap { $0 }.joined(separator: " ")
        return who.isEmpty ? "Your watched train" : who
    }

    private func reminderID(_ identity: TrainIdentity) -> String { "bigscreen.watch.reminder.\(identity.notificationKey)" }
}

/// What a watched train looked like last time. Stored instead of `DepartureStatus` because that enum is
/// not `Codable`; `status` rebuilds the band through the same rule the rest of the app uses, so last-seen
/// round-trips exactly (including the `.unknown` case, where SNCF signals a disruption with no figure).
struct WatchedStatus: Codable, Equatable, Sendable {
    let delayMinutes: Int?
    let isCancelled: Bool

    init(_ train: TrainDeparture) {
        delayMinutes = train.delayMinutes
        isCancelled = train.isCancelled
    }

    var status: DepartureStatus { .from(delayMinutes: delayMinutes, cancelled: isCancelled) }
}

extension TrainIdentity {
    /// A stable string for a notification request identifier, so a reminder can be found and replaced
    /// when the train's expected time shifts.
    var notificationKey: String {
        switch self {
        case .vehicleJourney(let id): "vj.\(id)"
        case .numbered(let number, let day): "num.\(number).\(Int(day.timeIntervalSince1970))"
        }
    }
}
