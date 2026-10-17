import SNCFCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Wall mode — a full-screen departure board kept awake (Wall.dc.html). The board follows the card picked
/// under YOUR JOURNEYS: one saved journey's trains, or "Station", every departure from the pinned station
/// (the nearest one when nothing is pinned). It is an ordinary page of the app: the sidebar stays and any
/// route leaves it.
///
/// Always drawn on the Board (dark) palette whatever the app's appearance setting: a wall is a dark
/// board, so the subtree forces `\.colorScheme = .dark` and the Tableau tokens resolve to their dark
/// variants. The only hard-coded colours are the three wall shades that have no token (`#0A0B0C` ground,
/// `#121316` panel, `#1C1E22` clock tile).
struct WallModeView: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model

    /// The card last picked on the wall: `stationKey`, a journey's `key(for:)`, or "" before any pick.
    /// Keyed by the journey's station ids rather than its index, so reordering the saved list keeps it.
    @AppStorage("wall.selection") private var selection = ""

    /// A frozen anchor for previews / screenshots; nil in the app so the board and clock follow the real
    /// clock (and ⌘R re-anchors to the current time).
    private let frozenNow: Date?
    /// When the last fetch ran; only the requests read it, the drawing reads the timeline's date.
    @State private var now = Date()

    @State private var station: Station?
    @State private var stationIsPinned = false
    @State private var stationBoard = StationDayBoard(state: .noTrains)
    @State private var journeys: [JourneyBoard] = []
    /// The walk to `leaveLeg`'s station; LEAVE HOME IN is worked out from it and the held board at each tick.
    @State private var walk: Int?
    @State private var leaveLeg: Leg?

    #if os(macOS)
    @State private var awake = WallAwake()
    #endif
    /// The desk clock's sun button; on until turned off, as the wall always was.
    @State private var keepAwake = true
    @Environment(\.previewFold) private var previewFold

    init(now: Date? = nil) {
        frozenNow = now
    }

    private static let stationKey = "station"
    private static func key(for journey: JourneyConfiguration) -> String {
        "\(journey.stationA.id)|\(journey.stationB.id)"
    }

    /// The journey the wall shows, nil for the station board. Nothing picked yet, or the picked journey
    /// since deleted, falls back to the first saved one; no saved journey at all leaves the station.
    private var current: JourneyBoard? {
        guard selection != Self.stationKey, let first = journeys.first else { return nil }
        return journeys.first { Self.key(for: $0.journey) == selection } ?? first
    }

    private var shownState: BoardState { current?.state ?? stationBoard.state }
    /// The morning under the split: the journey's, or the station's once tonight is nearly done.
    private var shownTomorrow: [TrainDeparture] { current?.tomorrow ?? stationBoard.tomorrow }

    var body: some View {
        // `.everyMinute` fires on each minute change, which a clock needs: a `.periodic` schedule anchored
        // on the last fetch ticks at that fetch's second and restarts on every reload. The clock, the
        // countdowns, LEAVE HOME IN and the dropping of departed rows all read `context.date`.
        TimelineView(.everyMinute) { context in
            // Previews and screenshots stay on the frozen mockup clock instead of the real one.
            wall(liveNow: frozenNow ?? context.date)
        }
        // A wall is left running for hours: refetch every five minutes (the free tier's 5 000 requests a
        // day allow it; the journeys and one board each round), on ⌘R, on appear and on a new pick. Between
        // rounds the minute tick drops departed rows and recounts the countdowns from what is held.
        .task(id: "\(model.refreshTick)|\(selection)") {
            await load()
            guard frozenNow == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { break }
                await load()
            }
        }
        .keepScreenAwake(enter: enterKeepAwake, leave: leaveKeepAwake)
        .onChange(of: keepAwake) { _, on in on ? enterKeepAwake() : leaveKeepAwake() }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Loading

    private func load() async {
        now = frozenNow ?? Date()
        journeys = await data.journeyBoards.boards(at: now)
        // The pin is a local read, so the Station card can name it whatever the wall shows; the nearest
        // station costs a location fix and a request, so it is only looked up when the board needs it. The
        // station card asks for the service day rather than a fixed count: the same one request, and late
        // in the evening it brings the morning for the split.
        let pinned = await data.leaveBy.pinnedStation()
        stationIsPinned = pinned != nil
        station = pinned
        if current == nil {
            if let pinned {
                stationBoard = await data.stationBoard.serviceDayBoard(for: pinned, at: now)
            } else {
                do throws(TrainServiceError) {
                    let nearest = try await data.stationSearch.nearest().station
                    station = nearest
                    stationBoard = await data.stationBoard.serviceDayBoard(for: nearest, at: now)
                } catch {
                    stationBoard = StationDayBoard(state: .unavailable(error))
                }
            }
        }
        // LEAVE HOME IN follows the journey on the board; the station board keeps the first saved one. Only
        // the walk is looked up: the trains are the board already held, so it costs no request.
        leaveLeg = current?.leg ?? journeys.first?.leg
        if let leaveLeg {
            walk = await data.leaveBy.walkMinutes(to: leaveLeg.from)
        } else {
            walk = nil
        }
    }

    // MARK: Keep awake

    private func enterKeepAwake() {
        guard keepAwake else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #elseif os(macOS)
        awake.begin()
        #endif
    }

    private func leaveKeepAwake() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #elseif os(macOS)
        awake.end()
        #endif
    }

    // MARK: Layout

    /// Which arrangement the wall takes. Read from the fold's region and the size, never the hinge angle:
    /// the region only changes when the posture does, so the wall does not flicker while the hinge moves.
    private enum Arrangement {
        /// The board and the side column: a Mac, an iPad or the Duo's inner display in landscape, whose
        /// fold (flat or half open) the columns stay clear of.
        case columns(FoldGap?)
        /// Partially open with the fold across: the glance stands up, the board lies on the table.
        case tabletop(FoldGap)
        /// Narrow or portrait: the glance over the board, the journeys in the toolbar.
        case stacked
        /// An iPhone (either way up), the folded Duo: one scrolling column, nothing fixed to the screen.
        case compact

        var hasBottomBar: Bool {
            switch self {
            case .tabletop, .stacked: true
            case .columns, .compact: false
            }
        }
    }

    private func arrangement(_ size: CGSize, _ region: Fold.Region?) -> Arrangement {
        if let region, region.isTabletop { return .tabletop(region.gap) }
        if let region, region.isVertical { return .columns(region.gap) }
        // Too narrow for the glance's pairs side by side, or too short for a board under a header (an
        // iPhone on its side): the iPhone's own column.
        if size.width < 560 || size.height < 500 { return .compact }
        return size.width > size.height && size.width >= 760 ? .columns(nil) : .stacked
    }

    private func wall(liveNow: Date) -> some View {
        GeometryReader { proxy in
            let arrangement = arrangement(proxy.size, Fold.region(in: proxy, preview: previewFold))
            Group {
                switch arrangement {
                case .columns(let gap): columns(liveNow: liveNow, size: proxy.size, gap: gap)
                case .tabletop(let gap): tabletop(liveNow: liveNow, gap: gap)
                case .stacked: stacked(liveNow: liveNow)
                case .compact: compact(liveNow: liveNow, width: proxy.size.width)
                }
            }
            .toolbar { controls(inBottomBar: arrangement.hasBottomBar) }
        }
        .foregroundStyle(Color.ink)
        .background(Color.wallGround.ignoresSafeArea())
    }

    /// The iPhone's wall, top to bottom in one scroll: the header, LEAVE HOME IN at full width, the
    /// board, the journeys as a row of cards, then the ticker. Inside the safe area, so nothing sits under
    /// the Dynamic Island, the home indicator or a tab bar.
    private func compact(liveNow: Date, width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(liveNow: liveNow, sideBySide: width >= 560)
                leaveCard(to: leaveLeg?.to.name, liveNow: liveNow)
                boardPanel(liveNow: liveNow, density: width < 480 ? .small : width < 668 ? .folded : .full,
                           scrolls: false)
                journeysCaption
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { journeyCards(liveNow: liveNow, width: 260) }
                }
                .scrollClipDisabled()
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
            footer(liveNow: liveNow, tickerWidth: nil, showsCredit: width >= 560)
        }
    }

    /// Our inset from the safe area: the mockups' 24 pt on a phone-sized screen, 40 on an iPad or a Mac.
    private func inset(_ size: CGSize) -> CGFloat { min(size.width, size.height) < 800 ? 24 : 40 }

    /// The board and the side column. With a fold, each side of it holds one, clear of its band; without,
    /// the side column takes at most 40 % of the width so the board's own columns keep their room.
    private func columns(liveNow: Date, size: CGSize, gap: FoldGap?) -> some View {
        let pad = inset(size)
        let spacing = gap.map { $0.start - $0.end } ?? 28
        let side = gap.map { size.width - pad - $0.start } ?? min(400, (size.width - 2 * pad - spacing) * 0.4)
        let board = gap.map { $0.end - pad } ?? size.width - 2 * pad - spacing - side
        return VStack(spacing: 0) {
            VStack(spacing: 26) {
                HStack(alignment: .bottom, spacing: spacing) {
                    title.frame(width: max(0, board), alignment: .leading)
                    clock(liveNow: liveNow).frame(width: max(0, side), alignment: .trailing)
                }
                HStack(alignment: .top, spacing: spacing) {
                    boardPanel(liveNow: liveNow, density: board < 620 ? .folded : .full)
                        .frame(width: max(0, board)).frame(maxHeight: .infinity)
                    rightColumn(liveNow: liveNow)
                        .frame(width: max(0, side))
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, pad)
            .padding(.top, pad)
            .padding(.bottom, 26)
            // Across a fold the ticker stops short of it and the credit moves to the far side.
            footer(liveNow: liveNow, tickerWidth: gap.map(\.end))
        }
    }

    /// The desk clock. `ArrangementView` splits at the fold for us; before iOS 27.1, and in the headless
    /// renders, the two halves are placed by hand either side of the same band.
    @ViewBuilder private func tabletop(liveNow: Date, gap: FoldGap) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            ArrangementView {
                glance(liveNow: liveNow)
            } secondary: {
                tableBoard(liveNow: liveNow)
            }
            .arrangementViewStyle(.split)
        } else {
            tabletopByHand(liveNow: liveNow, gap: gap)
        }
        #else
        tabletopByHand(liveNow: liveNow, gap: gap)
        #endif
    }

    private func tabletopByHand(liveNow: Date, gap: FoldGap) -> some View {
        VStack(spacing: 0) {
            glance(liveNow: liveNow).frame(height: max(0, gap.end))
            Color.clear.frame(height: gap.start - gap.end)
            tableBoard(liveNow: liveNow)
        }
    }

    /// Flat in portrait, an iPhone, a narrow window: the same two halves, one under the other.
    private func stacked(liveNow: Date) -> some View {
        VStack(spacing: 0) {
            glance(liveNow: liveNow).fixedSize(horizontal: false, vertical: true)
            tableBoard(liveNow: liveNow)
        }
    }

    /// What is read from across the room: the clock, LEAVE HOME IN, the next train and the evening's track.
    private func glance(liveNow: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(liveNow: liveNow, sideBySide: true)
            HStack(alignment: .top, spacing: 16) {
                // First served, so LEAVE HOME IN keeps its glyphs beside its tiles and stays short enough
                // for the standing half; the next train takes what is left.
                leaveCard(to: leaveLeg?.to.name, liveNow: liveNow).layoutPriority(1)
                nextTrainCard(liveNow: liveNow)
            }
            .fixedSize(horizontal: false, vertical: true)
            track(liveNow: liveNow)
        }
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What lies on the table: the next trains and the ticker; the controls are in the bottom bar.
    private func tableBoard(liveNow: Date) -> some View {
        VStack(spacing: 0) {
            boardPanel(liveNow: liveNow, density: .folded)
                .padding(.horizontal, 24).padding(.vertical, 16)
            footer(liveNow: liveNow, tickerWidth: nil, showsCredit: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controls

    /// The journey, the walk and keep awake, in the bottom bar wherever the side column with its journey
    /// cards is gone. The wall is a page or a tab everywhere, so it has no Close.
    @ToolbarContentBuilder private func controls(inBottomBar: Bool) -> some ToolbarContent {
        if inBottomBar {
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) { bottomControls }
            #else
            ToolbarItemGroup(placement: .automatic) { bottomControls }
            #endif
        }
    }

    @ViewBuilder private var bottomControls: some View {
        Menu {
            Picker("Board", selection: $selection) {
                ForEach(journeys, id: \.journey) { journey in
                    Text("\(journey.leg.from.name) → \(journey.leg.to.name)").tag(Self.key(for: journey.journey))
                }
                Text(station?.name ?? "Nearest station").tag(Self.stationKey)
            }
        } label: {
            Label(headerTitle, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .labelStyle(.titleAndIcon)
        }
        if let leg = leaveLeg {
            Menu {
                Picker("Walk to the station", selection: walkMinutes(leg)) {
                    ForEach(1...30, id: \.self) { Text("\($0) min").tag($0) }
                }
            } label: {
                Label("\(walkMinutes(leg).wrappedValue) min", systemImage: "figure.walk")
                    .labelStyle(.titleAndIcon)
            }
        }
        Spacer()
        Button(keepAwake ? "Let the screen sleep" : "Keep the screen awake",
               systemImage: keepAwake ? "sun.max.fill" : "sun.max") { keepAwake.toggle() }
    }

    /// The stored walk to the leg's station; a new figure recounts LEAVE HOME IN straight away, and is
    /// from then on the user's own, which MapKit no longer overrides.
    private func walkMinutes(_ leg: Leg) -> Binding<Int> {
        Binding {
            walk ?? SharedSettings[walkMinutesFor: leg.from.id]
        } set: { minutes in
            SharedSettings[walkMinutesFor: leg.from.id] = minutes
            walk = minutes
        }
    }

    // MARK: Header

    private var headerCaption: String {
        if current != nil { return "DEPARTURES · YOUR JOURNEY" }
        return stationIsPinned ? "DEPARTURES · PINNED STATION" : "DEPARTURES · NEAREST STATION"
    }

    private var headerTitle: String {
        if let current { return "\(current.leg.from.name) → \(current.leg.to.name)" }
        return station?.name ?? "Nearest station"
    }

    /// The title and the clock on one line, or the clock under the title on a phone held upright.
    @ViewBuilder private func header(liveNow: Date, sideBySide: Bool) -> some View {
        if sideBySide {
            HStack(alignment: .bottom, spacing: 20) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                clock(liveNow: liveNow)
            }
        } else {
            title
            clock(liveNow: liveNow).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(headerCaption)
                    .font(.mono(13, weight: .semibold)).tracking(2.4)
            } icon: {
                Image(systemName: current == nil ? "dot.radiowaves.left.and.right" : "arrow.right")
                    .foregroundStyle(Color.amberText)
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(1).minimumScaleFactor(0.6)
            Text(headerTitle)
                .font(.system(size: 64, weight: .heavy)).foregroundStyle(Color.ink)
                .lineLimit(1).minimumScaleFactor(0.4)
        }
    }

    /// The day beside the clock where it fits, under it where the column is narrower.
    private func clock(liveNow: Date) -> some View {
        let day = Text(WallFormat.day.string(from: liveNow).uppercased())
            .font(.mono(14, weight: .semibold)).tracking(2)
            .foregroundStyle(Color.inkSecondary)
        let flaps = FlapTime(date: liveNow, digitColor: .ink, tileWidth: 52, tileHeight: 74,
                             tileColor: .wallClockTile, seamColor: .wallGround, cornerRadius: 9, colonColor: .inkSecondary)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 18) { day.padding(.bottom, 6); flaps }
            VStack(alignment: .trailing, spacing: 8) { flaps; day }
        }
    }

    // MARK: Glance

    /// The train the wall points at: tonight's soonest that still runs, else the morning's first.
    private func nextTrain(liveNow: Date) -> TrainDeparture? {
        BoardReading.nextUpcoming(shownState, after: liveNow)
            ?? shownTomorrow.first { !$0.isCancelled && $0.expectedDeparture > liveNow }
    }

    private func nextTrainCard(liveNow: Date) -> some View {
        let next = nextTrain(liveNow: liveNow)
        let countdown = next.map { wallCountdown(to: $0.expectedDeparture, from: liveNow) }
            .map { $0 == "now" ? "leaving now" : "in \($0)" } ?? ""
        // LEAVE HOME IN counts down to the first train you can still walk to; when that is not this one,
        // this one leaves before you could reach it. Only on a journey: the station board's next train is
        // on another line than the journey LEAVE HOME IN follows.
        let tooTight = current != nil && next != nil && walk != nil && shownLeave(liveNow: liveNow)?.leave.train != next
        return VStack(alignment: .leading, spacing: 14) {
            Text("NEXT TRAIN").font(.mono(12, weight: .bold)).tracking(2).foregroundStyle(Color.inkSecondary)
            if let next {
                FlapTime(date: next.expectedDeparture, digitColor: .amber, tileWidth: 44, tileHeight: 64,
                         tileColor: .wallClockTile, seamColor: .wallPanel, cornerRadius: 8, colonColor: .amberText)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let mode = next.mode { ModeChip(mode) }
                        Text([next.trainNumber.map { "N° \($0)" },
                              next.expectedArrival.map { "arr. \(WallFormat.time.string(from: $0))" }]
                            .compactMap(\.self).joined(separator: " · "))
                            .font(.mono(13, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    }
                    Text(countdown + (tooTight ? " · too tight to walk" : ""))
                        .font(.mono(15, weight: .bold)).foregroundStyle(Color.soon)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("No train to come").font(.mono(15, weight: .medium)).foregroundStyle(Color.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(Color.wallPanel, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }

    /// The evening on the rail, or once tonight is over the night up to the morning's first train.
    private func track(liveNow: Date) -> some View {
        let tonight = BoardReading.departures(shownState).filter { $0.expectedDeparture > liveNow }
        let morning = tonight.isEmpty ? shownTomorrow.first { !$0.isCancelled } : nil
        return TimeTrack(trains: morning == nil ? tonight : shownTomorrow, now: liveNow, axis: .horizontal,
                         minutesSpan: morning.map { Int($0.expectedDeparture.timeIntervalSince(liveNow) / 60) + 40 } ?? 200,
                         metrics: .board)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Board

    /// The rows' density, by the board's width: `.folded` drops the TRAIN column into each row's second
    /// line, so the board fits half a Duo or a narrow window without squeezing DESTINATION to nothing;
    /// `.small` also takes smaller time tiles, for an iPhone held upright.
    enum BoardDensity {
        case full, folded, small

        var tile: CGFloat { self == .small ? 20 : 25 }
        /// Four tiles, their gaps and the colon.
        var timeColumn: CGFloat { self == .small ? 102 : 126 }
        var inset: CGFloat { self == .small ? 14 : 22 }
    }

    /// `scrolls` false inside the iPhone's single scrolling column, which a nested scroll view would
    /// collapse.
    @ViewBuilder private func boardPanel(liveNow: Date, density: BoardDensity, scrolls: Bool = true) -> some View {
        let tomorrow = shownTomorrow
        VStack(spacing: 0) {
            boardHeaderRow(density: density)
            switch shownState {
            case .departures(let trains):
                scrolling(scrolls) { boardRows(trains, liveNow: liveNow, density: density) }
            case .noService:
                noServicePlate
                if !tomorrow.isEmpty { scrolling(scrolls) { boardRows([], liveNow: liveNow, density: density) }.frame(maxHeight: .infinity) }
            case .endOfService(let first):
                if tomorrow.isEmpty {
                    boardNote("moon.stars", "Last train gone · first tomorrow \(WallFormat.time.string(from: first))")
                } else {
                    scrolling(scrolls) { boardRows([], liveNow: liveNow, density: density) }
                }
            case .noTrains:
                boardNote("tram", "No departures")
            case .unavailable(let error):
                boardNote("exclamationmark.triangle", error.appDescription)
            }
        }
        .background(Color.wallPanel, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    @ViewBuilder private func scrolling(_ scrolls: Bool, @ViewBuilder _ content: () -> some View) -> some View {
        if scrolls { ScrollView { content() } } else { content() }
    }

    /// Every remaining train cancelled: the board's one hazard plate (a single cancelled row never gets it).
    private var noServicePlate: some View {
        ZStack {
            HazardBackground(variant: .widget)
            VStack(spacing: 10) {
                Text("NO SERVICE").font(.mono(34, weight: .heavy)).tracking(3).foregroundStyle(Color.amberText)
                Text("Every remaining train tonight is cancelled")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 36).padding(.vertical, 26)
            .background(Color.wallGround, in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardNote(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Color.inkSecondary)
            Text(text).font(.mono(18, weight: .medium)).foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardHeaderRow(density: BoardDensity) -> some View {
        HStack(spacing: 18) {
            Text("TIME").wallColumn(density.timeColumn, .leading)
            Text("DESTINATION").frame(maxWidth: .infinity, alignment: .leading)
            if density == .full {
                Text("TRAIN").wallColumn(150, .leading)
                Text("STATUS").wallColumn(132, .trailing)
            } else {
                Text("STATUS")
            }
        }
        .lineLimit(1)
        .font(.mono(11, weight: .semibold)).tracking(1.6).foregroundStyle(Color.inkSecondary)
        .padding(.horizontal, density.inset).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Color.white.opacity(0.07).frame(height: 1) }
    }

    private func boardRows(_ trains: [TrainDeparture], liveNow: Date, density: BoardDensity) -> some View {
        // Rows drop off as their train leaves, without waiting for the next fetch. The soonest one still to
        // run is the "next" — a cancelled row is never it — with the amber tint and a green countdown; once
        // tonight is over that is the morning's first, under the split. The station board answers the whole
        // service day, but each of its rows asks for its own via line, so it lists what the fixed-count
        // board did, and a morning as long as a journey's.
        let station = current == nil
        let upcoming = Array(trains.filter { $0.expectedDeparture > liveNow }.prefix(station ? SNCFClient.boardDeparturesPerRequest : .max))
        let tomorrow = Array(shownTomorrow.prefix(station ? 6 : .max))
        let next = upcoming.first { !$0.isCancelled } ?? tomorrow.first { !$0.isCancelled }
        return VStack(spacing: 0) {
            ForEach(Array(upcoming.enumerated()), id: \.offset) { _, train in
                row(train, isNext: train == next, isTomorrow: false, liveNow: liveNow, density: density)
            }
            if !tomorrow.isEmpty {
                TomorrowSplit(lastTonight: BoardReading.lastTonight(shownState), fontSize: 13, inset: 22)
                ForEach(Array(tomorrow.enumerated()), id: \.offset) { _, train in
                    row(train, isNext: train == next, isTomorrow: true, liveNow: liveNow, density: density)
                }
            }
        }
    }

    private func row(_ train: TrainDeparture, isNext: Bool, isTomorrow: Bool, liveNow: Date, density: BoardDensity) -> some View {
        VStack(spacing: 0) {
            WallBoardRow(train: train, isNext: isNext,
                         fallbackDestination: current?.leg.to.name ?? station?.name,
                         showsArrival: current != nil, isTomorrow: isTomorrow, liveNow: liveNow, density: density)
            Color.white.opacity(0.06).frame(height: 1)
        }
    }

    // MARK: Right column

    private func rightColumn(liveNow: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Always there, even with no train left to catch: a card that came and went shoved the whole
            // column up and down on every journey switch. Its tiles spin to "--" instead.
            leaveCard(to: leaveLeg?.to.name, liveNow: liveNow)
            journeysCaption
            ScrollView {
                VStack(spacing: 16) { journeyCards(liveNow: liveNow, width: nil) }
            }
        }
    }

    private var journeysCaption: some View {
        Text("YOUR JOURNEYS")
            .font(.mono(11, weight: .semibold)).tracking(1.6)
            .foregroundStyle(Color.inkSecondary).padding(.horizontal, 6).padding(.top, 4)
    }

    /// One card per saved journey, then the station's. `width` fixes each card for a horizontal row.
    @ViewBuilder private func journeyCards(liveNow: Date, width: CGFloat?) -> some View {
        ForEach(Array(journeys.enumerated()), id: \.offset) { _, journey in
            let key = Self.key(for: journey.journey)
            let selected = current?.journey == journey.journey
            Button { selection = key } label: {
                WallJourneyCard(leg: journey.leg, state: journey.state, tomorrow: journey.tomorrow,
                                liveNow: liveNow, selected: selected)
            }
            .buttonStyle(.plain)
            .frame(width: width)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        // Last, because the journeys are what a wall is mostly for; the station board is the one-off
        // "what leaves from here" view.
        Button { selection = Self.stationKey } label: {
            WallStationCard(name: station?.name, pinned: stationIsPinned, selected: current == nil)
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .accessibilityAddTraits(current == nil ? .isSelected : [])
    }

    /// The small line under the train time: where it goes, or why there is nothing to catch.
    private func leaveDetail(_ leave: LeaveBy?, tomorrow: Bool, to destination: String?) -> String {
        guard let destination else { return "no journey saved" }
        if leave != nil { return tomorrow ? "tomorrow · \(destination)" : destination }
        if case .endOfService(let first)? = journeys.first(where: { $0.leg == leaveLeg })?.state {
            return "first tomorrow \(WallFormat.time.string(from: first))"
        }
        return "none to \(destination) now"
    }

    /// What LEAVE HOME IN counts down to: the first of tonight's held trains you can still walk to, worked
    /// out again at every minute so a train missed meanwhile gives way at once; once none is left, the
    /// morning's first with the same walk. No request: the board and the morning are already held.
    private func shownLeave(liveNow: Date) -> (leave: LeaveBy, tomorrow: Bool)? {
        guard let walk, let board = journeys.first(where: { $0.leg == leaveLeg }) else { return nil }
        if let tonight = LiveLeaveBy.firstCatchable(in: BoardReading.departures(board.state), walk: walk, now: liveNow) {
            return (tonight, false)
        }
        return LiveLeaveBy.firstCatchable(in: board.tomorrow, walk: walk, now: liveNow).map { ($0, true) }
    }

    private func leaveCard(to destination: String?, liveNow: Date) -> some View {
        let shown = shownLeave(liveNow: liveNow)
        let leave = shown?.leave
        // The hero is a countdown until you must walk out, not a clock time, so it is two bare `FlapTile`s
        // rather than a `FlapTime` (which renders HH:MM) — the same tile, so it flips the same way each
        // minute. Past 99 minutes (the night before the first train) it counts whole hours instead.
        let minutes = leave.map { max(0, Int($0.leaveAt.timeIntervalSince(liveNow) / 60)) }
        let inHours = (minutes ?? 0) >= 100
        let digits = minutes.map { String(format: "%02d", inHours ? min(99, $0 / 60) : $0) } ?? "--"
        let trainTime = leave.map { WallFormat.time.string(from: $0.train.expectedDeparture) } ?? "--:--"
        let detail = leaveDetail(leave, tomorrow: shown?.tomorrow ?? false, to: destination)
        let tiles = VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(Array(digits.enumerated()), id: \.offset) { column, digit in
                    // A dark tile on the amber card, with the amber seam the mockup draws.
                    FlapTile(digit: digit, delay: .milliseconds(50 * column), tileWidth: 62, tileHeight: 88,
                             tileColor: .ground, seamColor: Color.amber.opacity(0.35), cornerRadius: 11)
                }
            }
            Text(inHours ? "H" : "MIN").font(.mono(15, weight: .bold)).tracking(2)
        }
        // Two glyphs with their numbers rather than a sentence: the train to catch, and the walk to it.
        // Both rows stay in every state (a dash in place of a number), so the card never changes size.
        let trainRow = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "tram.fill").font(.system(size: 20, weight: .semibold)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(trainTime).font(.mono(24, weight: .bold))
                Text(detail).font(.system(size: 14, weight: .semibold)).opacity(0.7)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        let walkRow = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "figure.walk").font(.system(size: 20, weight: .semibold)).frame(width: 26)
            Text(leave.map { "\($0.walkMinutes) min" } ?? "-- min").font(.mono(24, weight: .bold))
        }
        let glyphs = VStack(alignment: .leading, spacing: 14) { trainRow; walkRow }
        return VStack(alignment: .leading, spacing: 14) {
            Text("LEAVE HOME IN").font(.mono(12, weight: .bold)).tracking(2)
            // Beside the tiles where the card is wide enough; under them where it is not (half a Duo, the
            // desk clock), the train and the walk side by side so the card's width is not left empty;
            // stacked only where even that does not fit. The same pieces, never smaller.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 22) { tiles; glyphs }
                VStack(alignment: .leading, spacing: 14) {
                    tiles
                    HStack(alignment: .top, spacing: 28) { trainRow; walkRow }
                }
                VStack(alignment: .leading, spacing: 14) { tiles; glyphs }
            }
        }
        .foregroundStyle(Color.onAmber)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(Color.amber, in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(leave.map { "Leave home in \(inHours ? (minutes ?? 0) / 60 : (minutes ?? 0)) \(inHours ? "hours" : "minutes") for the \(trainTime) to \(destination ?? ""), \($0.walkMinutes) minute walk" }
                            ?? "No train to leave for: \(detail)")
    }

    // MARK: Footer

    /// `tickerWidth` ends INFO and its line there (a fold's near edge) and puts the credit on the far side;
    /// the desk clock's lying half has no room for the credit. The hazard block is inset from the edges so
    /// a display's rounded corner never clips it.
    private func footer(liveNow: Date, tickerWidth: CGFloat?, showsCredit: Bool = true) -> some View {
        let ticker = HStack(spacing: 0) {
            ZStack {
                HazardBackground(variant: .band, stripe: .amber, bandWidth: 10)
                Text("INFO").font(.mono(13, weight: .heavy)).tracking(2).foregroundStyle(Color.amberText)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.wallGround, in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(width: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 12)
            Text(disruptions)
                .font(.mono(16, weight: .medium)).foregroundStyle(Color.ink.opacity(0.85))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
        }
        .padding(.leading, 24)
        return HStack(spacing: 0) {
            if let tickerWidth {
                ticker.frame(width: max(0, tickerWidth))
                Spacer(minLength: 0)
            } else {
                ticker
            }
            if showsCredit {
                HStack(spacing: 8) {
                    Circle().fill(Color.soon).frame(width: 7, height: 7)
                    Text("Data © SNCF · \(WallFormat.time.string(from: liveNow))")
                        .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 28)
            }
        }
        .frame(height: 64)
        .background(Color.ground)
        .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1) }
    }

    /// The disruptions, one line. A journey lists its own board; the station board leads with the dead
    /// journeys, then its late and cancelled trains.
    private var disruptions: String {
        var parts: [String] = []
        let dead = current.map { [$0] } ?? journeys
        for journey in dead where journey.state == .noService {
            parts.append("\(journey.leg.from.name) → \(journey.leg.to.name): no service tonight, every remaining train cancelled")
        }
        if case .departures(let trains) = shownState {
            for train in trains {
                let name = train.direction ?? current?.leg.to.name ?? station?.name ?? "Train"
                let at = WallFormat.time.string(from: train.scheduledDeparture)
                if train.isCancelled {
                    parts.append("\(name) \(at) cancelled")
                } else if let delay = train.delayMinutes, delay >= 11 {
                    parts.append("\(name) \(at) running \(delay) min late")
                }
            }
        }
        return parts.isEmpty ? "No disruptions reported tonight." : parts.joined(separator: "   ·   ")
    }
}

// MARK: - Board row

/// Minutes until a departure as "6 min" / "1 h 36" / "now", the station hall's wording.
private func wallCountdown(to date: Date, from now: Date) -> String {
    HallFormat.relative(date, from: now)
}

private struct WallBoardRow: View {
    @Environment(\.bigScreenData) private var data
    let train: TrainDeparture
    let isNext: Bool
    let fallbackDestination: String?
    /// A journey row: the second line is the arrival and the trip time, which a station board lacks.
    let showsArrival: Bool
    /// A morning row under the split: "tomorrow" in place of a countdown hours long.
    let isTomorrow: Bool
    let liveNow: Date
    let density: WallModeView.BoardDensity
    @State private var via: [String] = []

    var body: some View {
        HStack(spacing: 18) {
            flap.wallColumn(density.timeColumn, .leading)
            destination.frame(maxWidth: .infinity, alignment: .leading)
            if density == .full {
                trainCell.wallColumn(150, .leading)
                status.wallColumn(132, .trailing)
            } else {
                // No column to line up with any more: the status takes only what it needs.
                status.fixedSize()
            }
        }
        .padding(.horizontal, density.inset).padding(.vertical, 15)
        .background(isNext ? Color.amber.opacity(0.06) : Color.clear)
        // The station board carries no stopping pattern, so each row asks for its own "via …" as it
        // appears — all rows at once rather than one after another, and cached by the provider.
        .task(id: train.vehicleJourneyID) {
            guard !showsArrival, let id = train.vehicleJourneyID else { return }
            via = await data.stationBoard.via(forVehicleJourneyID: id)
        }
    }

    /// The timetabled time as four flap tiles — amendments live in the status column, never the flap. A
    /// cancelled row goes grey, with the seam hidden (seam = tile colour) so it loses the split line.
    private var flap: some View {
        FlapTime(date: train.scheduledDeparture,
                 digitColor: train.isCancelled ? .inkSecondary : .amber,
                 tileWidth: density.tile, tileHeight: density.tile * 38 / 25, tileColor: .raised,
                 seamColor: train.isCancelled ? .raised : .wallGround, cornerRadius: density.tile / 5)
            .opacity(train.isCancelled ? 0.45 : 1)
    }

    private var secondLine: String {
        var parts: [String] = []
        if showsArrival {
            if let arrival = train.expectedArrival {
                parts.append("arrives \(WallFormat.time.string(from: arrival)) · \(wallCountdown(to: arrival, from: train.expectedDeparture))")
            }
        } else {
            parts.append(via.isEmpty ? "direct" : "via " + via.joined(separator: " · "))
        }
        // Without its own column, the train goes under the destination, as the desk-clock mockup draws it.
        let name = [train.mode, train.trainNumber].compactMap(\.self).joined(separator: " ")
        if density != .full, !name.isEmpty {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(train.direction ?? fallbackDestination ?? "—")
                .font(.system(size: 27, weight: .bold)).foregroundStyle(Color.ink)
                .strikethrough(train.isCancelled, color: Color.ink)
                .lineLimit(1)
            Text(secondLine)
                .font(.mono(12.5, weight: .medium)).foregroundStyle(Color.inkSecondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .opacity(train.isCancelled ? 0.55 : 1)
    }

    private var trainCell: some View {
        HStack(spacing: 8) {
            if let mode = train.mode { ModeChip(mode) }
            if let number = train.trainNumber {
                Text(number).font(.mono(14, weight: .medium)).foregroundStyle(Color.inkSecondary)
            }
        }
        .opacity(train.isCancelled ? 0.55 : 1)
    }

    @ViewBuilder private var status: some View {
        switch train.status {
        case .onTime:
            Text(isTomorrow ? "tomorrow" : wallCountdown(to: train.expectedDeparture, from: liveNow))
                .font(.mono(isNext ? 20 : 18, weight: isNext ? .bold : .medium))
                .foregroundStyle(isNext && !isTomorrow ? Color.soon : Color.inkSecondary)
        case .delayed, .severelyDelayed:
            VStack(alignment: .trailing, spacing: 3) {
                StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
                Text("leaves \(WallFormat.time.string(from: train.expectedDeparture))")
                    .font(.mono(12.5, weight: .medium)).foregroundStyle(train.status.tableauInk)
            }
        case .cancelled:
            StatusPill("CANCELLED", status: .cancelled)
        case .unknown:
            StatusPill("delay ?", status: .unknown)
        }
    }
}

// MARK: - Journey card

private struct WallJourneyCard: View {
    let leg: Leg
    let state: BoardState
    let tomorrow: [TrainDeparture]
    let liveNow: Date
    let selected: Bool

    private var noService: Bool { state == .noService }

    var body: some View {
        HStack(spacing: 14) {
            RoutePins(destination: .solid(noService ? .inkSecondary : .amber)).frame(width: 12, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.from.name).font(.system(size: 13)).foregroundStyle(Color.ink.opacity(0.7)).lineLimit(1)
                Text(leg.to.name).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .wallCard(selected: selected) { background }
    }

    // Only a dead journey carries the hazard; a single cancelled train never does (Tableau rule).
    @ViewBuilder private var background: some View {
        if noService {
            HazardBackground(variant: .widget)
        } else {
            Color.wallPanel
        }
    }

    @ViewBuilder private var trailing: some View {
        if noService {
            Text("NO SERVICE")
                .font(.mono(13, weight: .bold)).tracking(1.6).foregroundStyle(Color.amberText)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Color.wallGround, in: RoundedRectangle(cornerRadius: 8))
        } else if let (time, secondary) = headline {
            VStack(alignment: .trailing, spacing: 2) {
                Text(time).font(.mono(24, weight: .bold)).foregroundStyle(Color.amberText)
                secondary.font(.mono(12, weight: .medium))
            }
        }
    }

    /// The next departure time and a secondary line: its delay, or its arrival. Read against the live
    /// minute, like the board, so a departed train leaves the card too.
    private var headline: (String, Text)? {
        switch state {
        case .departures(let trains):
            let upcoming = trains.filter { $0.expectedDeparture > liveNow }
            guard let next = upcoming.first(where: { !$0.isCancelled }) ?? upcoming.first else {
                if let first = tomorrow.first(where: { !$0.isCancelled }) {
                    return (WallFormat.time.string(from: first.expectedDeparture), Text("first tomorrow").foregroundStyle(Color.inkSecondary))
                }
                return ("—", Text("no more trains").foregroundStyle(Color.inkSecondary))
            }
            let time = WallFormat.time.string(from: next.expectedDeparture)
            if next.status == .delayed || next.status == .severelyDelayed {
                let second = Text("+\(next.delayMinutes ?? 0) · leaves \(WallFormat.time.string(from: next.expectedDeparture))")
                    .foregroundStyle(next.status.tableauInk)
                return (time, second)
            }
            if let arrival = next.expectedArrival {
                return (time, Text("arrives \(WallFormat.time.string(from: arrival))").foregroundStyle(Color.inkSecondary))
            }
            return (time, Text("next").foregroundStyle(Color.inkSecondary))
        case .endOfService(let first):
            return (WallFormat.time.string(from: first), Text("first tomorrow").foregroundStyle(Color.inkSecondary))
        case .noTrains:
            return ("—", Text("no trains").foregroundStyle(Color.inkSecondary))
        case .unavailable(let error):
            return ("—", Text(error.terse).foregroundStyle(Color.inkSecondary))
        case .noService:
            return nil
        }
    }
}

/// The extra card that turns the wall back into a station board: the pinned station's name when there
/// is one, otherwise the nearest one's once the card has been picked (it is only looked up then).
private struct WallStationCard: View {
    let name: String?
    let pinned: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18)).foregroundStyle(Color.amberText)
                .frame(width: 12, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(pinned ? "Pinned station" : "Nearest station").font(.system(size: 13)).foregroundStyle(Color.ink.opacity(0.7))
                Text(name ?? "Station").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("every departure").font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
        }
        .wallCard(selected: selected) { Color.wallPanel }
    }
}

// MARK: - Keep awake

#if os(macOS)
/// Holds the macOS "keep the display awake" activity token for Wall mode. The Mac has no
/// `isIdleTimerDisabled`; `beginActivity` is the equivalent and must be balanced by `endActivity`.
@MainActor final class WallAwake {
    private var token: (any NSObjectProtocol)?

    func begin() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "Wall mode on display")
    }

    func end() {
        if let token { ProcessInfo.processInfo.endActivity(token); self.token = nil }
    }
}
#endif

private extension View {
    /// A fixed-width board column, so the header labels and the rows line up on one grid.
    func wallColumn(_ width: CGFloat, _ alignment: Alignment) -> some View {
        frame(width: width, alignment: alignment)
    }

    /// A YOUR JOURNEYS card: its ground, then the app's selection treatment when picked (amber 7 % over
    /// the ground, a 1.5 pt amber ring), like the Lanes and station-hall selections.
    func wallCard(selected: Bool, @ViewBuilder background: () -> some View) -> some View {
        padding(.horizontal, 18).padding(.vertical, 16)
            .background {
                ZStack {
                    background()
                    if selected { Color.amber.opacity(0.07) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(selected ? Color.amber : Color.white.opacity(0.05), lineWidth: selected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    /// Enter / leave the display-awake state. One release point: navigating to any other route removes
    /// the view, which lands on `.onDisappear`.
    func keepScreenAwake(enter: @escaping () -> Void, leave: @escaping () -> Void) -> some View {
        onAppear(perform: enter).onDisappear(perform: leave)
    }
}

// MARK: - Wall palette & formats

private extension Color {
    /// The three wall-only shades, a touch darker than the app and with no Tableau token.
    static let wallGround = Color(red: 10 / 255, green: 11 / 255, blue: 12 / 255)   // #0A0B0C
    static let wallPanel = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)    // #121316
    static let wallClockTile = Color(red: 28 / 255, green: 30 / 255, blue: 34 / 255) // #1C1E22
}

private enum WallFormat {
    /// 24-hour "HH:mm", matching the split-flap tiles whatever the device clock.
    static let time = SNCFTime.hhmmFormatter
    /// "Thu 15 Oct", upper-cased by the caller.
    static let day = SNCFTime.formatter("EEE d MMM")
}

#Preview("Wall mode") {
    WallModeView(now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .frame(width: 1376, height: 1032)
}

#Preview("Wall mode · late evening") {
    WallModeView(now: BigScreenFixtures.lateNow)
        .environment(BigScreenModel())
        .environment(\.bigScreenData, .fakeLateEvening)
        .frame(width: 1376, height: 1032)
}
