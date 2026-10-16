import SNCFCore
import SwiftUI

// Lanes — every saved journey on one time axis, with the service-day minimap (Lanes.dc.html). Drawn as
// the light "Timetable" chart in the mockup, but it only ever reads theme tokens, so it follows the app's
// Light/Dark setting; the ink popover and the NO SERVICE plate are fixed dark in both. Every value comes
// from `BigScreenData` in the environment (live in the app, the mockup in previews); no `SNCFClient`.

// Fixed geometry, matching the mockup's 260/20/960 grid and 66 pt lanes. The track width itself is read
// from the layout (a `GeometryReader`), so every lane and the axis share one time-to-x mapping.
private let laneLabelWidth: CGFloat = 230
private let laneColumnGap: CGFloat = 20
private let laneHeight: CGFloat = 66
private let laneBarHeight: CGFloat = 30
private let laneRow2Y: CGFloat = laneHeight - laneBarHeight   // the second sub-row, so bars never collide

/// The three range presets; the raw value is the picker label.
private enum LanesRange: String, CaseIterable, Identifiable {
    case next4h = "NEXT 4 H"
    case tonight = "TONIGHT"
    case tomorrowAM = "TOMORROW AM"
    var id: String { rawValue }
}

/// The visible time window: a start and a span. `x(_:in:)` maps a date to a point along a track of the
/// given width; `rawX` is the same without clamping, so a bar can tell it runs past an edge.
private struct LaneWindow: Equatable {
    var start: Date
    var span: TimeInterval
    var end: Date { start.addingTimeInterval(span) }

    func rawX(_ date: Date, in width: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(start) / span) * width
    }
    func x(_ date: Date, in width: CGFloat) -> CGFloat {
        min(width, max(0, rawX(date, in: width)))
    }
}

struct LanesView: View {
    @Environment(\.bigScreenData) private var data
    // Optional so previews need not inject the shell model; the running app always provides it.
    @Environment(BigScreenModel.self) private var model: BigScreenModel?

    /// Default `Date()`; previews and the screenshot build pass `BigScreenFixtures.now` so the fixed
    /// 17:40 world lines up with the 4 h window.
    let now: Date

    @State private var boards: [JourneyBoard] = []
    @State private var selectedJourney = 0
    @State private var summary: ServiceDaySummary?
    @State private var range: LanesRange = .next4h
    @State private var window: LaneWindow
    /// The bar whose popover is open, as "laneIndex-id"; one binding shared by every bar.
    @State private var selectedBar: String?

    // The service day the chart and the minimap are anchored on; Paris, because the trains run on it.
    private let calendar = SNCFTime.calendar

    init(now: Date = Date()) {
        self.now = now
        _window = State(initialValue: LanesView.window(for: .next4h, now: now, calendar: SNCFTime.calendar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            titleRow
            axisHeader
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(boards.enumerated()), id: \.offset) { index, board in
                        LaneRow(board: board, index: index, now: now, window: window,
                                calendar: calendar, isSelected: index == selectedJourney,
                                selectedBar: $selectedBar) { selectedJourney = index }
                    }
                }
            }
            minimap
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ground.ignoresSafeArea())
        // A time chart drawn to fixed lane geometry (66 pt lanes, 30 pt bars): past this size the bar
        // labels would clip, so the type stops growing there.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .task { await load() }
        .onChange(of: model?.refreshTick) { Task { await load() } }
        .onChange(of: selectedJourney) { Task { await loadSummary() } }
    }

    // MARK: Loading

    private func load() async {
        boards = await data.journeyBoards.boards(at: now)
        if selectedJourney >= boards.count { selectedJourney = 0 }
        await loadSummary()
    }

    private func loadSummary() async {
        guard boards.indices.contains(selectedJourney) else { summary = nil; return }
        summary = await data.serviceDay.summary(for: boards[selectedJourney].leg, at: now)
    }

    // MARK: Top chrome

    private var header: some View {
        HStack {
            rangePicker
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(freshDotColor).frame(width: 7, height: 7)
                Text("Updated \(LanesFormat.hm.string(from: boards.first?.fetchedAt ?? now))")
                    .font(.mono(12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private var freshDotColor: Color {
        guard let fetched = boards.first?.fetchedAt else { return .inkSecondary }
        return now.timeIntervalSince(fetched) > 30 * 60 ? .amber : .soon
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(LanesRange.allCases) { option in
                Button {
                    range = option
                    window = LanesView.window(for: option, now: now, calendar: calendar)
                } label: {
                    Text(option.rawValue)
                        .font(.mono(12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(range == option ? Color.ground : Color.inkSecondary)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(range == option ? Color.ink : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
    }

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lanes").font(.system(size: 34, weight: .bold))
                Text("Every saved journey on one track. A bar runs from departure to arrival.")
                    .font(.system(size: 14)).foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendSwatch(Color.amber, ring: .ink, "next")
            legendSwatch(Color.ink, ring: nil, "on time")
            legendSwatch(Color.cautionBg, ring: .caution, "+11–19")
            legendSwatch(Color.stopBg, ring: .stop, "+20")
        }
        .font(.mono(11.5, weight: .medium))
        .foregroundStyle(Color.inkSecondary)
    }

    private func legendSwatch(_ fill: Color, ring: Color?, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 18, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ring ?? .clear, lineWidth: 1.5))
            Text(label)
        }
    }

    // MARK: Axis header (hour labels + the NOW flag), sharing the lane geometry

    private var axisHeader: some View {
        HStack(spacing: laneColumnGap) {
            Text("JOURNEY")
                .font(.mono(11, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Color.inkSecondary)
                .frame(width: laneLabelWidth, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(hourMarks, id: \.self) { hour in
                        Text(LanesFormat.hm.string(from: hour))
                            .font(.mono(12, weight: .semibold)).foregroundStyle(Color.inkSecondary)
                            .fixedSize().position(x: window.x(hour, in: w), y: 20)
                    }
                    if now >= window.start && now <= window.end {
                        Text("NOW \(LanesFormat.hm.string(from: now))")
                            .font(.mono(11, weight: .bold)).tracking(0.8).foregroundStyle(Color.onAmber)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.amber, in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize().position(x: window.x(now, in: w), y: 10)
                    }
                }
            }
            .frame(height: 28)
        }
    }

    private var hourMarks: [Date] {
        var marks: [Date] = []
        guard var tick = calendar.dateInterval(of: .hour, for: window.start)?.start else { return [] }
        if tick < window.start { tick = calendar.date(byAdding: .hour, value: 1, to: tick) ?? tick }
        while tick <= window.end && marks.count <= 48 {
            marks.append(tick)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { break }
            tick = next
        }
        return marks
    }

    // MARK: Minimap

    @ViewBuilder private var minimap: some View {
        let legName = boards.indices.contains(selectedJourney) ? boards[selectedJourney].leg : nil
        ServiceMinimap(summary: summary, legName: legName, window: $window,
                       dayStart: LanesView.serviceDayStart(now, calendar), calendar: calendar)
    }

    // MARK: Window maths

    fileprivate static func serviceDayStart(_ now: Date, _ calendar: Calendar) -> Date {
        // The service day starts at 03:00; a 00:15 train still belongs to the previous evening.
        calendar.startOfDay(for: now.addingTimeInterval(-3 * 3600)).addingTimeInterval(3 * 3600)
    }

    fileprivate static func window(for range: LanesRange, now: Date, calendar: Calendar) -> LaneWindow {
        switch range {
        case .next4h:
            // The mockup sits NOW 20 min in from the left so the just-departed context stays on screen.
            return LaneWindow(start: now.addingTimeInterval(-20 * 60), span: 240 * 60)
        case .tonight:
            let end = serviceDayStart(now, calendar).addingTimeInterval(24 * 3600)   // next 03:00
            return LaneWindow(start: now, span: max(60 * 60, end.timeIntervalSince(now)))
        case .tomorrowAM:
            let amStart = serviceDayStart(now, calendar).addingTimeInterval(24 * 3600 + 2 * 3600)   // 05:00
            return LaneWindow(start: amStart, span: 6 * 3600)
        }
    }
}

// MARK: - One lane

private struct LaneRow: View {
    @Environment(\.bigScreenData) private var data
    let board: JourneyBoard
    let index: Int
    let now: Date
    let window: LaneWindow
    let calendar: Calendar
    let isSelected: Bool
    @Binding var selectedBar: String?
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: laneColumnGap) {
            label.frame(width: laneLabelWidth, alignment: .leading)
            track
        }
        .padding(.vertical, 16).padding(.leading, 20).padding(.trailing, 12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Color.amber : Color.ink.opacity(0.07), lineWidth: isSelected ? 1.5 : 1)
        )
    }

    // MARK: Label column

    private var label: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoutePins(destination: isSelected ? .ring(core: .amber, ring: .ink) : .solid(.inkSecondary),
                          lineLength: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(board.leg.from.name).font(.system(size: 13)).foregroundStyle(Color.inkSecondary)
                    Text(board.leg.to.name).font(.system(size: 19, weight: .bold)).foregroundStyle(Color.ink)
                    Text(summaryText).font(.mono(10.5, weight: .semibold)).tracking(1)
                        .foregroundStyle(summaryColor).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var trains: [TrainDeparture] {
        if case .departures(let list) = board.state { return list }
        return []
    }

    private var summaryText: String {
        if case .noService = board.state { return "EVERY TRAIN CANCELLED" }
        let suffix = trains.first?.duration.map { " · \(LanesFormat.duration($0))" } ?? ""
        let delayed = trains.filter { [.delayed, .severelyDelayed, .unknown].contains($0.status) }.count
        let cancelled = trains.filter(\.isCancelled).count
        if delayed > 0 { return "\(delayed) DISRUPTED\(suffix)" }
        if cancelled > 0 { return "\(cancelled) CANCELLED\(suffix)" }
        return directionText + suffix
    }

    private var summaryColor: Color {
        if case .noService = board.state { return .stop }
        if trains.contains(where: { [.delayed, .severelyDelayed, .unknown].contains($0.status) }) { return .caution }
        if trains.contains(where: \.isCancelled) { return .stop }
        return .inkSecondary
    }

    private var directionText: String {
        let journey = board.journey
        if journey.nearestStationAsDeparture { return "FOLLOWS YOU" }
        switch journey.direction {
        case .forward, .reverse: return "ALWAYS THIS WAY"
        case .automatic: return String(format: "REVERSES %02d:%02d", journey.switchMinute / 60, journey.switchMinute % 60)
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                LaneGrid(window: window, now: now, hourMarks: hourMarks(w))
                if case .noService = board.state {
                    noService(w)
                } else if trains.isEmpty {
                    emptyNote
                } else {
                    bars(w)
                }
            }
            .frame(height: laneHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(height: laneHeight)
    }

    private func hourMarks(_ w: CGFloat) -> [CGFloat] {
        var xs: [CGFloat] = []
        guard var tick = calendar.dateInterval(of: .hour, for: window.start)?.start else { return [] }
        if tick < window.start { tick = calendar.date(byAdding: .hour, value: 1, to: tick) ?? tick }
        while tick <= window.end && xs.count <= 48 {
            xs.append(window.x(tick, in: w))
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { break }
            tick = next
        }
        return xs
    }

    @ViewBuilder private var emptyNote: some View {
        let note: String = {
            switch board.state {
            case .endOfService(let first): return "Service over · first \(LanesFormat.hm.string(from: first))"
            case .unavailable(let error): return error.terse
            default: return "No trains in this window"
            }
        }()
        Text(note).font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // The lane from NOW on is muted stripes — amber at about half strength crossed by thin ink hatching,
    // inset from the lane edges — under a black NO SERVICE plate (Lanes.dc.html lane 3). The full-strength
    // hazard band is for a whole screen; in one lane of a chart it drowned the bars around it.
    private func noService(_ w: CGFloat) -> some View {
        let left = window.x(now, in: w)
        return ZStack(alignment: .leading) {
            Color.amber.opacity(0.55)
                .overlay(Hatch(color: .ink))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 6)
                .frame(width: max(0, w - left - 6)).offset(x: left + 3)
            HStack(spacing: 12) {
                Text("NO SERVICE").font(.mono(14, weight: .bold)).tracking(2).foregroundStyle(Color.amber)
                Text("No trains until \(LanesFormat.hm.string(from: window.end))")
                    .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 16).frame(height: 36)
            .background(Color.ground, in: RoundedRectangle(cornerRadius: 9))
            // The plate is ink in both schemes; on the dark palette `ground` is that ink and the amber
            // label stays amber text on a dark plate, never on paper.
            .environment(\.colorScheme, .dark)
            .offset(x: left + 24, y: (laneHeight - 36) / 2)
        }
    }

    // MARK: Bars

    @ViewBuilder private func bars(_ w: CGFloat) -> some View {
        // The soonest upcoming train that is not cancelled reads as "next" (amber when it is on time).
        let nextID = trains.first { !$0.isCancelled && $0.expectedDeparture >= now }
            .flatMap { TrainIdentity($0, calendar: calendar) }
        ForEach(Array(trains.enumerated()), id: \.offset) { position, train in
            let rowY: CGFloat = position % 2 == 0 ? 0 : laneRow2Y
            let isNext = TrainIdentity(train, calendar: calendar) == nextID
            bar(train, rowY: rowY, isNext: isNext, width: w)
        }
    }

    @ViewBuilder private func bar(_ train: TrainDeparture, rowY: CGFloat,
                                  isNext: Bool, width w: CGFloat) -> some View {
        let barID = "\(index)-\(train.trainNumber ?? train.vehicleJourneyID ?? "\(train.scheduledDeparture.timeIntervalSinceReferenceDate)")"
        let status = train.status
        ZStack(alignment: .topLeading) {
            // A delayed train keeps a dashed ghost at its timetabled slot, so the slide is visible.
            if status == .delayed || status == .severelyDelayed,
               let slot = frame(train.scheduledDeparture, train.scheduledArrival, w) {
                ghostBar(train.scheduledDeparture, color: status.tableauInk, frame: slot, rowY: rowY)
            }
            if let box = frame(departureX(train), arrivalX(train), w) {
                Button { selectedBar = selectedBar == barID ? nil : barID } label: {
                    mainBar(train, status: status, isNext: isNext, box: box, selected: selectedBar == barID)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { selectedBar == barID },
                    set: { if !$0, selectedBar == barID { selectedBar = nil } })) {
                    LaneTrainPopover(train: train, leg: board.leg)
                }
                .offset(x: box.left, y: rowY)
            }
        }
    }

    // The timetable position a bar is drawn at: cancelled stays at its scheduled slot, everything else
    // slides to the expected time.
    private func departureX(_ train: TrainDeparture) -> Date {
        train.isCancelled ? train.scheduledDeparture : train.expectedDeparture
    }
    private func arrivalX(_ train: TrainDeparture) -> Date? {
        train.isCancelled ? train.scheduledArrival : (train.expectedArrival ?? train.scheduledArrival)
    }

    /// Clamped left/width for a dep→arr span, and whether it runs off the right edge. nil when fully off.
    private func frame(_ from: Date, _ to: Date?, _ w: CGFloat) -> (left: CGFloat, width: CGFloat, overflow: Bool)? {
        let end = to ?? from.addingTimeInterval(20 * 60)
        let rawL = window.rawX(from, in: w), rawR = window.rawX(end, in: w)
        guard rawR > 0 && rawL < w else { return nil }
        let left = max(0, rawL), right = min(w, rawR)
        // 56 = a mono "17:42" at 12.5 pt plus the bar's 8 pt insets, so the shortest bar still shows its time.
        return (left, max(56, right - left), rawR > w)
    }

    private func ghostBar(_ scheduled: Date, color: Color, frame: (left: CGFloat, width: CGFloat, overflow: Bool), rowY: CGFloat) -> some View {
        HStack {
            Text(LanesFormat.hm.string(from: scheduled)).strikethrough()
                .font(.mono(11, weight: .semibold)).foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).frame(width: frame.width, height: laneBarHeight)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .opacity(0.55)
        .offset(x: frame.left, y: rowY)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func mainBar(_ train: TrainDeparture, status: DepartureStatus, isNext: Bool,
                                      box: (left: CGFloat, width: CGFloat, overflow: Bool), selected: Bool) -> some View {
        let amber = isNext && status == .onTime
        let time = Text(LanesFormat.hm.string(from: departureX(train)))
            .strikethrough(status == .cancelled)
            .font(.mono(12.5, weight: .bold))
            .fixedSize()
        let tag = tagText(train, status: status, isNext: isNext).map {
            Text($0).font(.mono(status == .cancelled || amber ? 9.5 : 11, weight: amber ? .semibold : .bold))
                .tracking(amber || status == .cancelled ? 0.9 : 0)
                .fixedSize()
        }
        let arrow = box.overflow ? Text("→").font(.mono(11, weight: .bold)) : nil
        // A short bar (a quick trip, or one clipped at NOW) can't hold the time and its tag side by side;
        // squeezing them truncated the time, which is the one thing a bar must show. Drop the tag first.
        let content = ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { time; Spacer(minLength: 2); tag; arrow }
            HStack(spacing: 4) { time; Spacer(minLength: 2); arrow }
            time
        }
        .foregroundStyle(barInk(status: status, amber: amber))
        .padding(.horizontal, 8).frame(width: box.width, height: laneBarHeight)

        content
            .background { barFill(status: status, amber: amber) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(barBorder(status: status, amber: amber, selected: selected))
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel(train, status: status))
    }

    private func tagText(_ train: TrainDeparture, status: DepartureStatus, isNext: Bool) -> String? {
        switch status {
        case .cancelled: return "CANC."
        case .delayed, .severelyDelayed: return train.delayMinutes.map { "+\($0)" }
        case .unknown: return "?"
        case .onTime: return isNext ? "NEXT" : nil
        }
    }

    private func barInk(status: DepartureStatus, amber: Bool) -> Color {
        if amber { return .onAmber }
        switch status {
        case .onTime: return .ground
        case .delayed, .unknown: return .caution
        case .severelyDelayed, .cancelled: return .stop
        }
    }

    @ViewBuilder private func barFill(status: DepartureStatus, amber: Bool) -> some View {
        if amber {
            Color.amber
        } else if status == .cancelled {
            Hatch(color: .stop).background(Color.stopBg)
        } else if status == .onTime {
            Color.ink
        } else {
            status.tableauFill
        }
    }

    @ViewBuilder private func barBorder(status: DepartureStatus, amber: Bool, selected: Bool) -> some View {
        if status == .cancelled {
            RoundedRectangle(cornerRadius: 8).stroke(Color.stop, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        } else if amber {
            RoundedRectangle(cornerRadius: 8).stroke(Color.ink, lineWidth: 1.5)
        } else if status == .delayed || status == .severelyDelayed || status == .unknown {
            RoundedRectangle(cornerRadius: 8).stroke(status.tableauInk, lineWidth: selected ? 2 : 1.5)
        } else if selected {
            RoundedRectangle(cornerRadius: 8).stroke(Color.amber, lineWidth: 1.5)
        }
    }

    private func accessibilityLabel(_ train: TrainDeparture, status: DepartureStatus) -> String {
        var parts: [String] = []
        if let number = train.trainNumber { parts.append("Train \(number)") }
        switch status {
        case .cancelled: parts.append("cancelled, timetabled \(LanesFormat.hm.string(from: train.scheduledDeparture))")
        case .delayed, .severelyDelayed:
            parts.append("departs \(LanesFormat.hm.string(from: train.expectedDeparture))")
            if let delay = train.delayMinutes { parts.append("\(delay) minutes late") }
        default: parts.append("departs \(LanesFormat.hm.string(from: train.expectedDeparture))")
        }
        parts.append("to \(board.leg.to.name)")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Grid behind the bars (past shading, hour lines, the NOW line)

private struct LaneGrid: View {
    let window: LaneWindow
    let now: Date
    let hourMarks: [CGFloat]

    var body: some View {
        Canvas { context, size in
            if now > window.start {
                let nx = window.x(now, in: size.width)
                context.fill(Path(CGRect(x: 0, y: 0, width: nx, height: size.height)),
                             with: .color(.ink.opacity(0.035)))
            }
            for hx in hourMarks {
                context.fill(Path(CGRect(x: hx - 0.5, y: 0, width: 1, height: size.height)),
                             with: .color(.ink.opacity(0.07)))
            }
            if now >= window.start && now <= window.end {
                let nx = window.x(now, in: size.width)
                context.fill(Path(CGRect(x: nx - 1, y: 0, width: 2, height: size.height)), with: .color(.ink))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Diagonal hatching for a cancelled bar: the same -45° bands the hazard uses, at low alpha.
private struct Hatch: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            var x = -size.height
            while x < size.width {
                var band = Path()
                band.move(to: CGPoint(x: x, y: size.height))
                band.addLine(to: CGPoint(x: x + 3, y: size.height))
                band.addLine(to: CGPoint(x: x + 3 + size.height, y: 0))
                band.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.fill(band, with: .color(color.opacity(0.2)))
                x += 10
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The ink popover on a bar

/// Always the dark ink card the mockup draws, whatever the chart's scheme: the subtree is forced dark,
/// so `ground` is the ink surface and `ink` its light text, and the mode chip's outline stays visible.
/// Shared with the station board's stops, so a train reads the same wherever it is tapped.
struct LaneTrainPopover: View {
    @Environment(\.bigScreenData) private var data
    let train: TrainDeparture
    let leg: Leg

    @State private var stops: [TripStop] = []
    @State private var watched = false
    @State private var showStops = false

    private var identity: TrainIdentity? { TrainIdentity(train) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            times
            Text(detailLine).font(.mono(11.5, weight: .medium)).foregroundStyle(Color.ink.opacity(0.6))
            buttons
            if showStops { stopList }
        }
        .padding(16).frame(width: 280)
        .background(Color.ground)
        .environment(\.colorScheme, .dark)
        .task {
            if let identity { watched = await data.watching.isWatched(identity) }
            stops = (try? await data.trainStops.stops(forVehicleJourneyID: train.vehicleJourneyID ?? "")) ?? []
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                if let mode = train.mode { ModeChip(mode) }
                if let number = train.trainNumber {
                    Text("N° \(number)").font(.mono(13, weight: .semibold)).foregroundStyle(Color.ink)
                }
            }
            Spacer()
            if train.isCancelled {
                StatusPill("CANCELLED", status: .cancelled)
            } else if let delay = train.delayMinutes, delay > 0 {
                StatusPill("+\(delay)", status: train.status)
            }
        }
    }

    private var times: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(LanesFormat.hm.string(from: train.expectedDeparture))
                .font(.mono(22, weight: .bold)).foregroundStyle(Color.amber)
            Text("–").foregroundStyle(Color.ink.opacity(0.5))
            if let arrival = train.expectedArrival {
                Text(LanesFormat.hm.string(from: arrival))
                    .font(.mono(16, weight: .medium)).foregroundStyle(Color.ink.opacity(0.85))
            }
            Spacer()
            Text(leg.to.name).font(.system(size: 13)).foregroundStyle(Color.ink.opacity(0.55))
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if train.isCancelled || (train.delayMinutes ?? 0) > 0 {
            parts.append("was \(LanesFormat.hm.string(from: train.scheduledDeparture))")
        }
        if !stops.isEmpty { parts.append("\(stops.count) stops") }
        parts.append("to \(stops.last?.name ?? leg.to.name)")
        return parts.joined(separator: " · ")
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            popoverButton(watched ? "Watching" : "Watch") {
                guard let identity else { return }
                Task {
                    if watched { await data.watching.unwatch(identity) } else { await data.watching.watch(train, to: leg) }
                    watched = await data.watching.isWatched(identity)
                }
            }
            .accessibilityValue(watched ? "On" : "Off")
            popoverButton(showStops ? "Hide stops" : "Stops") { showStops.toggle() }
        }
    }

    private func popoverButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity).frame(minHeight: 36)
                .background(Color.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var stopList: some View {
        if stops.isEmpty {
            Text("No stop list available.").font(.mono(11.5)).foregroundStyle(Color.ink.opacity(0.5))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(stops, id: \.name) { stop in
                    HStack {
                        Text(stop.name).strikethrough(stop.isSkipped)
                            .font(.system(size: 12)).foregroundStyle(Color.ink.opacity(stop.isSkipped ? 0.4 : 0.85))
                        Spacer()
                        Text(stop.time).font(.mono(12, weight: .medium)).foregroundStyle(Color.ink.opacity(0.6))
                    }
                }
            }
        }
    }
}

// MARK: - Service-day minimap

private struct ServiceMinimap: View {
    let summary: ServiceDaySummary?
    let legName: Leg?
    @Binding var window: LaneWindow
    let dayStart: Date
    let calendar: Calendar

    @State private var dragBase: Date?

    private var dayEnd: Date { dayStart.addingTimeInterval(24 * 3600) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.mono(11, weight: .semibold)).tracking(1.4).foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("drag the window").font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
            }
            if let summary { bars(summary) } else { placeholder }
            labels
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ink.opacity(0.07), lineWidth: 1))
    }

    private var title: String {
        let route = legName.map { "\($0.from.name.uppercased()) → \($0.to.name.uppercased())" } ?? "SERVICE DAY"
        return "SERVICE DAY · \(route) · TRAINS PER HOUR"
    }

    private var placeholder: some View {
        Text("No service-day data for this journey.")
            .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
            .frame(height: 64, alignment: .center).frame(maxWidth: .infinity)
    }

    private func bars(_ summary: ServiceDaySummary) -> some View {
        let maxCount = max(summary.trainsPerHour.max() ?? 1, 1)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(summary.trainsPerHour.enumerated()), id: \.offset) { hour, count in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(hour: hour, count: count))
                            .frame(height: barHeight(count, maxCount))
                            .frame(maxWidth: .infinity)
                    }
                }
                brush(w)
            }
        }
        .frame(height: 64)
    }

    private func barHeight(_ count: Int, _ maxCount: Int) -> CGFloat {
        count == 0 ? 2 : 14 + CGFloat(count - 1) / CGFloat(max(1, maxCount - 1)) * 28
    }

    private func barColor(hour: Int, count: Int) -> Color {
        let bucketStart = dayStart.addingTimeInterval(Double(hour) * 3600)
        let inWindow = bucketStart < window.end && bucketStart.addingTimeInterval(3600) > window.start
        if count == 0 { return .sleeper.opacity(0.5) }
        return inWindow ? .ink : .sleeper
    }

    // The visible window as a draggable amber brush over the 24 h day.
    private func brush(_ w: CGFloat) -> some View {
        let fStart = CGFloat(window.start.timeIntervalSince(dayStart) / (24 * 3600))
        let fWidth = CGFloat(window.span / (24 * 3600))
        return RoundedRectangle(cornerRadius: 10)
            .fill(Color.amber.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ink, lineWidth: 2))
            .frame(width: max(14, fWidth * w))
            .frame(maxHeight: .infinity)
            .offset(x: max(0, min(w - fWidth * w, fStart * w)))
            .gesture(DragGesture()
                .onChanged { value in
                    if dragBase == nil { dragBase = window.start }
                    let dt = Double(value.translation.width / w) * 24 * 3600
                    let proposed = (dragBase ?? window.start).addingTimeInterval(dt)
                    window.start = max(dayStart, min(dayEnd.addingTimeInterval(-window.span), proposed))
                }
                .onEnded { _ in dragBase = nil })
            .accessibilityLabel("Visible window \(LanesFormat.hm.string(from: window.start)) to \(LanesFormat.hm.string(from: window.end))")
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { step in
                Text(LanesFormat.hm.string(from: dayStart.addingTimeInterval(Double(step) * 3 * 3600)))
                    .font(.mono(11, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Shared formatting

/// MainActor-isolated so the cached `DateFormatter` is safe under Swift 6 strict concurrency, the way
/// `FlapTime` keeps its own. Times are pinned to Europe/Paris: the trains run on it, whatever the device.
@MainActor private enum LanesFormat {
    static let hm: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? String(format: "%d H %02d", minutes / 60, minutes % 60) : "\(minutes) MIN"
    }
}

#Preview("Lanes") {
    LanesView(now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .frame(width: 1376, height: 1032)
}
