import SNCFCore
import SwiftUI

/// The four big-screen destinations, driven from the sidebar and ⌘1–4.
enum BigScreenRoute: Hashable, CaseIterable {
    case stationHall, lanes, wall, roundTrip

    var title: String {
        switch self {
        case .stationHall: "Station hall"
        case .lanes: "Lanes"
        case .wall: "Wall mode"
        case .roundTrip: "Round trip"
        }
    }

    var symbol: String {
        switch self {
        case .stationHall: "rectangle.3.group"
        case .lanes: "chart.bar.doc.horizontal"
        case .wall: "tv"
        case .roundTrip: "arrow.left.arrow.right"
        }
    }

    /// The ⌘ digit that selects this route.
    var shortcut: KeyEquivalent {
        switch self {
        case .stationHall: "1"
        case .lanes: "2"
        case .wall: "3"
        case .roundTrip: "4"
        }
    }
}

/// The shell's navigation state. The screens observe it; the keyboard commands and the sidebar mutate it.
@Observable final class BigScreenModel {
    var route: BigScreenRoute = .stationHall
    /// ⌘K asked for the "go to station" search; a screen owns the actual field.
    var searchRequested = false
    /// ⌘R bumps this; screens reload when it changes.
    var refreshTick = 0

    func select(_ route: BigScreenRoute) { self.route = route }
    func requestSearch() { searchRequested = true }
    func refresh() { refreshTick += 1 }
    /// Esc: leave Wall mode, otherwise do nothing (a screen may dismiss its own sheet first).
    func escape() { if route == .wall { route = .stationHall } }
}

/// The big-screen container: a sidebar + a routed detail column on macOS and on iPad / any regular
/// width; compact iPhone keeps the existing three-tab `RootView`. The keyboard commands (⌘K / ⌘R /
/// ⌘1–4 / Esc) are wired here and drive the route; the screens decide what each one does.
struct BigScreenRoot: View {
    @Environment(\.bigScreenData) private var data
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var model = BigScreenModel()

    var body: some View {
        content
            .environment(model)
            .background(commands)
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        if sizeClass == .compact {
            RootView()
        } else {
            split
        }
        #else
        split
        #endif
    }

    private var split: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List {
            Section("Views") {
                ForEach(BigScreenRoute.allCases, id: \.self) { route in
                    Button {
                        model.select(route)
                    } label: {
                        Label(route.title, systemImage: route.symbol)
                            .foregroundStyle(model.route == route ? Color.amber : Color.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Trains near me")
    }

    @ViewBuilder private var detail: some View {
        switch model.route {
        case .stationHall: StationHallView()
        case .lanes: LanesView()
        case .wall: WallModeView()
        case .roundTrip: RoundTripView()
        }
    }

    // Hidden shortcut sinks: the one cross-platform way (iPad hardware keyboard + Mac) to bind ⌘-keys
    // without an AppKit/UIKit responder. Phase 1 can promote these to a macOS `.commands` menu.
    private var commands: some View {
        Group {
            ForEach(BigScreenRoute.allCases, id: \.self) { route in
                Button("") { model.select(route) }.keyboardShortcut(route.shortcut, modifiers: .command)
            }
            Button("") { model.requestSearch() }.keyboardShortcut("k", modifiers: .command)
            Button("") { model.refresh() }.keyboardShortcut("r", modifiers: .command)
            Button("") { model.escape() }.keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// The shared stub body each Phase-1 screen replaces: it reads `BigScreenData` from the environment so
/// the whole pipe (scene → environment → providers) compiles and runs on the fake today.
struct BigScreenPlaceholder: View {
    let route: BigScreenRoute
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: route.symbol)
                .font(.system(size: 46))
                .foregroundStyle(Color.inkSecondary)
            Text(route.title).font(.largeTitle.bold()).foregroundStyle(Color.ink)
            Text(detail).font(.mono(13)).foregroundStyle(Color.inkSecondary)
            Text("Phase 1 owner fills this").font(.caption).foregroundStyle(Color.inkSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ground.ignoresSafeArea())
    }
}
