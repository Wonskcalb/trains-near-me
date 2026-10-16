#if os(macOS)
import AppKit
import SNCFCore
import SwiftUI

// The macOS menu-bar extra (MenuBar.dc.html): a bar label and a window-style popover. Everything is
// driven by `data.journeyBoards` — live from the app's scene, the mockup `.fake` in the previews.
// macOS only — the menu bar is the one place this scene exists.

/// The bar item: the amber "A Flap" mark and the next train's time + minutes-until ("17:42 · 2′").
/// A single flap mark rather than a four-tile `FlapTime`, because the menu bar has room for one glyph
/// and the time is already spelled out in the text beside it (MenuBar.dc.html's label).
struct MenuBarLabel: View {
    @Environment(\.bigScreenData) private var data
    /// A frozen clock for the preview; nil follows the real one.
    var now: Date?
    @State private var trains: [TrainDeparture] = []
    @State private var clock = Date()

    var body: some View {
        // No TimelineView here: macOS turns the label into the status item's image on every render, and
        // that image swap asks SwiftUI for another update. A timeline restarting from `.now` on each render
        // never settles, so the app spun at launch. A plain state tick, set once a minute, is all it needs.
        HStack(spacing: 6) {
            FlapMark()
            Text(text(at: now ?? clock)).font(.mono(12.5, weight: .semibold))
        }
        // The minute tick recounts "2′" and moves on to the next train once one leaves, from the trains
        // already held; only the delays need a fetch.
        // ponytail: a fixed 15 min refetch for the delays, every saved journey per round (the boards memo
        // fetches them together) — about a hundred requests per journey a day while the app runs.
        .task {
            var minutes = 0
            while !Task.isCancelled {
                if minutes % 15 == 0 { trains = await Self.primaryTrains(from: data, at: now ?? .now) }
                try? await Task.sleep(for: .seconds(60))
                clock = .now
                minutes += 1
            }
        }
    }

    private func text(at clock: Date) -> String {
        guard let next = MenuBarFormat.next(in: trains, after: clock) else { return "—" }
        return "\(MenuBarFormat.hm.string(from: next.expectedDeparture)) · \(MenuBarFormat.minutesUntil(next.expectedDeparture, from: clock))′"
    }

    /// The primary (first saved) journey's trains — the ones the bar always watches.
    static func primaryTrains(from data: BigScreenData, at now: Date) async -> [TrainDeparture] {
        BoardReading.departures(await data.journeyBoards.boards(at: now).first?.state)
    }
}

/// The popover: a journey switcher, a refresh button, the next train as a flap, a compact time track,
/// the next three trains, journey chips, and the Open / Wall actions (MenuBar.dc.html).
struct MenuBarExtraView: View {
    @Environment(\.bigScreenData) private var data
    @Environment(\.openWindow) private var openWindow
    // Shared with the main window's BigScreenRoot: ⌘3 leaves "wall" here and that window switches route.
    @AppStorage("bigscreen.pendingRoute") private var pendingRoute = ""
    /// A frozen clock for the preview; nil follows the real one.
    var frozenNow: Date?
    @State private var clock = Date()
    private var now: Date { frozenNow ?? clock }

    @State private var boards: [JourneyBoard] = []
    @State private var selected = 0

    private var board: JourneyBoard? { boards.indices.contains(selected) ? boards[selected] : nil }

    init(now: Date? = nil) { frozenNow = now }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            // Trains that have left, or a cancelled first row, never become the hero.
            let trains = BoardReading.departures(board?.state).filter { $0.expectedDeparture > now }
            if let next = MenuBarFormat.next(in: trains, after: now) {
                let after = trains.filter { $0 != next && $0.expectedDeparture >= next.expectedDeparture }
                hero(next)
                // The hero already carries the imminent train, so the track and list show the ones after it.
                TimeTrack(trains: after, now: now, axis: .horizontal,
                          minutesSpan: 200, length: 324, metrics: .compact)
                nextTrains(Array(after.prefix(3)))
            } else {
                noDepartures
            }
            chips
            actions
        }
        .padding(16)
        .frame(width: 372, alignment: .leading)
        .background(Color.surface)
        .task {
            boards = await data.journeyBoards.boards(at: now)
            // The open popover keeps its countdowns and its hero current from what it holds.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                clock = Date()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            journeySwitcher
            Spacer()
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh")
        }
    }

    // A menu so the chevron and the list come for free; its own indicator is hidden since the glyph
    // already carries one.
    private var journeySwitcher: some View {
        Menu {
            ForEach(boards.indices, id: \.self) { i in
                Button(boards[i].leg.to.name) { selected = i }
            }
        } label: {
            HStack(spacing: 9) {
                RoutePins(lineColor: .inkSecondary, destination: .solid(.amber),
                          originDiameter: 7, destinationDiameter: 9, lineWidth: 1.8, lineLength: 10)
                Text(board.map { "\($0.leg.from.name) → \($0.leg.to.name)" } ?? "Trains near me")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Hero

    private func hero(_ next: TrainDeparture) -> some View {
        HStack(spacing: 14) {
            FlapTime(date: next.expectedDeparture, digitColor: .amber, tileWidth: 30, tileHeight: 44,
                     seamColor: .surface, cornerRadius: 6, colonColor: .amberText)
            VStack(alignment: .leading, spacing: 3) {
                Text("in \(MenuBarFormat.minutesUntil(next.expectedDeparture, from: now)) min")
                    .font(.mono(14, weight: .semibold))
                    .foregroundStyle(Color.soon)
                Text(subtitle(next, arrival: true))
                    .font(.mono(11.5))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    // MARK: Next three trains

    private func nextTrains(_ trains: [TrainDeparture]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(trains.enumerated()), id: \.offset) { i, train in
                if i > 0 { Divider().overlay(Color.ink.opacity(0.06)) }
                row(train)
            }
        }
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ train: TrainDeparture) -> some View {
        HStack(spacing: 10) {
            Text(MenuBarFormat.hm.string(from: train.scheduledDeparture))
                .font(.mono(15, weight: .bold))
                .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.amberText)
                .strikethrough(train.isCancelled)
                .fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            Text(subtitle(train, arrival: false))
                .font(.mono(12))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing(train)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder private func trailing(_ train: TrainDeparture) -> some View {
        switch train.status {
        case .cancelled: StatusPill("CANCELLED", status: .cancelled)
        case .delayed, .severelyDelayed: StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
        case .unknown: StatusPill("delay ?", status: .unknown)
        case .onTime:
            Text(MenuBarFormat.duration(train.expectedDeparture.timeIntervalSince(now)))
                .font(.mono(12)).foregroundStyle(Color.inkSecondary)
        }
    }

    // The secondary line: "TER 17655 · leaves 18:24" when a row is delayed, "· arr. 19:37" otherwise,
    // just the number when cancelled. `arrival` keeps the hero on "arr." even when it is running late.
    private func subtitle(_ train: TrainDeparture, arrival: Bool) -> String {
        var line = ""
        if let mode = train.mode { line += mode + " " }
        if let number = train.trainNumber { line += number }
        if train.isCancelled { return line }
        let late = train.status == .delayed || train.status == .severelyDelayed || train.status == .unknown
        if late, !arrival {
            line += " · leaves " + MenuBarFormat.hm.string(from: train.expectedDeparture)
        } else if let arrives = train.expectedArrival {
            line += " · arr. " + MenuBarFormat.hm.string(from: arrives)
        }
        return line
    }

    private var noDepartures: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz")
            Text(noDeparturesText).font(.mono(13))
        }
        .foregroundStyle(Color.inkSecondary)
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private var noDeparturesText: String {
        switch board?.state {
        case .noService: "No service tonight"
        case .endOfService(let first): "Service over · first " + MenuBarFormat.hm.string(from: first)
        case .noTrains: "No trains"
        case .unavailable(let error): error.terse
        default: "No departures"
        }
    }

    // MARK: Chips

    // A horizontal scroller rather than a wrapping row: journey names vary in length and SwiftUI has no
    // stock flow layout; scrolling keeps every chip reachable without reimplementing one.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(boards.indices, id: \.self) { i in chip(boards[i], index: i) }
            }
        }
    }

    private func chip(_ board: JourneyBoard, index i: Int) -> some View {
        let isSelected = i == selected
        return Button { selected = i } label: {
            HStack(spacing: 6) {
                // The selected journey's troubles are shown in the board above, so only the others carry
                // the at-a-glance dot (MenuBar.dc.html).
                if !isSelected, let dot = statusDot(board.state) {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(board.leg.to.name).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.surface : Color.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isSelected ? Color.ink : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(Color.ink.opacity(isSelected ? 0 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statusDot(_ state: BoardState) -> Color? {
        switch state {
        case .noService, .unavailable:
            return .stop
        case .departures(let trains):
            if trains.contains(where: { $0.status == .cancelled || $0.status == .severelyDelayed }) { return .stop }
            if trains.contains(where: { $0.status == .delayed || $0.status == .unknown }) { return .caution }
            return nil
        default:
            return nil
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.ink.opacity(0.07))
            action("Open Trains near me", shortcut: "⌘O", perform: openMain)
                .keyboardShortcut("o", modifiers: .command)
            action("Wall mode on this display", shortcut: "⌘3", perform: openWall)
                .keyboardShortcut("3", modifiers: .command)
            HStack {
                Text("Data © SNCF · not affiliated")
                Spacer()
                Text(MenuBarFormat.hm.string(from: now))
            }
            .font(.mono(11))
            .foregroundStyle(Color.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
    }

    private func action(_ title: String, shortcut: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Text(title).font(.system(size: 13.5)).foregroundStyle(Color.ink)
                Spacer()
                Text(shortcut).font(.mono(12)).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refresh() {
        Task {
            clock = Date()
            await data.journeyBoards.invalidate()
            boards = await data.journeyBoards.boards(at: now)
        }
    }

    // Open (or raise) the main window and bring the app forward. ⌘3 also sets the pending route so the
    // window lands on Wall mode — BigScreenRoot reads it on appear (cold open) and on change (already open).
    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func openWall() {
        pendingRoute = "wall"
        openMain()
    }
}

/// The amber "A Flap" bar mark: one tile with the ground-coloured split-flap seam across its middle.
private struct FlapMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.amber)
            .frame(width: 13, height: 15)
            .overlay(Color.ground.frame(height: 1))
            .accessibilityHidden(true)
    }
}

/// Times and durations for the popover, matched to `FlapTime`'s device-local clock so the flap and the
/// text beside it never disagree.
enum MenuBarFormat {
    static let hm: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func minutesUntil(_ date: Date, from now: Date) -> Int {
        max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
    }

    /// The first train still to leave that is not cancelled — the one the label and the hero name.
    static func next(in trains: [TrainDeparture], after now: Date) -> TrainDeparture? {
        trains.first { !$0.isCancelled && $0.expectedDeparture > now }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        let (hours, minutes) = (total / 60, total % 60)
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }
}

#Preview("Popover") {
    MenuBarExtraView(now: BigScreenFixtures.now)
}

#Preview("Label") {
    MenuBarLabel(now: BigScreenFixtures.now)
}
#endif
