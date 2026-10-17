#if os(iOS)
import SNCFCore
import SwiftUI

/// The app proper on iPhone and the iPhone Duo: the radar, the saved journeys, the wall and the settings
/// that used to be the whole app. Each big-screen view is reachable from a tab or a tab's List | … switch,
/// never only from a toolbar icon. On macOS the widgets are still the product, so there it stays one window.
struct RootView: View {
    /// The Duo stood half open like a desk clock, read from the fold's region by `BigScreenRoot`.
    var isTabletop = false

    // Read from the same App Group suite the Settings picker writes to, so flipping the appearance
    // there re-tints the whole app at once rather than only the tab that changed it.
    @AppStorage("appearance", store: AppGroupStore.defaults) private var appearance: SharedSettings.Appearance = .system
    @Environment(\.spansFold) private var spansFold
    @Environment(BigScreenModel.self) private var model

    /// Nonisolated: `ScreenshotSupport` reads it from a nonisolated default.
    nonisolated static let wallTab = 2

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
            // A stack because the wall's controls are toolbar items (the desk clock's bottom bar). It keeps
            // the screen awake from its own appear / disappear, which switching tabs fires.
            NavigationStack { WallModeView() }
                .tabItem { Label("Wall", systemImage: BigScreenRoute.wall.symbol) }
                .tag(Self.wallTab)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(3)
        }
        .tint(.amberTint)
        .preferredColorScheme(appearance.colorScheme)
        // Set down half open, the Duo becomes a desk clock. Only on the way into the posture (or launching
        // in it), so another tab can still be picked while it stands, and opening it keeps that tab.
        .onChange(of: isTabletop, initial: true) { _, tabletop in
            if tabletop { selection = Self.wallTab }
        }
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
            nearMe.showsLines = ScreenshotSupport.showsLines
            model.showsLanes = ScreenshotSupport.showsLanes
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

    // Folded, the radar and the map share one stack behind List | Lines; unfolded the split shows both.
    @ViewBuilder private var nearMeBoards: some View {
        if spansFold {
            NearMeSplit(nearMe: $nearMe)
        } else {
            NavigationStack(path: $nearMe.path) {
                Group {
                    if nearMe.showsLines {
                        NearMeLines(nearMe: $nearMe).navigationTitle("Near me")
                    } else {
                        BoardView(journey: nil, nearMe: $nearMe)
                    }
                }
                .modeSwitch($nearMe.showsLines, "List", "Lines")
                .navigationDestination(for: JourneyConfiguration.self) { BoardView(journey: $0) }
            }
        }
    }

    // The path lives on the shared model so that folding a Duo, which swaps the split for a plain stack,
    // leaves you on the journey you had open. Unfolded, Lanes is the split's detail, so no switch there.
    @ViewBuilder private var journeysTab: some View {
        if spansFold {
            JourneysSplit()
        } else {
            @Bindable var model = model
            NavigationStack(path: $model.journeyPath) {
                Group {
                    if model.showsLanes {
                        // The tab's title over the switch, as on List; Lanes' own heading and controls follow.
                        LanesView().navigationTitle("Journeys")
                    } else {
                        JourneysView()
                    }
                }
                .modeSwitch($model.showsLanes, "List", "Lanes")
                .navigationDestination(for: JourneyConfiguration.self) { JourneyBoardScreen(journey: $0) }
            }
        }
    }
}
#endif
