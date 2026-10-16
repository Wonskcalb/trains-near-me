#if os(iOS)
import SNCFCore
import SwiftUI

/// The app proper on iPhone and iPad: the radar, the saved journeys, and the settings that used to
/// be the whole app. On macOS the widgets are still the product, so there it stays one window.
struct RootView: View {
    // Read from the same App Group suite the Settings picker writes to, so flipping the appearance
    // there re-tints the whole app at once rather than only the tab that changed it.
    @AppStorage("appearance", store: AppGroupStore.defaults) private var appearance: SharedSettings.Appearance = .system
    @Environment(\.spansFold) private var spansFold
    @Environment(BigScreenModel.self) private var model

    // Selection-based so the screenshot script can open a specific tab; defaults to the first tab,
    // which is the plain behaviour in Release.
    #if DEBUG
    @State private var selection = ScreenshotSupport.initialTab
    #else
    @State private var selection = 0
    #endif

    var body: some View {
        TabView(selection: $selection) {
            nearMeTab
                .tabItem { Label("Near me", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(0)
            journeysTab
                .tabItem { Label("Journeys", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(1)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .tint(.amber)
        .preferredColorScheme(appearance.colorScheme)
        // The line map opens a terminus through `model.open(temporary:)`, which only the iPad/Mac shell
        // routes. In the tabs the journey is pushed over the map instead, and the leg cleared at once so the
        // Journeys tab's boards never read it as their own temporary journey.
        .onChange(of: model.temporaryLeg) { _, leg in
            guard let leg else { return }
            model.temporaryLeg = nil
            nearMe.open(leg)
        }
        #if DEBUG
        .task {
            ScreenshotSupport.seedIfNeeded()
            if let journey = ScreenshotSupport.openJourney { model.journeyPath = [journey] }
        }
        #endif
    }

    // Here rather than in the tab for the same reason as `journeyPath`: folding swaps the tab's container.
    @State private var nearMe = NearMeState()

    @ViewBuilder private var nearMeTab: some View {
        #if DEBUG
        if let station = ScreenshotSupport.station {
            NavigationStack { StationBoardView(station: station) }
        } else {
            nearMeBoards
        }
        #else
        nearMeBoards
        #endif
    }

    @ViewBuilder private var nearMeBoards: some View {
        if spansFold {
            NearMeSplit(nearMe: $nearMe)
        } else {
            NavigationStack(path: $nearMe.path) {
                BoardView(journey: nil, nearMe: $nearMe)
                    .navigationDestination(for: NearMeRoute.self) { NearMeDestination(route: $0, nearMe: $nearMe) }
            }
        }
    }

    // The path lives on the shared model so that folding a Duo, which swaps the split for a plain stack,
    // leaves you on the journey you had open.
    @ViewBuilder private var journeysTab: some View {
        if spansFold {
            JourneysSplit()
        } else {
            @Bindable var model = model
            NavigationStack(path: $model.journeyPath) { JourneysView() }
        }
    }
}
#endif
