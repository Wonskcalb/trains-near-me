#if os(iOS)
import SNCFCore
import SwiftUI

/// The app proper on iPhone and iPad: the radar, the saved journeys, and the settings that used to
/// be the whole app. On macOS the widgets are still the product, so there it stays one window.
struct RootView: View {
    // Read from the same App Group suite the Settings picker writes to, so flipping the appearance
    // there re-tints the whole app at once rather than only the tab that changed it.
    @AppStorage("appearance", store: AppGroupStore.defaults) private var appearance: SharedSettings.Appearance = .system

    // Selection-based so the screenshot script can open a specific tab; defaults to the first tab,
    // which is the plain behaviour in Release.
    #if DEBUG
    @State private var selection = ScreenshotSupport.initialTab
    #else
    @State private var selection = 0
    #endif

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { BoardView(journey: nil) }
                .tabItem { Label("Near me", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(0)
            NavigationStack { JourneysView() }
                .tabItem { Label("Journeys", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(1)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .tint(.amber)
        .preferredColorScheme(appearance.colorScheme)
        #if DEBUG
        .task { ScreenshotSupport.seedIfNeeded() }
        #endif
    }
}
#endif
