import SNCFCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Wall mode — a full-screen departure board for the pinned station, kept awake (Wall.dc.html).
///
/// Always drawn on the Board (dark) palette whatever the app's appearance setting: a wall is a dark
/// board, so the subtree forces `\.colorScheme = .dark` and the Tableau tokens resolve to their dark
/// variants. The only hard-coded colours are the three wall shades that have no token (`#0A0B0C` ground,
/// `#121316` panel, `#1C1E22` clock tile).
struct WallModeView: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model

    /// A frozen anchor for previews / screenshots; nil in the app so the board and clock follow the real
    /// clock (and ⌘R re-anchors to the current time).
    private let frozenNow: Date?
    @State private var now = Date()

    @State private var station: Station?
    @State private var board: BoardState = .noTrains
    @State private var journeys: [JourneyBoard] = []
    @State private var leave: LeaveBy?
    @State private var leaveLeg: Leg?

    #if os(macOS)
    @State private var awake = WallAwake()
    #endif

    init(now: Date? = nil) { frozenNow = now }

    var body: some View {
        // One TimelineView ticks the whole board every minute: the clock advances, the "LEAVE HOME IN"
        // countdown drops, and the per-row "6 min" times recount — all from `context.date`, the live now.
        TimelineView(.periodic(from: now, by: 60)) { context in
            // Previews and screenshots stay on the frozen mockup clock instead of the real one.
            wall(liveNow: frozenNow ?? context.date)
        }
        // A wall is left running for hours: refetch every five minutes (the free tier's 5 000 requests a
        // day allow it; one station board and the journeys each round), on ⌘R, and on appear. Between
        // rounds the minute tick drops departed rows and recounts the countdowns from what is held.
        .task(id: model.refreshTick) {
            await load()
            guard frozenNow == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { break }
                await load()
            }
        }
        // Esc is wired globally by the shell; a tap anywhere leaves too (a wall is glanceable, not clicky).
        .onTapGesture { model.escape() }
        .keepScreenAwake(enter: enterKeepAwake, leave: leaveKeepAwake)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Loading

    private func load() async {
        now = frozenNow ?? Date()
        let station = await data.leaveBy.pinnedStation()
        self.station = station
        if let station {
            board = await data.stationBoard.board(for: station, at: now)
        }
        journeys = await data.journeyBoards.boards(at: now)
        // The leave-by is for the primary saved journey (the first card); its destination names the train.
        if let primary = journeys.first?.leg {
            leaveLeg = primary
            leave = await data.leaveBy.leaveBy(toCatch: primary, at: now)
        }
    }

    // MARK: Keep awake

    private func enterKeepAwake() {
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

    private func wall(liveNow: Date) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 26) {
                header(liveNow: liveNow)
                HStack(alignment: .top, spacing: 28) {
                    boardPanel(liveNow: liveNow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    rightColumn(liveNow: liveNow)
                        .frame(width: 400)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 26)
            footer(liveNow: liveNow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.ink)
        .background(Color.wallGround.ignoresSafeArea())
    }

    // MARK: Header

    private func header(liveNow: Date) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("DEPARTURES · PINNED STATION")
                        .font(.mono(13, weight: .semibold)).tracking(2.4)
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Color.amber)
                }
                .font(.system(size: 15))
                .foregroundStyle(Color.inkSecondary)
                Text(station?.name ?? "No pinned station")
                    .font(.system(size: 64, weight: .heavy)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 20)
            HStack(alignment: .bottom, spacing: 18) {
                Text(WallFormat.day.string(from: now).uppercased())
                    .font(.mono(14, weight: .semibold)).tracking(2)
                    .foregroundStyle(Color.inkSecondary).padding(.bottom, 6)
                FlapTime(date: liveNow, digitColor: .ink, tileWidth: 52, tileHeight: 74,
                         tileColor: .wallClockTile, seamColor: .wallGround, cornerRadius: 9, colonColor: .inkSecondary)
            }
        }
    }

    // MARK: Board

    @ViewBuilder private func boardPanel(liveNow: Date) -> some View {
        VStack(spacing: 0) {
            boardHeaderRow
            if case .departures(let trains) = board {
                ScrollView { boardRows(trains, liveNow: liveNow) }
            } else {
                Text(boardFallback)
                    .font(.mono(16, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.wallPanel, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var boardFallback: String {
        switch board {
        case .endOfService(let first): "Last train gone · first tomorrow \(WallFormat.time.string(from: first))"
        case .noService: "No service tonight"
        case .noTrains: "No departures"
        case .unavailable(let error): error.terse
        case .departures: ""
        }
    }

    private var boardHeaderRow: some View {
        HStack(spacing: 18) {
            Text("TIME").wallColumn(126, .leading)
            Text("DESTINATION").frame(maxWidth: .infinity, alignment: .leading)
            Text("TRAIN").wallColumn(150, .leading)
            Text("STATUS").wallColumn(132, .trailing)
        }
        .font(.mono(11, weight: .semibold)).tracking(1.6).foregroundStyle(Color.inkSecondary)
        .padding(.horizontal, 22).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Color.white.opacity(0.07).frame(height: 1) }
    }

    private func boardRows(_ trains: [TrainDeparture], liveNow: Date) -> some View {
        // Rows drop off as their train leaves, without waiting for the next fetch. The soonest one still to
        // run is the "next" — a cancelled row is never it — with the amber tint and a green countdown.
        let upcoming = trains.filter { $0.expectedDeparture > liveNow }
        let next = upcoming.first { !$0.isCancelled }
        return VStack(spacing: 0) {
            ForEach(Array(upcoming.enumerated()), id: \.offset) { _, train in
                WallBoardRow(train: train, isNext: train == next, fallbackDestination: station?.name, liveNow: liveNow)
                Color.white.opacity(0.06).frame(height: 1)
            }
        }
    }

    // MARK: Right column

    private func rightColumn(liveNow: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let leave, let leaveLeg {
                leaveCard(leave, to: leaveLeg.to.name, liveNow: liveNow)
            }
            Text("YOUR JOURNEYS")
                .font(.mono(11, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Color.inkSecondary).padding(.horizontal, 6).padding(.top, 4)
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(journeys.enumerated()), id: \.offset) { _, journey in
                        WallJourneyCard(leg: journey.leg, state: journey.state)
                    }
                }
            }
        }
    }

    private func leaveCard(_ leave: LeaveBy, to destination: String, liveNow: Date) -> some View {
        // The hero is a countdown of whole minutes until you must walk out, not a clock time, so it is two
        // bare flap tiles rather than a `FlapTime` (which only renders HH:MM). Clamped 0–99: a door-leave
        // window never runs to hours.
        let minutes = min(99, max(0, Int(leave.leaveAt.timeIntervalSince(liveNow) / 60)))
        return VStack(alignment: .leading, spacing: 14) {
            Text("LEAVE HOME IN").font(.mono(12, weight: .bold)).tracking(2)
            HStack(alignment: .bottom, spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(Array(String(format: "%02d", minutes).enumerated()), id: \.offset) { _, digit in
                        WallFlapTile(digit: digit)
                    }
                }
                Text("MIN").font(.mono(26, weight: .bold)).padding(.bottom, 8)
            }
            Text("for the \(WallFormat.time.string(from: leave.train.expectedDeparture)) to \(destination).\n\(leave.walkMinutes) min walk to the platform.")
                .font(.system(size: 16, weight: .semibold)).lineSpacing(3)
        }
        .foregroundStyle(Color.onAmber)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(Color.amber, in: RoundedRectangle(cornerRadius: 26))
    }

    // MARK: Footer

    private func footer(liveNow: Date) -> some View {
        HStack(spacing: 0) {
            ZStack {
                HazardBackground(variant: .band, stripe: .amber, bandWidth: 10)
                Text("INFO").font(.mono(13, weight: .heavy)).tracking(2).foregroundStyle(Color.amber)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.wallGround, in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(width: 150)
            .frame(maxHeight: .infinity)
            Text(disruptions)
                .font(.mono(16, weight: .medium)).foregroundStyle(Color.ink.opacity(0.85))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            HStack(spacing: 8) {
                Circle().fill(Color.soon).frame(width: 7, height: 7)
                Text("Data © SNCF · \(WallFormat.time.string(from: liveNow)) · Esc to leave")
                    .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 64)
        .background(Color.ground)
        .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1) }
    }

    /// The disruptions, one line: dead journeys first, then the station's late and cancelled trains.
    private var disruptions: String {
        var parts: [String] = []
        for journey in journeys where journey.state == .noService {
            parts.append("\(journey.leg.from.name) → \(journey.leg.to.name): no service tonight, every remaining train cancelled")
        }
        if case .departures(let trains) = board {
            for train in trains {
                let name = train.direction ?? station?.name ?? "Train"
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

/// Minutes until a departure as "6 min" / "1 h 36" / "now". `BoardView`'s own `relativeTime` is walled
/// behind `#if os(iOS)`, so Wall (which also runs on the Mac) carries its own copy.
private func wallCountdown(to date: Date, from now: Date) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
}

private struct WallBoardRow: View {
    @Environment(\.bigScreenData) private var data
    let train: TrainDeparture
    let isNext: Bool
    let fallbackDestination: String?
    let liveNow: Date
    @State private var via: [String] = []

    var body: some View {
        HStack(spacing: 18) {
            flap.wallColumn(126, .leading)
            destination.frame(maxWidth: .infinity, alignment: .leading)
            trainCell.wallColumn(150, .leading)
            status.wallColumn(132, .trailing)
        }
        .padding(.horizontal, 22).padding(.vertical, 15)
        .background(isNext ? Color.amber.opacity(0.06) : Color.clear)
        // The station board carries no stopping pattern, so each row asks for its own "via …" as it
        // appears — all rows at once rather than one after another, and cached by the provider.
        .task(id: train.vehicleJourneyID) {
            guard let id = train.vehicleJourneyID else { return }
            via = await data.stationBoard.via(forVehicleJourneyID: id)
        }
    }

    /// The timetabled time as four flap tiles — amendments live in the status column, never the flap. A
    /// cancelled row goes grey, with the seam hidden (seam = tile colour) so it loses the split line.
    private var flap: some View {
        FlapTime(date: train.scheduledDeparture,
                 digitColor: train.isCancelled ? .inkSecondary : .amber,
                 tileWidth: 25, tileHeight: 38, tileColor: .raised,
                 seamColor: train.isCancelled ? .raised : .wallGround, cornerRadius: 5)
            .opacity(train.isCancelled ? 0.45 : 1)
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(train.direction ?? fallbackDestination ?? "—")
                .font(.system(size: 27, weight: .bold)).foregroundStyle(Color.ink)
                .strikethrough(train.isCancelled, color: Color.ink)
                .lineLimit(1)
            Text(via.isEmpty ? "direct" : "via " + via.joined(separator: " · "))
                .font(.mono(12.5, weight: .medium)).foregroundStyle(Color.inkSecondary).lineLimit(1)
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
            Text(wallCountdown(to: train.expectedDeparture, from: liveNow))
                .font(.mono(isNext ? 20 : 18, weight: isNext ? .bold : .medium))
                .foregroundStyle(isNext ? Color.soon : Color.inkSecondary)
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
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background { background }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
                .font(.mono(13, weight: .bold)).tracking(1.6).foregroundStyle(Color.amber)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Color.wallGround, in: RoundedRectangle(cornerRadius: 8))
        } else if let (time, secondary) = headline {
            VStack(alignment: .trailing, spacing: 2) {
                Text(time).font(.mono(24, weight: .bold)).foregroundStyle(Color.amber)
                secondary.font(.mono(12, weight: .medium))
            }
        }
    }

    /// The next departure time and a secondary line: its delay, or its arrival.
    private var headline: (String, Text)? {
        switch state {
        case .departures(let trains):
            guard let next = trains.first(where: { !$0.isCancelled }) ?? trains.first else { return nil }
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

// MARK: - Flap tile (countdown)

/// One flap tile for the leave-by countdown: the digit on a dark tile, an amber seam across the middle.
/// `FlapTime`'s own tile is private and locked to a four-tile HH:MM, so the bare-digit pair is its own.
private struct WallFlapTile: View {
    let digit: Character

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(Color.ground)
            // Sized from the tile height like `FlapTime`'s digits (88 × 0.65 ≈ 57 pt; the mockup draws 62).
            Text(String(digit)).font(.monoFixed(88 * 0.65, weight: .bold)).foregroundStyle(Color.amber)
            Color.amber.opacity(0.35).frame(height: 1.5)
        }
        .frame(width: 62, height: 88)
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

    /// Enter / leave the display-awake state. One release point: changing route removes the view, so Esc
    /// and a tap both land on `.onDisappear`.
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
    static let time = formatter("HH:mm")
    /// "Thu 15 Oct", upper-cased by the caller.
    static let day = formatter("EEE d MMM")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = format
        return f
    }
}

#Preview("Wall mode") {
    WallModeView(now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .frame(width: 1376, height: 1032)
}
