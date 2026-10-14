import CoreLocation
import SNCFCore
import SwiftUI
import WidgetKit

/// On macOS it exists only to store the API token and obtain location permission; the widget is the
/// product there. On iOS it is a real app: the radar and the saved journeys, same data as the widgets.
@main
struct TrainsNearMeApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("Trains near me", id: "settings") {
            SettingsView().frame(width: 420).fixedSize()
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup { RootView() }
        #endif
    }
}

/// Where `@AppStorage` reads the appearance from, resolved the same way `SharedSettings` does: the
/// App Group when one exists, the app's own defaults otherwise. Sharing the suite and the key is what
/// lets the Settings picker and `RootView`'s `.preferredColorScheme` react to each other live.
enum AppGroupStore {
    // UserDefaults is documented thread-safe, so sharing one instance across the app is safe; the
    // marker is only to satisfy Swift 6's blanket ban on non-Sendable static storage.
    nonisolated(unsafe) static let defaults = (Bundle.main.object(forInfoDictionaryKey: "SNCFAppGroup") as? String)
        .flatMap { UserDefaults(suiteName: $0) } ?? .standard
}

struct SettingsView: View {
    @State private var token = SharedSettings.token ?? ""
    @State private var tokenStatus = ""
    @State private var location = LocationFix.shared
    @State private var fix: String?
    #if !os(macOS)
    @AppStorage("appearance", store: AppGroupStore.defaults) private var appearance: SharedSettings.Appearance = .system
    #endif

    var body: some View {
        content
            .task {
                // The widget cannot show a permission prompt itself; without this it silently uses the configured order.
                var askForLocation = location.status == .notDetermined
                #if DEBUG
                // The screenshot script sets the location through simctl, so skip the prompt that
                // would otherwise sit on top of every captured screen.
                if ProcessInfo.processInfo.environment["SCREENSHOT_TAB"] != nil { askForLocation = false }
                #endif
                if askForLocation { location.requestAuthorization() }
                // Taking a fix here is what makes the widget's own attempt cheap: the permission alone
                // leaves the system with nothing cached, and a widget has no time to start from cold.
                await probe()
                WidgetCenter.shared.reloadAllTimelines()
            }
    }

    // macOS keeps the plain settings window — the widget is the product there, so the native Form is
    // the right amount of chrome; only iOS gets the Tableau treatment.
    @ViewBuilder private var content: some View {
        #if os(macOS)
        Form {
            Section("SNCF API token") {
                tokenControls
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
        #else
        iosSettings
        #endif
    }

    // Shared between the two platforms' token sections.
    @ViewBuilder private var tokenControls: some View {
        // Typing a token only reaches the widget through the App Group, which a free Apple
        // account does not get on iOS. There, the compiled-in SNCF_TOKEN is all there is.
        if SharedSettings.isShared {
            SecureField("Token", text: $token)
                .textContentType(.password)
            HStack {
                Button("Save and test") { Task { await save() } }
                    .disabled(token.isEmpty)
                Text(tokenStatus).font(.caption).foregroundStyle(.secondary)
            }
            Link("Get a free token", destination: URL(string: "https://numerique.sncf.com/startup/api/token-developpeur/")!)
                .font(.caption)
        } else {
            Text(SharedSettings.bundled == nil
                 ? "No token in this build. Put SNCF_TOKEN in Config/Local.xcconfig and build again."
                 : "Token taken from the build settings (SNCF_TOKEN). Sign with a real team to type it here instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

#if !os(macOS)
private extension SettingsView {
    var iosSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings").font(.largeTitle.bold()).padding(.horizontal, 4).padding(.bottom, 2)

                SettingsSection("SNCF API TOKEN") { tokenCard }
                SettingsSection("LOCATION") { locationCard }
                SettingsSection("APPEARANCE") { appearanceCard }
                SettingsSection("TICKETS & FULL TIMETABLES") {
                    SettingsCard { SettingsLink("Open SNCF Connect", url: "https://www.sncf-connect.com") }
                }
                SettingsSection("ABOUT") { aboutCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.ground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // The large title is drawn in the content, so the bar stays empty rather than stacking a
        // second "Settings" on top of it.
        .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
    }

    @ViewBuilder var tokenCard: some View {
        SettingsCard {
            if SharedSettings.isShared {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Token")
                        SecureField("", text: $token)
                            .textContentType(.password)
                            .multilineTextAlignment(.trailing)
                            .font(.mono(15, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    HStack {
                        Button("Save and test") { Task { await save() } }
                            .buttonStyle(.borderless)
                            .disabled(token.isEmpty)
                        Spacer()
                        if !tokenStatus.isEmpty {
                            Text(tokenStatus).font(.mono(12)).foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
                Divider().overlay(Color.ink.opacity(0.07))
                SettingsLink("Get a free token", url: "https://numerique.sncf.com/startup/api/token-developpeur/")
            } else {
                Text(SharedSettings.bundled == nil
                     ? "No token in this build. Put SNCF_TOKEN in Config/Local.xcconfig and build again."
                     : "Token taken from the build settings (SNCF_TOKEN). Sign with a real team to type it here instead.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    @ViewBuilder var locationCard: some View {
        SettingsCard {
            HStack {
                Text(summary).foregroundStyle(Color.inkSecondary).font(.subheadline)
                Spacer()
                if location.status == .notDetermined {
                    Button("Allow") { location.requestAuthorization() }.buttonStyle(.borderless)
                } else {
                    Button("Find me") { Task { await probe() } }.buttonStyle(.borderless)
                }
            }
            if let fix {
                Text(fix).font(.footnote).foregroundStyle(Color.inkSecondary)
            }
        }
    }

    @ViewBuilder var appearanceCard: some View {
        SettingsCard {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag(SharedSettings.Appearance.system)
                Text("Light").tag(SharedSettings.Appearance.light)
                Text("Dark").tag(SharedSettings.Appearance.dark)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder var aboutCard: some View {
        SettingsCard {
            HStack {
                Link("Source code", destination: URL(string: "https://github.com/Wonskcalb/trains-near-me")!)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("MIT · v\(version)").font(.mono(13)).foregroundStyle(Color.inkSecondary)
            }
            Divider().overlay(Color.ink.opacity(0.07))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(Color.inkSecondary).padding(.top, 1)
                Text("Trains near me is an independent project, not affiliated with or endorsed by SNCF. Train data © SNCF, via the SNCF open data API, shown as received: times can change. When in doubt, trust the station boards.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The marketing version and build, read rather than hardcoded so a bump in project.yml shows here.
    var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

/// A mono-caps section header over a Tableau card.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.mono(11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            content
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }
}

/// A row that opens an external URL, drawn as a card on its own with the trailing "open" glyph.
private struct SettingsLink: View {
    let title: String
    let url: String

    init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title).foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
            }
        }
    }
}
#endif
