import SNCFCore
import SwiftUI

/// The big-screen destinations: the four screens the sidebar's views and ⌘1–4 switch between, plus the
/// station board a search or NEAR ME opens and the Settings pane.
enum BigScreenRoute: Hashable, CaseIterable {
    case stationHall, lanes, wall, roundTrip, station, settings

    /// The routes bound to ⌘1–4, in that order.
    static let numbered: [BigScreenRoute] = [.stationHall, .lanes, .wall, .roundTrip]

    var title: String {
        switch self {
        case .stationHall: "Station hall"
        case .lanes: "Lanes"
        case .wall: "Wall mode"
        case .roundTrip: "Round trip"
        case .station: "Station"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .stationHall: "rectangle.3.group"
        case .lanes: "chart.bar.doc.horizontal"
        case .wall: "tv"
        case .roundTrip: "arrow.left.arrow.right"
        case .station: "mappin.and.ellipse"
        case .settings: "slider.horizontal.3"
        }
    }

    /// The ⌘ digit that selects this route; nil for the two that are reached from the sidebar only.
    var shortcut: KeyEquivalent? {
        switch self {
        case .stationHall: "1"
        case .lanes: "2"
        case .wall: "3"
        case .roundTrip: "4"
        case .station, .settings: nil
        }
    }
}

/// The shell's navigation state. The screens observe it; the keyboard commands and the sidebar mutate it.
@Observable final class BigScreenModel {
    var route: BigScreenRoute = .stationHall
    /// Which saved journey the station-hall board shows: an index into `data.journeyBoards`. The sidebar
    /// sets it, the centre board reads it. Clamped by the reader so a stale index never traps.
    var selectedJourney = 0
    /// The station `.station` shows, picked from the search or NEAR ME.
    var station: Station?
    /// ⌘K asked for the "go to station" search; the sidebar owns the actual field and clears this.
    var searchRequested = false
    /// ⌘R bumps this; screens reload when it changes.
    var refreshTick = 0
    /// An unsaved journey a lane of the station line map opened, station → terminus. The station hall board
    /// shows it inside the `.station` route, so the back button is just clearing it; any other navigation
    /// drops it, because it is not saved anywhere to come back to.
    var temporaryLeg: Leg?
    /// The Journeys tab's pushed journey. Held here rather than in the tab so folding and unfolding a Duo,
    /// which swaps the tab between a plain stack and a split, keeps you on the same journey.
    var journeyPath: [JourneyConfiguration] = []
    /// The folded Journeys tab's List | Lanes switch, here beside `journeyPath` for the same reason.
    var showsLanes = false
    /// The train a journey board hands to the detail column on the Duo's inner display; nil shows Lanes.
    var detailTrain: PickedTrain?

    func select(_ route: BigScreenRoute) { temporaryLeg = nil; self.route = route }
    /// Picking a journey always returns to the board it feeds.
    func select(journey index: Int) { temporaryLeg = nil; selectedJourney = index; route = .stationHall }
    func show(station: Station) { temporaryLeg = nil; self.station = station; route = .station }
    /// Opened from the station map or from the hall's Swap; Back returns to whichever it was.
    func open(temporary leg: Leg) {
        if temporaryLeg == nil { temporaryOrigin = route }
        temporaryLeg = leg
        route = .station
    }
    func closeTemporary() { temporaryLeg = nil; route = temporaryOrigin }
    private var temporaryOrigin: BigScreenRoute = .station
    func requestSearch() { searchRequested = true }
    func refresh() { refreshTick += 1 }
}

/// A train picked on a journey board, with the leg it was picked for, so the detail column can draw it.
struct PickedTrain: Equatable {
    let train: TrainDeparture
    let leg: Leg
}

/// The big-screen container: a sidebar + a routed detail column on macOS and on iPad / any regular
/// width; compact iPhone and the iPhone Duo keep the four-tab `RootView`. The keyboard commands (⌘K /
/// ⌘R / ⌘1–4, in `BigScreenCommands`) drive the route; Wall mode is a route like the others.
struct BigScreenRoot: View {
    @Environment(\.bigScreenData) private var data
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    #if os(macOS)
    // The menu-bar "Wall mode on this display" (⌘3) cannot reach this window's BigScreenModel across
    // scenes, so it leaves a flag here; the window consumes it on appear (cold open) and on change
    // (already open). Same process, so plain standard defaults carry it.
    @AppStorage("bigscreen.pendingRoute") private var pendingRoute = ""
    #endif
    @State private var model = BigScreenModel()

    var body: some View {
        content
            .environment(model)
            // The menu commands (⌘1–4, ⌘K, ⌘R) reach this window's model through the focused scene.
            .focusedSceneValue(\.bigScreenModel, model)
            // The Settings pane's picker; the big screen follows it like the iPhone tabs do.
            .followsAppearance()
            // A journey edit from any window, the Mac's ⌘, Settings included, refreshes this one's screens.
            .onReceive(NotificationCenter.default.publisher(for: SharedSettings.favoritesDidChange).receive(on: RunLoop.main)) { _ in
                model.refresh()
            }
        #if os(macOS)
            .onAppear { consumePendingRoute() }
            .onChange(of: pendingRoute) { _, _ in consumePendingRoute() }
        #endif
        #if DEBUG && os(iOS)
            .task { ScreenshotSupport.apply(to: model) }
        #endif
    }

    #if os(macOS)
    private func consumePendingRoute() {
        guard pendingRoute == "wall" else { return }
        model.select(.wall)
        pendingRoute = ""
    }
    #endif

    @ViewBuilder private var content: some View {
        #if os(iOS)
        // A fold means the Duo: its system bars stand up in a strip only around the native TabView, and the
        // big views become detail columns inside the tabs, so the 280 pt sidebar split is retired there.
        // One branch for both poses, so folding keeps RootView (and its selected tab) alive.
        GeometryReader { proxy in
            let spansFold = Fold.division(in: proxy) != nil
            if spansFold || sizeClass == .compact {
                RootView(isTabletop: Fold.isTabletop(in: proxy)).environment(\.spansFold, spansFold)
            } else {
                split
            }
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
        // Balanced, not the automatic overlay: in iPad portrait the sidebar laid over the board and hid its
        // left edge; side by side, the board narrows and moves its inspector into a sheet instead.
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder private var detail: some View {
        switch model.route {
        case .stationHall: StationHallView()
        case .lanes: LanesView()
        case .wall: WallModeView()
        case .roundTrip: RoundTripView()
        case .station:
            if model.temporaryLeg != nil {
                StationHallView()
            } else if let station = model.station {
                StationBoardView(station: station)
            } else {
                StationHallView()
            }
        case .settings: SettingsView()
        }
    }
}

// MARK: - Commands

extension FocusedValues {
    @Entry var bigScreenModel: BigScreenModel?
}

/// The big screen's keyboard commands as real menu items, so they show in the View menu on the Mac and
/// in the hardware-keyboard overlay on iPad; they act on whichever big-screen window has focus.
struct BigScreenCommands: Commands {
    /// Handed in by the App: a `Commands` body does not see the environment the scenes' views get.
    let data: BigScreenData
    @FocusedValue(\.bigScreenModel) private var model

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(BigScreenRoute.numbered, id: \.self) { route in
                if let key = route.shortcut {
                    Button(route.title) { model?.select(route) }.keyboardShortcut(key, modifiers: .command)
                        .disabled(model == nil)
                }
            }
            Divider()
            Button("Go to station") { model?.requestSearch() }.keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil)
            // ⌘R means "fetch now", so the boards memo that spares the duplicate requests is dropped first.
            Button("Refresh") {
                guard let model else { return }
                Task { await data.journeyBoards.invalidate(); model.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model == nil)
        }
    }
}

// MARK: - Sidebar (Main.dc.html's left column)

/// The station-hall sidebar: app mark, a "Go to station" search over every SNCF station, the NEAR ME row,
/// the saved journeys (add / edit / delete / reorder), the VIEWS switcher, Settings and the "Updated …"
/// freshness line. It is the shell sidebar, so it is what the two-column split shows beside every screen.
private struct BigScreenSidebar: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model

    @State private var boards: [JourneyBoard] = []
    @State private var pinned: Station?
    @State private var near: Result<NearbyStation, TrainServiceError>?
    @State private var nextNearMe: Date?
    @State private var location = LocationFix.shared

    @State private var query = ""
    @State private var results: [Station] = []
    @State private var searchFailure: String?
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    @State private var adding = false
    @State private var editTarget: JourneyConfiguration?

    /// A frozen `BigScreenFixtures.now` from the `#Preview`, so the mockup lines up; nil follows the clock.
    private let frozenNow: Date?

    init(now: Date? = nil) { frozenNow = now }

    // The rows' next times and NEXT tags move with the minute; the fetch is keyed on ⌘R, not on the time.
    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: frozenNow ?? context.date)
        }
    }

    /// The clock a request is asked at: read when it starts, so ⌘R asks at the real time and lands in the
    /// same boards-memo round as the screen beside it, rather than a minute or an hour behind.
    private var requestTime: Date { frozenNow ?? Date() }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            appMark
            searchField
            if !query.isEmpty {
                searchResults
            } else {
                nearMe
                journeys(now: now)
                views
            }
            Spacer(minLength: 0)
            footer(now: now)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ground)
        .task(id: model.refreshTick) { await load() }
        // A just-granted permission is worth a fresh NEAR ME at once, not at the next ⌘R.
        .onChange(of: location.status) { Task { await loadNear() } }
        .task(id: query) { await search() }
        // ⌘K hands focus to the search field, then releases the flag so the next ⌘K fires again.
        .onChange(of: model.searchRequested) { _, requested in
            if requested { searchFocused = true; model.searchRequested = false }
        }
        .sheet(isPresented: $adding) {
            EditJourneyView { save(SharedSettings.favorites + [$0]) }
        }
        .sheet(item: $editTarget) { target in
            EditJourneyView(existing: target) { updated in
                save(SharedSettings.favorites.map { $0 == target ? updated : $0 })
            }
        }
        .navigationTitle("")
    }

    private func load() async {
        boards = await data.journeyBoards.boards(at: requestTime)
        pinned = await data.leaveBy.pinnedStation()
        await loadNear()
    }

    private func loadNear() async {
        do throws(TrainServiceError) { near = .success(try await data.stationSearch.nearest()) }
        catch { near = .failure(error) }
        if let station = nearStation {
            let at = requestTime
            nextNearMe = BoardReading.nextUpcoming(await data.stationBoard.board(for: station, at: at), after: at)?.expectedDeparture
        } else {
            nextNearMe = nil
        }
    }

    /// The station NEAR ME stands for: the nearest one, or the pinned one when there is no fix.
    private var nearStation: Station? {
        if case .success(let found) = near { return found.station }
        return pinned
    }

    private func save(_ journeys: [JourneyConfiguration]) {
        SavedJourneys.save(journeys)
    }

    // MARK: Search

    /// A pause in the typing, at least two letters, then one request; `task(id:)` cancels the sleep as the
    /// next key lands, so a word typed fast costs one lookup.
    private func search() async {
        searchFailure = nil
        highlighted = 0
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do throws(TrainServiceError) {
            results = try await data.stationSearch.search(text)
        } catch {
            results = []
            searchFailure = error.appDescription
        }
    }

    private func pick(_ station: Station) {
        model.show(station: station)
        query = ""
        searchFocused = false
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
                .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(results.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""; searchFocused = false
                    return .handled
                }
                .onSubmit { if results.indices.contains(highlighted) { pick(results[highlighted]) } }
            Text("⌘K").font(.mono(11, weight: .semibold)).foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.ink.opacity(0.14), lineWidth: 1))
        }
        .padding(.horizontal, 10).frame(minHeight: 38)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let searchFailure {
                note(searchFailure)
            } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                note("Keep typing…")
            } else if results.isEmpty {
                note("No station matches")
            }
            ForEach(Array(results.prefix(8).enumerated()), id: \.element.id) { index, station in
                Button { pick(station) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 13)).foregroundStyle(Color.amberText)
                        Text(station.name).font(.system(size: 15)).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(10).contentShape(Rectangle())
                    .background(index == highlighted ? Color.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Color.inkSecondary).padding(10)
    }

    private var nearMe: some View {
        SidebarSection("NEAR ME") {
            Button {
                if let station = nearStation { model.show(station: station) }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18)).foregroundStyle(Color.amberText).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nearStation?.name ?? "Nearest station").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text(nearDetail).font(.mono(11.5)).foregroundStyle(Color.inkSecondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let nextNearMe {
                        Text(HallFormat.hm(nextNearMe)).font(.mono(14, weight: .semibold)).foregroundStyle(Color.amberText)
                    }
                }
                .padding(10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(nearStation == nil)
            if case .failure(.noLocation) = near, location.status == .notDetermined {
                Button("Allow location") { location.requestAuthorization() }
                    .buttonStyle(.borderless).font(.system(size: 13, weight: .semibold)).tint(.amberText)
                    .padding(.horizontal, 10)
            }
        }
    }

    /// The second line: how far the station is, or — without one — why, so an empty row never just sits there.
    private var nearDetail: String {
        switch near {
        case nil: return "looking around…"
        case .success(let found): return ["every direction", found.distance.map(Self.distance)].compactMap { $0 }.joined(separator: " · ")
        case .failure(let error):
            let reason: String
            switch error {
            case .noLocation:
                switch location.status {
                case .notDetermined: reason = "location not allowed yet"
                case .denied, .restricted: reason = "location is off for this app"
                default: reason = "no position yet"
                }
            case .noStationNearby: reason = "no station within \(SNCFClient.searchRadiusKilometres) km"
            default: reason = error.terse.lowercased()
            }
            return pinned == nil ? reason : "pinned · \(reason)"
        }
    }

    private static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Int((metres / 10).rounded()) * 10) m" : String(format: "%.1f km", metres / 1000)
    }

    private func journeys(now: Date) -> some View {
        SidebarSection("JOURNEYS", accessory: {
            Button { adding = true } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.inkSecondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a journey")
        }) {
            ForEach(Array(boards.enumerated()), id: \.offset) { index, board in
                Button { model.select(journey: index) } label: {
                    SidebarJourneyRow(board: board, now: now, selected: index == model.selectedJourney && model.route == .stationHall)
                }
                .buttonStyle(.plain)
                .contextMenu { actions(for: board.journey) }
            }
        }
    }

    /// Edit / move / delete against the saved list; a board whose journey is not saved (the mockup data
    /// in previews) has nothing to act on.
    @ViewBuilder private func actions(for journey: JourneyConfiguration) -> some View {
        let saved = SharedSettings.favorites
        if let index = saved.firstIndex(of: journey) {
            JourneyActions(journey: journey, index: index, count: saved.count,
                           edit: { editTarget = journey }, apply: save, journeys: saved)
        }
    }

    private var views: some View {
        SidebarSection("VIEWS") {
            viewRow(.lanes, shortcut: "⌘2")
            viewRow(.wall, shortcut: "⌘3")
            viewRow(.roundTrip, shortcut: "⌘4")
        }
    }

    private func viewRow(_ route: BigScreenRoute, shortcut: String?) -> some View {
        Button { model.select(route) } label: {
            HStack(spacing: 11) {
                Image(systemName: route.symbol).font(.system(size: 15)).frame(width: 18)
                Text(route.title).font(.system(size: 15))
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut).font(.mono(11, weight: .semibold)).foregroundStyle(Color.inkSecondary.opacity(0.8))
                }
            }
            .foregroundStyle(model.route == route ? Color.amberText : Color.ink.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
            .background(model.route == route ? Color.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Settings opens as a pane of this window rather than the small separate panel, so the token,
            // the journeys and the appearance sit at the size the rest of the big screen is drawn at.
            viewRow(.settings, shortcut: nil)
            HStack(spacing: 7) {
                Circle().fill(Color.soon).frame(width: 7, height: 7)
                Text("Updated \(HallFormat.hm(boards.first?.fetchedAt ?? now)) · ⌘R")
                    .font(.mono(11.5)).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 10)
        }
    }
}

/// The "T" flap mark: a flap tile, an amber mono glyph, the split-flap seam across the middle.
private struct FlapMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.flapTile)
            Text("T").font(.monoFixed(18, weight: .bold)).foregroundStyle(Color.amber)
            Color.ground.frame(height: 1)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// A mono-caps sidebar section header over its rows, with an optional control at the header's end.
private struct SidebarSection<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.mono(11, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Color.inkSecondary)
                Spacer(minLength: 0)
                accessory
            }
            .padding(.horizontal, 10)
            content
        }
    }
}

extension SidebarSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
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
                Text(HallFormat.hm(next.expectedDeparture)).font(.mono(14, weight: .semibold)).foregroundStyle(Color.amberText)
            } else if let first = board.tomorrow.first(where: { !$0.isCancelled }) {
                // Tonight is over: the morning's first, dimmed behind a moon so it never reads as the next
                // train this evening.
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill").font(.system(size: 10, weight: .semibold))
                    Text(HallFormat.hm(first.expectedDeparture)).font(.mono(14, weight: .semibold))
                }
                .foregroundStyle(Color.inkSecondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("First train tomorrow \(HallFormat.hm(first.expectedDeparture))")
            }
        }
    }
}

extension View {
    /// The selected row of a table or list card: an edge-to-edge amber tint and a 3 pt bar on the leading
    /// edge, no ring. An inset ring had to dodge the card's rounded corners and so sat with more room left
    /// and right than above and below; a fill and a flush bar can simply be clipped by the card.
    func selectedRowBackground(_ isSelected: Bool) -> some View {
        background {
            if isSelected {
                Color.amber.opacity(0.08)
                    .overlay(alignment: .leading) { Color.amber.frame(width: 3) }
            }
        }
    }
}

#Preview("Sidebar") {
    NavigationSplitView {
        BigScreenSidebar(now: BigScreenFixtures.now).navigationSplitViewColumnWidth(280)
    } detail: {
        Color.ground
    }
    .environment(BigScreenModel())
    .frame(width: 1100, height: 760)
    .preferredColorScheme(.dark)
}
