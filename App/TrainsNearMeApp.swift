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
    @State private var location = LocationPermission()

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
            Section("Location (optional, for “Depart from nearest station”)") {
                HStack {
                    Text(location.description).foregroundStyle(.secondary)
                    Spacer()
                    if location.status == .notDetermined {
                        Button("Allow") { location.request() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The widget cannot show a permission prompt itself; without this it silently uses the configured order.
            if location.status == .notDetermined { location.request() }
            // The system only hands the widget a location fix while the app is active, so refresh it now.
            WidgetCenter.shared.reloadAllTimelines()
        }
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

@Observable
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        WidgetCenter.shared.reloadAllTimelines()
    }

    override var description: String {
        switch status {
        case .authorizedAlways: "Allowed"
        #if !os(macOS)
        case .authorizedWhenInUse: "Allowed"
        #endif
        case .denied, .restricted: "Denied — enable Location Services for Trains near me in Settings"
        default: "Not requested"
        }
    }
}
