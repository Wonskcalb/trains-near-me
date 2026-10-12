import CoreLocation
import Observation
import os

/// One long-lived location client per process, shared by the widget, which needs a fix to pick a
/// station, and by the host app, which takes one at launch: asking for the permission is not asking
/// for a position, so without that the system often has nothing cached.
///
/// It has to be long-lived. A freshly created `CLLocationManager` answers `.notDetermined` until
/// locationd has replied to it, so reading the status off a throwaway manager — as this did — makes
/// an authorized process believe it has no permission. The status is now stored and kept up to date
/// by the delegate, and a fix is attempted whatever it says: the status only names the failure.
@MainActor
@Observable
public final class LocationFix: NSObject, CLLocationManagerDelegate {
    public static let shared = LocationFix()
    /// Read with: log show --last 5m --info --predicate 'subsystem == "trains-near-me"'
    public static let log = Logger(subsystem: "trains-near-me", category: "location")

    @ObservationIgnored private let manager = CLLocationManager()
    public private(set) var status: CLAuthorizationStatus

    private override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// macOS only ever grants "always" to a widget; iOS only ever grants "when in use".
    public var isAuthorized: Bool {
        #if os(macOS)
        return status == .authorizedAlways
        #else
        return [.authorizedAlways, .authorizedWhenInUse].contains(status)
        #endif
    }

    /// Only the host app can ask: an extension cannot show the prompt.
    public func requestAuthorization() { manager.requestWhenInUseAuthorization() }

    /// The system's cached fix while it is fresh enough, otherwise a live one. A widget gets about
    /// 30 s to build its timeline and a cold fix over Wi-Fi regularly needs ten of them, so the wait
    /// is long enough to succeed and short enough to leave time for the SNCF request.
    public func current(cachedWithin: TimeInterval = 15 * 60, timeout: TimeInterval = 12) async -> CLLocation? {
        let process = ProcessInfo.processInfo.processName
        // A refusal is the one status worth trusting early: locationd never reports it by mistake.
        if status == .denied || status == .restricted {
            Self.log.notice("\(process, privacy: .public): refused, status=\(self.status.rawValue, privacy: .public)")
            return nil
        }
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -cachedWithin {
            Self.log.notice("\(process, privacy: .public): cached fix, \(Int(-cached.timestamp.timeIntervalSinceNow), privacy: .public)s old")
            return cached
        }

        let started = Date.now
        let live = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                let updates = CLLocationUpdate.liveUpdates()
                return try? await updates.first { $0.location != nil }?.location
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let fallback = manager.location
        Self.log.notice("""
            \(process, privacy: .public): status=\(self.status.rawValue, privacy: .public) \
            live=\(live != nil, privacy: .public) after \(Int(-started.timeIntervalSinceNow), privacy: .public)s \
            stale=\(fallback != nil, privacy: .public)
            """)
        // Rather an old fix than none: stations are kilometres apart, and the widget shows the time
        // of its last update anyway.
        return live ?? fallback
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let granted = manager.authorizationStatus
        Task { @MainActor in
            status = granted
            Self.log.notice("\(ProcessInfo.processInfo.processName, privacy: .public): status now \(granted.rawValue, privacy: .public)")
        }
    }
}
