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
    /// Which saved journey the station-hall board shows: an index into `data.journeyBoards`. The sidebar
    /// sets it, the centre board reads it. Clamped by the reader so a stale index never traps.
    var selectedJourney = 0
    /// ⌘K asked for the "go to station" search; the sidebar owns the actual field and clears this.
    var searchRequested = false
    /// ⌘R bumps this; screens reload when it changes.
    var refreshTick = 0

    func select(_ route: BigScreenRoute) { self.route = route }
    /// Picking a journey always returns to the board it feeds.
    func select(journey index: Int) { selectedJourney = index; route = .stationHall }
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
            BigScreenSidebar()
                .navigationSplitViewColumnWidth(280)
        } detail: {
            detail
        }
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

// MARK: - Sidebar (Main.dc.html's left column)

/// The station-hall sidebar: app mark, a "Go to station" search over known stations, the NEAR ME row,
/// the saved journeys, the VIEWS switcher, Settings and the "Updated …" freshness line. It is the shell
/// sidebar, so it is what the two-column split shows beside every screen.
private struct BigScreenSidebar: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model

    @State private var boards: [JourneyBoard] = []
    @State private var pinned: Station?
    @State private var nextNearMe: Date?
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// Thu 15 Oct 2026, 17:40 — the fake world the whole Phase-1 build renders against. Flip to `Date()`
    /// at the one spot `TrainsNearMeApp` injects live data, and every relative time follows.
    private let now = BigScreenFixtures.now

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            appMark
            searchField
            if !query.isEmpty && searchFocused {
                searchResults
            } else {
                nearMe
                journeys
                views
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ground)
        .task(id: model.refreshTick) { await load() }
        // ⌘K hands focus to the search field, then releases the flag so the next ⌘K fires again.
        .onChange(of: model.searchRequested) { _, requested in
            if requested { searchFocused = true; model.searchRequested = false }
        }
        .navigationTitle("")
    }

    private func load() async {
        boards = await data.journeyBoards.boards(at: now)
        pinned = await data.leaveBy.pinnedStation()
        if let pinned {
            nextNearMe = BoardReading.nextUpcoming(await data.stationBoard.board(for: pinned, at: now), after: now)?.expectedDeparture
        }
    }

    // MARK: Pieces

    private var appMark: some View {
        HStack(spacing: 10) {
            FlapMark()
            Text("Trains near me").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.inkSecondary)
            TextField("Go to station", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)
                .focused($searchFocused)
            Text("⌘K").font(.mono(11, weight: .semibold)).foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.ink.opacity(0.14), lineWidth: 1))
        }
        .padding(.horizontal, 10).frame(height: 38)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }

    // Phase 1 searches only the stations we already hold (journey endpoints + the pinned station): the
    // views cannot call `SNCFClient`, so a live text search needs a `StationSearching` provider added to
    // `BigScreenData`. Picking a result jumps to a journey that touches that station.
    private var searchResults: some View {
        let matches = knownStations.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(6)
        return VStack(alignment: .leading, spacing: 2) {
            if matches.isEmpty {
                Text("No saved station matches").font(.system(size: 13)).foregroundStyle(Color.inkSecondary).padding(10)
            }
            ForEach(Array(matches), id: \.id) { station in
                Button {
                    if let index = boards.firstIndex(where: { $0.leg.from.id == station.id || $0.leg.to.id == station.id }) {
                        model.select(journey: index)
                    }
                    query = ""; searchFocused = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 13)).foregroundStyle(Color.amber)
                        Text(station.name).font(.system(size: 15)).foregroundStyle(Color.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Journey endpoints plus the pinned station, de-duplicated by id in first-seen order.
    private var knownStations: [Station] {
        var seen = Set<String>()
        var out: [Station] = []
        for station in boards.flatMap({ [$0.leg.from, $0.leg.to] }) + [pinned].compactMap({ $0 }) where seen.insert(station.id).inserted {
            out.append(station)
        }
        return out
    }

    private var nearMe: some View {
        SidebarSection("NEAR ME") {
            // Tapping surfaces the "follows you" journey if one is saved; distance needs a location the
            // views cannot read, so it is left to the live build.
            Button {
                if let index = boards.firstIndex(where: { $0.journey.nearestStationAsDeparture }) { model.select(journey: index) }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18)).foregroundStyle(Color.amber).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pinned?.name ?? "Nearest station").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                        Text("every direction").font(.mono(11.5)).foregroundStyle(Color.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    if let nextNearMe {
                        Text(HallFormat.hm(nextNearMe)).font(.mono(14, weight: .semibold)).foregroundStyle(Color.amber)
                    }
                }
                .padding(10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var journeys: some View {
        SidebarSection("JOURNEYS") {
            ForEach(Array(boards.enumerated()), id: \.offset) { index, board in
                Button { model.select(journey: index) } label: {
                    SidebarJourneyRow(board: board, now: now, selected: index == model.selectedJourney && model.route == .stationHall)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var views: some View {
        SidebarSection("VIEWS") {
            viewRow(.lanes, symbol: "chart.bar.doc.horizontal", shortcut: "⌘2")
            viewRow(.wall, symbol: "tv", shortcut: "⌘3")
            viewRow(.roundTrip, symbol: "arrow.left.arrow.right", shortcut: "⌘4")
        }
    }

    private func viewRow(_ route: BigScreenRoute, symbol: String, shortcut: String) -> some View {
        Button { model.select(route) } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 18)
                Text(route.title).font(.system(size: 15))
                Spacer(minLength: 0)
                Text(shortcut).font(.mono(11, weight: .semibold)).foregroundStyle(Color.inkSecondary.opacity(0.8))
            }
            .foregroundStyle(model.route == route ? Color.amber : Color.ink.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
            .background(model.route == route ? Color.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            SettingsLink {
                settingsLabel
            }
            .buttonStyle(.plain)
            #else
            settingsLabel
            #endif
            HStack(spacing: 7) {
                Circle().fill(Color.soon).frame(width: 7, height: 7)
                Text("Updated \(HallFormat.hm(boards.first?.fetchedAt ?? now)) · ⌘R")
                    .font(.mono(11.5)).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 10)
        }
    }

    private var settingsLabel: some View {
        HStack(spacing: 11) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 15)).frame(width: 18)
            Text("Settings").font(.system(size: 15))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ink.opacity(0.85))
        .padding(.horizontal, 10).padding(.vertical, 9)
    }
}

/// The "T" flap mark: a raised tile, an amber mono glyph, the split-flap seam across the middle.
private struct FlapMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.raised)
            Text("T").font(.monoFixed(18, weight: .bold)).foregroundStyle(Color.amber)
            Color.ground.frame(height: 1)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// A mono-caps sidebar section header over its rows.
private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.mono(11, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Color.inkSecondary).padding(.horizontal, 10)
            content
        }
    }
}

/// One saved journey in the sidebar: route glyph, name, direction rule, and the next time in amber — or
/// a trouble badge (a delay clock when the next train is late, a NO SERVICE pill when nothing runs).
private struct SidebarJourneyRow: View {
    let board: JourneyBoard
    let now: Date
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            RoutePins(destination: trouble == .noService ? .solid(.inkSecondary) : .ring(core: .ink, ring: .amber),
                      originDiameter: 8, destinationDiameter: 10, lineLength: 16)
                .frame(width: 12, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: selected ? .semibold : .medium)).foregroundStyle(Color.ink).lineLimit(1)
                Text(HallFormat.directionCaps(board.journey)).font(.mono(10.5, weight: .semibold)).tracking(1)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(10)
        .background(selected ? Color.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ink.opacity(selected ? 0.06 : 0), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var name: String {
        board.journey.nearestStationAsDeparture
            ? "\(board.journey.stationA.name) ⇄ \(board.journey.stationB.name)"
            : "\(board.leg.from.name) → \(board.leg.to.name)"
    }

    private enum Trouble { case none, delayed, noService }

    private var trouble: Trouble {
        if case .noService = board.state { return .noService }
        let next = BoardReading.nextUpcoming(board.state, after: now)
        switch next?.status {
        case .delayed, .severelyDelayed, .unknown: return .delayed
        default: return .none
        }
    }

    @ViewBuilder private var trailing: some View {
        switch trouble {
        case .noService:
            Text("NO SERVICE").font(.mono(10, weight: .bold)).tracking(0.8).foregroundStyle(Color.stop)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Color.stopBg, in: RoundedRectangle(cornerRadius: 6))
        case .delayed:
            if let next = BoardReading.nextUpcoming(board.state, after: now) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 12, weight: .semibold))
                    Text(HallFormat.hm(next.expectedDeparture)).font(.mono(14, weight: .semibold))
                }
                .foregroundStyle(next.status.tableauInk)
            }
        case .none:
            if let next = BoardReading.nextUpcoming(board.state, after: now) {
                Text(HallFormat.hm(next.expectedDeparture)).font(.mono(14, weight: .semibold)).foregroundStyle(Color.amber)
            }
        }
    }
}

/// The shared stub body each not-yet-built screen replaces: it reads `BigScreenData` from the environment
/// so the whole pipe (scene → environment → providers) compiles and runs on the fake today.
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

#Preview("Sidebar") {
    NavigationSplitView {
        BigScreenSidebar().navigationSplitViewColumnWidth(280)
    } detail: {
        Color.ground
    }
    .environment(BigScreenModel())
    .frame(width: 1100, height: 760)
    .preferredColorScheme(.dark)
}
