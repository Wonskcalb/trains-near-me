import SNCFCore
import SwiftUI

/// Station hall — the centre journey board and the right-hand train inspector of Main.dc.html. The
/// sidebar lives in `BigScreenRoot`; this is the two columns the detail area fills. Everything comes
/// through `BigScreenData` (live in the app, the mockup in previews), never `SNCFClient`. Follows the
/// appearance setting: its times are `amberText`, so on the Timetable (light) palette they turn to ink
/// rather than putting amber text on paper.
struct StationHallView: View {
    /// A frozen anchor for the `#Preview` and the screenshot build; nil follows the real clock.
    private let frozenNow: Date?
    /// Set when the board is one column of the Duo's board | train split, showing this saved journey: the
    /// inspector moves to the split's detail column and the header controls to the toolbar.
    private let journey: JourneyConfiguration?

    init(now: Date? = nil, journey: JourneyConfiguration? = nil) {
        frozenNow = now
        self.journey = journey
    }

    // The hero's "in N min" and the board's countdowns must move on their own: `.everyMinute` re-draws
    // the board at each minute change. The board's state survives the tick (same view identity), and its
    // fetch is keyed on the journey and ⌘R, not on the time, so a tick never costs a request.
    var body: some View {
        TimelineView(.everyMinute) { context in
            StationHallBoard(journey: journey, now: frozenNow ?? context.date, isFrozen: frozenNow != nil)
        }
    }
}

private struct StationHallBoard: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model

    @State private var boards: [JourneyBoard] = []
    /// The unsaved journey `model.temporaryLeg` names, fetched on its own; nil on a saved journey.
    @State private var temporary: JourneyBoard?
    /// Whether the temporary journey is already among the saved ones (it was just added, or was all along).
    @State private var temporarySaved = false
    @State private var summary: ServiceDaySummary?
    /// The train the inspector shows and the board rings; nil closes the inspector.
    @State private var selected: TrainDeparture?
    @State private var stops: [TripStop] = []
    /// Space-pinned trains: local to the screen, not persisted anywhere.
    @State private var pins: Set<TrainDeparture> = []
    @FocusState private var boardFocused: Bool
    /// Too narrow for the inspector beside the board: a picked train opens it as a sheet.
    @State private var narrow = false
    @State private var inspectorSheet = false
    /// The "Add a journey" sheet, offered when nothing is saved.
    @State private var adding = false
    /// The first round has landed, so an empty list means nothing is saved, not "still loading".
    @State private var loaded = false

    /// The saved journey this board shows as a split column; nil is the full station hall.
    let journey: JourneyConfiguration?
    private var isColumn: Bool { journey != nil }

    /// The minute being drawn: the timeline's, or a frozen `BigScreenFixtures.now` from the `#Preview` and
    /// the screenshot build so the mockup lines up.
    let now: Date
    /// A preview: the requests read `now` too, instead of the real clock.
    let isFrozen: Bool

    /// The clock a request is asked at: read when it starts, the same way the sidebar reads it, so the two
    /// land in one boards-memo round instead of a minute boundary apart.
    private var requestTime: Date { isFrozen ? now : Date() }

    private var board: JourneyBoard? {
        if model.temporaryLeg != nil, !isColumn { return temporary }
        if let journey { return boards.first { $0.journey == journey } }
        guard !boards.isEmpty else { return nil }
        return boards[min(model.selectedJourney, boards.count - 1)]
    }

    private var trains: [TrainDeparture] { BoardReading.departures(board?.state) }
    private var tomorrow: [TrainDeparture] { board?.tomorrow ?? [] }
    /// Every row the board lists, tonight's then tomorrow's: what ↑↓ walks.
    private var rows: [TrainDeparture] { trains + tomorrow }
    /// The train the hero and the NEXT tag point at: tonight's next, or tomorrow's first once tonight is over.
    private var heroTrain: TrainDeparture? { BoardReading.nextUpcoming(board, after: now) }

    var body: some View {
        Group {
            if isColumn {
                column
            } else {
                HStack(spacing: 0) {
                    center
                        .frame(maxWidth: .infinity)
                    // Under 820 pt (an iPad in portrait) a 360 pt inspector beside the board left it too
                    // narrow for its own header; the picked train opens as a sheet there instead.
                    if !narrow {
                        Divider().overlay(Color.ink.opacity(0.06))
                        inspector
                            .frame(width: 360)
                    }
                }
                .onGeometryChange(for: Bool.self) { $0.size.width < 820 } action: { narrow = $0 }
                // Keyed on the train so a quick ↑↓ run cancels the lookups it has already left behind.
                .task(id: selected) { await loadStops() }
                .sheet(isPresented: $inspectorSheet) {
                    inspector.presentationDetents([.medium, .large])
                }
            }
        }
        .background(Color.ground.ignoresSafeArea())
        .task(id: reloadKey) { await load() }
        .sheet(isPresented: $adding) {
            EditJourneyView { SavedJourneys.save(SharedSettings.favorites + [$0]) }
        }
    }

    /// The board alone, its pick handed to the split's detail column through the shell model, which is
    /// where that column's inspector reads it (and fetches the stops).
    @ViewBuilder private var column: some View {
        let board = center
            .onChange(of: selected) { publishSelection() }
            .onAppear { publishSelection() }
        #if os(iOS)
        board.modifier(JourneyToolbar(leg: self.board?.leg, swap: reverseJourney.map { reverse in { model.journeyPath = [reverse] } }))
        #else
        board
        #endif
    }

    private func publishSelection() {
        guard let leg = board?.leg else { return }
        model.detailTrain = selected.map { PickedTrain(train: $0, leg: leg) }
    }

    /// The saved journey running the other way, which is all a column's Swap can open.
    private var reverseJourney: JourneyConfiguration? {
        guard let leg = board?.leg else { return nil }
        return boards.first { $0.leg.from.id == leg.to.id && $0.leg.to.id == leg.from.id }?.journey
    }

    /// Re-fetch when the picked journey or ⌘R changes.
    private var reloadKey: String {
        "\(journey.map { "\($0.stationA.id)>\($0.stationB.id)" } ?? "\(model.selectedJourney)")-\(model.refreshTick)-\(model.temporaryLeg.map { "\($0.from.id)>\($0.to.id)" } ?? "")"
    }

    private func load() async {
        let at = requestTime
        if let leg = model.temporaryLeg, !isColumn {
            temporarySaved = Self.isSaved(leg)
            temporary = await data.journeyBoards.board(for: leg, at: at)
            // The service-day footer costs two more requests, too many for a journey opened for a glance.
            summary = nil
            keepOrResetSelection()
            return
        }
        boards = await data.journeyBoards.boards(at: at)
        loaded = true
        if let leg = board?.leg { summary = await data.serviceDay.summary(for: leg, at: at) } else { summary = nil }
        keepOrResetSelection()
    }

    /// A reload keeps the train the user picked while it is still listed (matched by identity, since its
    /// delay may have changed the row); otherwise, or on another journey, the next upcoming train.
    private func keepOrResetSelection() {
        if let picked = selected.flatMap({ TrainIdentity($0) }),
           let still = rows.first(where: { TrainIdentity($0) == picked }) {
            selected = still
        } else {
            selected = heroTrain ?? rows.first
        }
    }

    private func loadStops() async {
        // Cleared first: otherwise the inspector draws the previous train's run under the new train's
        // number until the request lands.
        stops = []
        guard let id = selected?.vehicleJourneyID else { return }
        stops = (try? await data.trainStops.stops(forVehicleJourneyID: id)) ?? []
    }

    // MARK: Centre board

    private var center: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !isColumn { chips }
                switch board?.state {
                case .departures:
                    hero
                    boardTable
                    if !isColumn { footer }
                case .noService:
                    noService
                    // The dead night keeps its plate; the morning still runs, so it follows the split.
                    if !tomorrow.isEmpty { boardTable }
                case .endOfService(let first):
                    if tomorrow.isEmpty {
                        EndOfServiceCard(first: first)
                    } else {
                        hero
                        boardTable
                        if !isColumn { footer }
                    }
                case .unavailable(let error):
                    stateCard("Board unavailable", error.appDescription)
                case .noTrains, nil:
                    if loaded, boards.isEmpty, model.temporaryLeg == nil, !isColumn {
                        noJourney
                    } else {
                        stateCard("No board", "Nothing to show for this journey right now.")
                    }
                }
            }
            .padding(.horizontal, isColumn ? 16 : 32).padding(.top, isColumn ? 8 : 28).padding(.bottom, 24)
        }
        // A focusable board so a hardware keyboard can drive it; ⌘-keys stay on the shell.
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        .onAppear { boardFocused = true }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.space) { togglePin(); return .handled }
    }

    private var header: some View {
        // The controls drop under the title where the board is too narrow for both on one line.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                headerTitle
                Spacer(minLength: 0)
                headerControls
            }
            VStack(alignment: .leading, spacing: 12) {
                headerTitle
                headerControls
            }
        }
    }

    /// Nothing saved yet: say so, and offer the + the sidebar has, rather than an empty "No board".
    private var noJourney: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No saved journey").font(.headline).foregroundStyle(Color.ink)
                Text("Save one to see its next direct trains here.").font(.subheadline).foregroundStyle(Color.inkSecondary)
            }
            Button { adding = true } label: {
                Label("Add a journey", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.onAmber)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.amber, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var headerTitle: some View {
            HStack(alignment: .center, spacing: 14) {
                RoutePins(destination: .solid(.amber), originDiameter: 10, destinationDiameter: 14, lineWidth: 2.5)
                    .frame(width: 14, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(board?.leg.from.name ?? " ").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.ink.opacity(0.7))
                    Text(board?.leg.to.name ?? "Journey").font(.system(size: isColumn ? 28 : 38, weight: .bold)).foregroundStyle(Color.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var headerControls: some View {
            if isColumn {
                // A column has no room for a chips row and its controls are in the toolbar, so the chips
                // stack where the controls were.
                VStack(alignment: .trailing, spacing: 6) { chipList }
                    .padding(.top, 4)
            } else if let leg = model.temporaryLeg {
                temporaryControls(leg)
            } else {
                controls
            }
    }

    private static func isSaved(_ leg: Leg) -> Bool {
        SharedSettings.favorites.contains { $0.stationA.id == leg.from.id && $0.stationB.id == leg.to.id }
    }

    /// A journey opened unsaved (a station-map lane, or Swap with no saved way back): back to where it was
    /// opened from, and the one way to keep it.
    private func temporaryControls(_ leg: Leg) -> some View {
        HStack(spacing: 8) {
            Button {
                guard !temporarySaved else { return }
                SavedJourneys.save(SharedSettings.favorites + [JourneyConfiguration(stationA: leg.from, stationB: leg.to)])
                temporarySaved = true
            } label: {
                Label(temporarySaved ? "In my journeys" : "Add to my journeys", systemImage: temporarySaved ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.raised, in: Capsule())
                    .overlay(Capsule().stroke(Color.ink.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityValue(temporarySaved ? "Saved" : "Not saved")
            roundButton("chevron.backward", label: "Back") { model.closeTemporary() }
        }
        .padding(.top, 4)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            // Board | Lanes: Board is here; Lanes drives the shell route.
            HStack(spacing: 0) {
                segment("Board", selected: true) {}
                segment("Lanes", selected: false) { model.select(.lanes) }
            }
            .padding(3).background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ink.opacity(0.06), lineWidth: 1))

            roundButton("arrow.up.arrow.down", label: "Swap direction") { swapDirection() }
            roundButton("arrow.up.left.and.arrow.down.right", label: "Open in Wall mode") { model.select(.wall) }
        }
        .padding(.top, 4)
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).fixedSize()
                .foregroundStyle(selected ? Color.ink : Color.ink.opacity(0.7))
                .padding(.horizontal, 14).frame(height: 34)
                .background(selected ? Color.ground.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Color.raised.opacity(0.72), in: Circle())
                .overlay(Circle().stroke(Color.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The saved reverse journey when there is one; otherwise the way back opens unsaved, as a station-map
    /// lane does, with the one button that keeps it.
    private func swapDirection() {
        guard let leg = board?.leg else { return }
        if let reverse = boards.firstIndex(where: { $0.leg.from.id == leg.to.id && $0.leg.to.id == leg.from.id }) {
            model.select(journey: reverse)
        } else {
            model.open(temporary: Leg(from: leg.to, to: leg.from))
        }
    }

    private var chips: some View {
        HStack(spacing: 8) { chipList }
    }

    @ViewBuilder private var chipList: some View {
        Group {
            chip("DIRECT ONLY", color: Color.ink.opacity(0.85), fill: Color.raised)
            if model.temporaryLeg != nil {
                if !temporarySaved { chip("NOT SAVED", color: Color.ink.opacity(0.85), fill: Color.raised) }
            } else if let journey = board?.journey {
                chip(HallFormat.directionCapsChip(journey), color: Color.ink.opacity(0.85), fill: Color.raised)
            }
            // Real time, so read off the live board rather than the day's cached summary. Not in a column: it
            // has no room for a third chip, and the delayed rows say the same thing right under it.
            if !isColumn, case let disrupted = trains.filter(\.isRunningLate).count, disrupted > 0 {
                chip("\(disrupted) DISRUPTED TONIGHT", color: Color.caution, fill: Color.cautionBg)
            }
        }
    }

    private func chip(_ text: String, color: Color, fill: Color) -> some View {
        Text(text).font(.mono(11, weight: .semibold)).tracking(1.1).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(fill, in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        if let next = heroTrain {
            let isTomorrow = BoardReading.isTomorrow(next, after: now)
            VStack(alignment: .leading, spacing: 16) {
                if isColumn {
                    // Half a portrait Duo is 334 pt: the flaps shrink before the words start to truncate.
                    ViewThatFits(in: .horizontal) {
                        heroRow(next, isTomorrow: isTomorrow, tile: 34)
                        heroRow(next, isTomorrow: isTomorrow, tile: 26)
                    }
                } else {
                    heroRow(next, isTomorrow: isTomorrow, tile: 46)
                }
                // Tonight over, the track stretches to the morning's first train rather than drawing hours of
                // empty rail up to the 200-minute mark and stopping short of it.
                TimeTrack(trains: isTomorrow ? tomorrow : trains, now: now, axis: .horizontal,
                          minutesSpan: isTomorrow ? Int(next.expectedDeparture.timeIntervalSince(now) / 60) + 40 : 200,
                          length: isColumn ? nil : 672, metrics: .board)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, isColumn ? 16 : 22).padding(.top, isColumn ? 16 : 20).padding(.bottom, 14)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.05), lineWidth: 1))
        }
    }

    private func heroRow(_ next: TrainDeparture, isTomorrow: Bool, tile: CGFloat) -> some View {
        HStack(spacing: isColumn ? 14 : 22) {
            FlapTime(date: next.expectedDeparture, tileWidth: tile, tileHeight: tile * 66 / 46,
                     cornerRadius: tile / 5, colonColor: .amberText)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(isTomorrow ? "FIRST TRAIN TOMORROW" : "NEXT TRAIN") · ARRIVES \(next.expectedArrival.map(HallFormat.hm) ?? "—")")
                    .font(.mono(11, weight: .semibold)).tracking(1.4).foregroundStyle(Color.inkSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    if let mode = next.mode { ModeChip(mode) }
                    Text(HallFormat.numberAndDuration(next)).font(.mono(13)).foregroundStyle(Color.inkSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(isTomorrow ? "tomorrow · \(HallFormat.inWords(next.expectedDeparture, from: now))"
                                : HallFormat.inWords(next.expectedDeparture, from: now))
                    .font(.mono(15, weight: .semibold)).foregroundStyle(isTomorrow ? Color.inkSecondary : Color.soon)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            // In a column, watching is the detail column's toolbar action, one tap on the train.
            if !isColumn, let leg = board?.leg { RemindButton(train: next, leg: leg) }
        }
    }

    // MARK: Board table

    private var boardTable: some View {
        let longest = rows.compactMap(\.duration).max() ?? 1
        let next = heroTrain
        return VStack(spacing: 0) {
            if !isColumn { BoardTableHeader() }
            ForEach(Array(trains.enumerated()), id: \.offset) { index, train in
                boardRow(train, next: next, longest: longest, tomorrow: false)
                if index < trains.count - 1 { Divider().overlay(Color.ink.opacity(0.07)) }
            }
            if !tomorrow.isEmpty {
                TomorrowSplit(lastTonight: BoardReading.lastTonight(board?.state) ?? summary?.lastTonight)
                ForEach(Array(tomorrow.enumerated()), id: \.offset) { index, train in
                    if index > 0 { Divider().overlay(Color.ink.opacity(0.07)) }
                    boardRow(train, next: next, longest: longest, tomorrow: true)
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.05), lineWidth: 1))
    }

    private func boardRow(_ train: TrainDeparture, next: TrainDeparture?, longest: TimeInterval, tomorrow: Bool) -> some View {
        Button { select(train) } label: {
            BoardRow(train: train, now: now, longestTrip: longest, isNext: train == next,
                     isSelected: train == selected, isPinned: pins.contains(train), isTomorrow: tomorrow, isCompact: isColumn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(train == selected ? .isSelected : [])
    }

    private var footer: some View {
        HStack {
            Text(summary.map { "LAST TRAIN TONIGHT \($0.lastTonight.map(HallFormat.hm) ?? "—") · FIRST TOMORROW \($0.firstTomorrow.map(HallFormat.hm) ?? "—")" } ?? " ")
            Spacer(minLength: 0)
            Text("↑↓ to pick a train · Space to pin")
        }
        .font(.mono(12)).foregroundStyle(Color.inkSecondary).padding(.horizontal, 4)
    }

    private var noService: some View {
        HazardBackground(variant: .band)
            .frame(height: tomorrow.isEmpty ? 260 : 160)
            .overlay {
                VStack(spacing: 5) {
                    Text("NO SERVICE").font(.mono(30, weight: .heavy)).tracking(3).foregroundStyle(Color.ink)
                    Text("Every train of the day is cancelled").font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .background(Color.ground, in: RoundedRectangle(cornerRadius: 16))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            // The hazard and its black plate are a dark surface by design, as on the widget, whatever the theme.
            .environment(\.colorScheme, .dark)
    }

    private func stateCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Color.ink)
            Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let train = selected, let leg = board?.leg {
            TrainInspector(train: train, leg: leg, stops: stops, now: now) { selected = nil; inspectorSheet = false }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "tram").font(.system(size: 36)).foregroundStyle(Color.inkSecondary)
                Text("Select a train").font(.headline).foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ground)
        }
    }

    // MARK: Selection & keyboard

    private func select(_ train: TrainDeparture) {
        selected = train
        if narrow { inspectorSheet = true }
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let current = selected.flatMap { rows.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), rows.count - 1)
        select(rows[next])
    }

    private func togglePin() {
        guard let train = selected else { return }
        if pins.contains(train) { pins.remove(train) } else { pins.insert(train) }
    }
}

/// The widget's end-of-service treatment: the fixed night sky and the moon, the first train in amber mono.
/// Fixed dark whatever the scheme, so the text on it stays light. Shared with the station board.
struct EndOfServiceCard: View {
    let first: Date

    var body: some View {
        HStack(spacing: 16) {
            NightMoon(size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("End of service").font(.headline).foregroundStyle(.white)
                (Text("First train at ") + Text(HallFormat.hm(first)).font(.mono(15, weight: .bold)).foregroundStyle(Color.amber))
                    .font(.subheadline).foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background { NightSky() }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

/// Where tonight's board stops and tomorrow's first trains begin, shared by every journey view. A real
/// stretch of night sky, roomy enough to read as the evening's full stop rather than one more row, so the
/// morning under it reads as a new start. Fixed dark with light text, so it holds on paper and on the board.
struct TomorrowSplit: View {
    let lastTonight: Date?
    var fontSize: CGFloat = 11.5
    /// Matches the host's row inset, so the moon lines up with the times under it.
    var inset: CGFloat = 20

    static let navy = Color(red: 0.10, green: 0.13, blue: 0.28)

    var body: some View {
        HStack(spacing: fontSize * 1.3) {
            NightMoon(size: fontSize * 3.2)
            VStack(alignment: .leading, spacing: fontSize * 0.35) {
                Text("End of service")
                    .font(.system(size: fontSize * 1.6, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.mono(fontSize, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, minHeight: fontSize * 7.5, alignment: .leading)
        .background(NightSky())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("End of service" + (lastTonight.map { ", last train \(HallFormat.hm($0))" } ?? "") + ". Tomorrow:")
        .accessibilityAddTraits(.isHeader)
    }

    private var detail: String {
        guard let lastTonight else { return "TOMORROW ↓" }
        return "LAST \(HallFormat.hm(lastTonight)) · TOMORROW ↓"
    }
}

/// The night gradient with a scatter of stars. The stars come from a fixed seed, so every render (and
/// every reload) shows the same sky; it is one static `Canvas`, so it costs nothing between frames.
struct NightSky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [TomorrowSplit.navy, Color(red: 0.04, green: 0.05, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var seed: UInt64 = 0x5EED_2026
                func next() -> Double {
                    // A tiny LCG: deterministic, no Foundation randomness, so the sky never shuffles.
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return Double(seed >> 11) / Double(1 << 53)
                }
                let count = Int(size.width * size.height / 900)
                for _ in 0..<min(count, 400) {
                    let x = next() * size.width, y = next() * size.height
                    let r = 0.4 + next() * next() * 1.2
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.white.opacity(0.25 + next() * 0.6)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A pale crescent with a soft glow, the night card's moon.
struct NightMoon: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: size))
            .foregroundStyle(Color(red: 1, green: 0.93, blue: 0.75))
            .shadow(color: Color(red: 1, green: 0.85, blue: 0.5).opacity(0.55), radius: size * 0.35)
            .accessibilityHidden(true)
    }
}

// MARK: - Board table rows

/// The table's fixed columns, grown with Dynamic Type so a larger mono time never clips. Header and rows
/// each hold one, scaled from the same base, so they stay on one grid.
private struct BoardColumns: DynamicProperty {
    @ScaledMetric(relativeTo: .body) var departArrive: CGFloat = 172
    @ScaledMetric(relativeTo: .body) var train: CGFloat = 150
    @ScaledMetric(relativeTo: .body) var status: CGFloat = 128
}

private struct BoardTableHeader: View {
    private let columns = BoardColumns()

    var body: some View {
        HStack(spacing: 14) {
            cell("DEPART → ARRIVE", width: columns.departArrive)
            cell("TRAIN", width: columns.train)
            Text("TIME ON BOARD").frame(maxWidth: .infinity, alignment: .leading)
            Text("STATUS").frame(width: columns.status, alignment: .trailing)
        }
        .font(.mono(10.5, weight: .semibold)).tracking(1.3).foregroundStyle(Color.inkSecondary)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().overlay(Color.ink.opacity(0.07)) }
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .leading)
    }
}

/// One journey row: departure → arrival, the train, a duration bar, and the status. The amber tint and
/// leading bar mark the selected row.
private struct BoardRow: View {
    let train: TrainDeparture
    let now: Date
    let longestTrip: TimeInterval
    let isNext: Bool
    let isSelected: Bool
    let isPinned: Bool
    /// A morning row under the split: its countdown reads "tomorrow", hours away being no use.
    var isTomorrow = false
    /// A split column's row (the Duo's board | train): no time-on-board bar, and the train number only
    /// while the column has room for it, so the status never truncates.
    var isCompact = false
    private let columns = BoardColumns()

    var body: some View {
        Group {
            if isCompact {
                HStack(spacing: 12) {
                    departArrive.fixedSize()
                    ViewThatFits(in: .horizontal) {
                        trainCell(withNumber: true)
                        trainCell(withNumber: false)
                        // Half a portrait Duo (334 pt): the times and the status are what must fit.
                        Color.clear.frame(width: 0, height: 0)
                    }
                    Spacer(minLength: 0)
                    // Sized first, so the train cell is what gives way, never the status.
                    status.fixedSize()
                }
                .padding(.horizontal, 16)
            } else {
                HStack(spacing: 14) {
                    departArrive.frame(width: columns.departArrive, alignment: .leading)
                    trainCell.frame(width: columns.train, alignment: .leading)
                    onBoard.frame(maxWidth: .infinity, alignment: .leading)
                    status.frame(width: columns.status, alignment: .trailing)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 14)
        .selectedRowBackground(isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The row as one sentence: "17:42 to 18:07, TER 17653, next, in 2 min" / "18:12 to 18:36, plus 12, leaves 18:24".
    private var spoken: String {
        var parts = [HallFormat.hm(train.scheduledDeparture) + (train.scheduledArrival.map { " to \(HallFormat.hm($0))" } ?? "")]
        parts.append([train.mode, train.trainNumber].compactMap { $0 }.joined(separator: " "))
        if isPinned { parts.append("pinned") }
        switch train.status {
        case .onTime: parts.append((isNext ? "next, " : "") + (isTomorrow ? "tomorrow" : "in \(HallFormat.relative(train.expectedDeparture, from: now))"))
        case .delayed, .severelyDelayed: parts.append("plus \(train.delayMinutes ?? 0), leaves \(HallFormat.hm(train.expectedDeparture))")
        case .cancelled: parts.append("cancelled")
        case .unknown: parts.append("delay unknown")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var departArrive: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(HallFormat.hm(train.scheduledDeparture))
                .font(.mono(22, weight: .bold))
                .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.amberText)
                .strikethrough(train.isCancelled)
            if let arrival = train.scheduledArrival {
                DashLine().frame(width: 16, height: 2)
                Text(HallFormat.hm(arrival)).font(.mono(15)).foregroundStyle(Color.ink.opacity(0.85))
                    .strikethrough(train.isCancelled)
            }
        }
        .opacity(train.isCancelled ? 0.6 : 1)
    }

    private var trainCell: some View { trainCell(withNumber: true) }

    private func trainCell(withNumber: Bool) -> some View {
        HStack(spacing: 7) {
            if isPinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Color.amberText) }
            if let mode = train.mode { ModeChip(mode) }
            if withNumber, let number = train.trainNumber {
                Text(isCompact ? number : "N° \(number)").font(.mono(12.5)).foregroundStyle(Color.inkSecondary)
            }
        }
        .opacity(train.isCancelled ? 0.6 : 1)
    }

    @ViewBuilder private var onBoard: some View {
        if train.isCancelled {
            Text("—").font(.mono(12.5)).foregroundStyle(Color.inkSecondary.opacity(0.7))
        } else if let duration = train.duration {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.sleeper).frame(height: 4)
                        Capsule().fill(Color.rail).frame(width: geo.size.width * min(1, duration / longestTrip), height: 4)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(width: 100, height: 14)
                Text("\(Int(duration / 60)) min").font(.mono(12.5)).foregroundStyle(Color.inkSecondary)
            }
        } else {
            Text("—").font(.mono(12.5)).foregroundStyle(Color.inkSecondary.opacity(0.7))
        }
    }

    @ViewBuilder private var status: some View {
        switch train.status {
        case .onTime:
            let relative = isTomorrow ? "tomorrow" : HallFormat.relative(train.expectedDeparture, from: now)
            if isNext {
                HStack(spacing: 8) {
                    Text("NEXT").font(.mono(10, weight: .bold)).tracking(1.2).foregroundStyle(Color.onAmber)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.amber, in: RoundedRectangle(cornerRadius: 5))
                    Text(relative).font(.mono(13, weight: .semibold)).foregroundStyle(isTomorrow ? Color.inkSecondary : Color.soon)
                }
            } else {
                Text(relative).font(.mono(13)).foregroundStyle(Color.inkSecondary)
            }
        case .delayed, .severelyDelayed:
            // One line, the amended time beside the pill: stacking "leaves 18:24" under it made a delayed row
            // taller than every other. The time in the status colour already reads as "now leaves at".
            HStack(spacing: 6) {
                Text(HallFormat.hm(train.expectedDeparture)).font(.mono(12.5, weight: .semibold))
                    .foregroundStyle(train.status.tableauInk)
                StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
            }
            .fixedSize()
        case .cancelled:
            StatusPill("CANCELLED", status: .cancelled)
        case .unknown:
            StatusPill("delay ?", status: .unknown)
        }
    }
}

/// A dashed connector between a departure and its arrival.
private struct DashLine: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.inkSecondary.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .accessibilityHidden(true)
    }
}

/// The hero's "Remind me" button, mirroring the watch state through `data.watching`. Watches the train
/// itself, not just its identity, so the reminder is scheduled and the first delay change is measured.
struct RemindButton: View {
    @Environment(\.bigScreenData) private var data
    let train: TrainDeparture
    let leg: Leg
    @State private var watched = false

    private var identity: TrainIdentity? { TrainIdentity(train, calendar: SNCFTime.calendar) }

    var body: some View {
        Button {
            guard let identity else { return }
            Task {
                if watched { await data.watching.unwatch(identity) } else { await data.watching.watch(train, to: leg) }
                watched = await data.watching.isWatched(identity)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: watched ? "bell.fill" : "bell").font(.system(size: 15)).foregroundStyle(Color.amberText)
                Text(watched ? "Reminding" : "Remind me").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 16).frame(height: 44)
            .background(Color.raised, in: Capsule())
            .overlay(Capsule().stroke(Color.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(identity == nil)
        .accessibilityValue(watched ? "On" : "Off")
        .task(id: identity) { if let identity { watched = await data.watching.isWatched(identity) } }
    }
}

// MARK: - Reading a board

/// Small readers over `BoardState`, shared by the sidebar and the centre so "the next train" means one
/// thing everywhere.
enum BoardReading {
    static func departures(_ state: BoardState?) -> [TrainDeparture] {
        if case .departures(let trains) = state { return trains }
        return []
    }

    /// The soonest train that has not left and is not cancelled — the one the hero, the NEXT tag and the
    /// sidebar times all point at.
    static func nextUpcoming(_ state: BoardState?, after now: Date) -> TrainDeparture? {
        departures(state).first { !$0.isCancelled && $0.expectedDeparture > now }
    }

    /// Tonight's next, or once tonight is over the morning's first: what a journey view leads with.
    static func nextUpcoming(_ board: JourneyBoard?, after now: Date) -> TrainDeparture? {
        nextUpcoming(board?.state, after: now) ?? board?.tomorrow.first { !$0.isCancelled && $0.expectedDeparture > now }
    }

    /// The last train still running tonight, for the split's "LAST 22:42"; nil once the board holds none.
    static func lastTonight(_ state: BoardState?) -> Date? {
        departures(state).last { !$0.isCancelled }?.scheduledDeparture
    }

    /// Whether a train belongs to the next 03:00 service day rather than tonight's.
    static func isTomorrow(_ train: TrainDeparture, after now: Date) -> Bool {
        BoardState.isLaterServiceDay(train.scheduledDeparture, than: now)
    }
}

// MARK: - Formatting

/// The big-screen time/words helpers. A namespace rather than free functions so they never clash with
/// the iOS-only `relativeTime`/`clock` in `BoardView`, and so they work on macOS too.
enum HallFormat {
    static func hm(_ date: Date) -> String { SNCFTime.hhmm(date) }

    /// "now" / "2 min" / "1 h 32".
    static func relative(_ date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return minutes < 1 ? "now" : SNCFTime.duration(minutes: minutes)
    }

    /// The hero's "in 2 min · run" / "leaving now".
    static func inWords(_ date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 1 { return "leaving now" }
        return "in \(relative(date, from: now))" + (minutes <= 5 ? " · run" : "")
    }

    static func numberAndDuration(_ train: TrainDeparture) -> String {
        var parts: [String] = []
        if let number = train.trainNumber { parts.append("N° \(number)") }
        if let duration = train.duration { parts.append("\(Int(duration / 60)) min") }
        return parts.joined(separator: " · ")
    }

    /// "HH:MM" base-schedule time pushed by a delay, for the inspector's stopping pattern.
    static func amend(_ hhmm: String, byMinutes minutes: Int) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        let total = (parts[0] * 60 + parts[1] + minutes + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func clock(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    /// The sidebar rule, matching the iOS Journeys tab.
    static func directionCaps(_ journey: JourneyConfiguration) -> String {
        if journey.nearestStationAsDeparture { return "FOLLOWS YOU" }
        switch journey.direction {
        case .forward: return "ALWAYS THIS WAY"
        case .reverse: return "ALWAYS REVERSED"
        case .automatic: return "REVERSES \(clock(journey.switchMinute))"
        }
    }

    /// The board chip spells "REVERSES AT 13:00" where the sidebar is terser.
    static func directionCapsChip(_ journey: JourneyConfiguration) -> String {
        if journey.nearestStationAsDeparture { return "FOLLOWS YOU" }
        switch journey.direction {
        case .forward: return "ALWAYS THIS WAY"
        case .reverse: return "ALWAYS REVERSED"
        case .automatic: return "REVERSES AT \(clock(journey.switchMinute))"
        }
    }
}

#Preview("Station hall") {
    let model = BigScreenModel()
    return StationHallView(now: BigScreenFixtures.now)
        .environment(model)
        .frame(width: 1376, height: 1032)
        .preferredColorScheme(.dark)
}

#Preview("Station hall · late evening") {
    StationHallView(now: BigScreenFixtures.lateNow)
        .environment(BigScreenModel())
        .environment(\.bigScreenData, .fakeLateEvening)
        .frame(width: 1376, height: 1032)
}
