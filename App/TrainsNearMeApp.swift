import CoreLocation
import SNCFCore
import SwiftUI
import WidgetKit

/// Exists only to store the API token and obtain location permission; the widget is the product.
@main
struct TrainsNearMeApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("Trains near me", id: "settings") {
            SettingsView().frame(width: 420).fixedSize()
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup { SettingsView() }
        #endif
    }
}

struct SettingsView: View {
    @State private var token = SharedSettings.token ?? ""
    @State private var tokenStatus = ""
    @State private var location = LocationFix.shared
    @State private var fix: String?

    var body: some View {
        Form {
            Section("SNCF API token") {
                #if os(macOS)
                SecureField("Token", text: $token)
                HStack {
                    Button("Save and test") { Task { await save() } }
                        .disabled(token.isEmpty)
                    Text(tokenStatus).font(.caption).foregroundStyle(.secondary)
                }
                Link("Get a free token", destination: URL(string: "https://numerique.sncf.com/startup/api/token-developpeur/")!)
                    .font(.caption)
                #else
                // A free Apple account cannot share an App Group on iOS, so the token is compiled in instead.
                Text(SharedSettings.bundled == nil
                     ? "No token in this build. Put SNCF_TOKEN in Config/Local.xcconfig and build again."
                     : "Token taken from the build settings (SNCF_TOKEN).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            Section("Location (needed by Radar, optional for Trip)") {
                HStack {
                    Text(summary).foregroundStyle(.secondary)
                    Spacer()
                    if location.status == .notDetermined {
                        Button("Allow") { location.requestAuthorization() }
                    } else {
                        Button("Find me") { Task { await probe() } }
                    }
                }
                if let fix {
                    Text(fix).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // The widget cannot show a permission prompt itself; without this it silently uses the configured order.
            if location.status == .notDetermined { location.requestAuthorization() }
            // Taking a fix here is what makes the widget's own attempt cheap: the permission alone
            // leaves the system with nothing cached, and a widget has no time to start from cold.
            await probe()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var summary: String {
        switch location.status {
        case .authorizedAlways: "Allowed"
        #if !os(macOS)
        case .authorizedWhenInUse: "Allowed"
        #endif
        case .denied, .restricted: "Denied — enable Location Services for Trains near me in Settings"
        default: "Not requested"
        }
    }

    /// Shows what the system really hands over, so a silent failure stays visible.
    private func probe() async {
        fix = "Looking for your position…"
        guard let location = await LocationFix.shared.current() else {
            fix = "No position: the system returned none. Check that Location Services is on."
            return
        }
        let minutes = Int(-location.timestamp.timeIntervalSinceNow / 60)
        fix = String(format: "Found: %.3f, %.3f (%@) — that is what Radar sends to SNCF.",
                     location.coordinate.latitude, location.coordinate.longitude,
                     minutes < 1 ? "just now" : "\(minutes) min ago")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func save() async {
        SharedSettings.token = token
        tokenStatus = "Testing…"
        do {
            _ = try await SNCFClient(token: token).searchStations("Grenoble")
            tokenStatus = "Token works."
        } catch {
            tokenStatus = error == .unauthorized ? "Token rejected." : "Saved, but the SNCF API could not be reached."
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
