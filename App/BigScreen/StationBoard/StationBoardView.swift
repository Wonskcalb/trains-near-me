import SNCFCore
import SwiftUI

/// One station's departures in the detail column — what a "Go to station" pick or the NEAR ME row opens —
/// drawn as a line map: the station on the left edge, one lane per terminus flowing right, the termini
/// split by side of the line above and below a shared time axis, and every train a stop at its time. A
/// lane opens that journey unsaved in the station hall board; pinning the station for Wall mode is the one
/// action that belongs to the station itself.
struct StationBoardView: View {
    let station: Station
    /// A frozen anchor for the `#Preview`; nil follows the real clock.
    private let frozenNow: Date?

    init(station: Station, now: Date? = nil) {
        self.station = station
        frozenNow = now
    }

    // `.everyMinute` moves the stops left, the "in 7′" countdowns and drops departed trains; the fetch is
    // keyed on the station and ⌘R, not on the time, so a tick never costs a request.
    var body: some View {
        TimelineView(.everyMinute) { context in
            StationLinesBoard(station: station, now: frozenNow ?? context.date)
        }
    }
}

/// What the header's picker trades: a short look ahead with room for every label, or the whole evening.
private enum LinesRange: String, CaseIterable {
    case nextTwoHours = "NEXT 2 H"
    case tonight = "TONIGHT"
}

/// Headsigns that came without a stop_area, resolved through the station search the first time they are
/// tapped and remembered for the session: the same terminus never costs a second `places` request.
@MainActor private enum TerminusNames {
    static var resolved: [String: Station] = [:]
}

private struct StationLinesBoard: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model
    let station: Station
    let now: Date

    @State private var board: StationDayBoard?
    @State private var fetchedAt: Date?
    @State private var pinned: Station?
    @State private var range = LinesRange.nextTwoHours
    @State private var openFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 44).padding(.top, 28).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ground.ignoresSafeArea())
        // One request on open, on ⌘R and every five minutes: the whole evening comes in that one answer,
        // and the stops and countdowns are recomputed from `now` in between.
        .task(id: "\(station.id)-\(model.refreshTick)") {
            while !Task.isCancelled {
                let at = Date()
                board = await data.stationBoard.serviceDayBoard(for: station, at: at)
                fetchedAt = at
                pinned = await data.leaveBy.pinnedStation()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    // MARK: Header

    // On a narrow column (iPad portrait, split view) the controls drop under the title instead of
    // wrapping the picker's words.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                title
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 14) { controls; legend }
            }
            VStack(alignment: .leading, spacing: 12) {
                title
                controls
                legend
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            freshness
            rangePicker
            pinButton
        }
        .fixedSize()
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEPARTURES · STATION").font(.mono(11, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Color.inkSecondary)
            Text(station.name).font(.system(size: 40, weight: .bold)).foregroundStyle(Color.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let openFailure {
                Text(openFailure).font(.system(size: 13)).foregroundStyle(Color.caution)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var freshness: some View {
        HStack(spacing: 7) {
            // Amber-free freshness: green while the last answer is recent, caution once it is old.
            Circle().fill(isStale ? Color.caution : Color.soon).frame(width: 7, height: 7)
            Text(fetchedAt.map { "Updated \(HallFormat.hm($0))" } ?? "Updating…")
                .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var isStale: Bool { fetchedAt.map { now.timeIntervalSince($0) > 30 * 60 } ?? false }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { NextDot(size: 11, ring: 2); Text("next") }
            HStack(spacing: 6) { LinePill(text: "+12", status: .delayed, size: 10.5); Text("late") }
            HStack(spacing: 6) { LinePill(text: "+24", status: .severelyDelayed, size: 10.5); Text("very late") }
            HStack(spacing: 6) { Text("19:05").strikethrough(); Text("cancelled") }
        }
        .font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(LinesRange.allCases, id: \.self) { option in
                Button { range = option } label: {
                    Text(option.rawValue).font(.mono(11.5, weight: .semibold)).tracking(1)
                        .foregroundStyle(range == option ? Color.ink : Color.inkSecondary)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(range == option ? Color.surface : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .shadow(color: .black.opacity(range == option ? 0.18 : 0), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == option ? .isSelected : [])
            }
        }
        .padding(3).background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
    }

    private var pinButton: some View {
        Button {
            Task {
                let target: Station? = isPinned ? nil : station
                await data.leaveBy.pin(target)
                pinned = target
            }
        } label: {
            Label(isPinned ? "Pinned for Wall mode" : "Pin for Wall mode", systemImage: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 14).frame(height: 38)
                .background(Color.raised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isPinned ? "Pinned" : "Not pinned")
    }

    private var isPinned: Bool { pinned?.id == station.id }

    private var footer: some View {
        HStack {
            Text("Data © SNCF · Not affiliated with SNCF")
            Spacer()
            Text("Tap a terminus to open its journey · ⌘R")
        }
        .font(.mono(11, weight: .medium)).tracking(0.3).foregroundStyle(Color.inkSecondary)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let board {
            // Tomorrow's first trains join tonight's lanes past the axis break; when nothing runs tonight
            // the river starts at the break, so the end-of-service card is only for a night with no morning.
            let lanes = StationLines.lanes(from: BoardReading.departures(board.state) + board.tomorrow, now: now)
            if !lanes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if board.state == .noService {
                        Text("No service tonight · every remaining train is cancelled")
                            .font(.mono(12, weight: .semibold)).tracking(0.6).foregroundStyle(Color.stop)
                    }
                    LineMap(input: MapInput(station: station, lanes: lanes, now: now, tonight: range == .tonight), open: open)
                }
            } else {
                switch board.state {
                case .departures:
                    note("No more departures", "Every train fetched has left. ⌘R looks again.")
                case .endOfService(let first):
                    VStack { EndOfServiceCard(first: first); Spacer(minLength: 0) }.padding(.top, 24)
                case .noService:
                    note("No service", "Every remaining train is cancelled.")
                case .noTrains:
                    note("No departures", "Nothing leaves this station right now.")
                case .unavailable(let error):
                    note("Board unavailable", error.appDescription)
                }
            }
        } else {
            ProgressView().tint(.amberText).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
    }

    // MARK: Opening a journey

    /// The journey station → terminus, unsaved, in the station hall board. A terminus that came without
    /// a stop_area is looked up by its headsign only now, when someone asked for it.
    private func open(_ terminus: Station?, _ name: String) {
        openFailure = nil
        Task {
            guard let target = await resolve(terminus, name), target.id != station.id else {
                openFailure = "Couldn’t find a station called \(name)."
                return
            }
            model.open(temporary: Leg(from: station, to: target))
        }
    }

    private func resolve(_ terminus: Station?, _ name: String) async -> Station? {
        if let terminus { return terminus }
        if let known = TerminusNames.resolved[name] { return known }
        // SNCF headsigns read "Rives (Rives)": the town in brackets only blurs the search.
        let query = name.components(separatedBy: " (").first ?? name
        guard let found = try? await data.stationSearch.search(query).first else { return nil }
        TerminusNames.resolved[name] = found
        return found
    }
}

// MARK: - The map

/// What one frame of the map is drawn from. Equatable so a tick or a reload can be diffed against the
/// frame before it, which is how a departing train is told apart from a station or range change.
private struct MapInput: Equatable {
    let station: Station
    let lanes: [StationLane]
    let now: Date
    let tonight: Bool
}

/// Everything the map draws, in one coordinate space: the Canvas strokes the lanes and the axis from it,
/// and the stops and labels are views positioned on the same numbers so they can be buttons.
private struct MapGeometry {
    struct Lane {
        let lane: StationLane
        let y: CGFloat
        let path: StationLines.LanePath
        let above: Bool
        let stops: [Stop]
        let summary: (text: String, color: Color)?
    }

    struct Stop: Identifiable {
        enum Kind { case next, onTime, delayed, cancelled }
        let id: String
        let train: TrainDeparture
        let kind: Kind
        let x: CGFloat
        /// The timetabled slot a delayed train slid off, drawn as a hollow ghost.
        let ghostX: CGFloat?
        let labelWidth: CGFloat
        var row: StationLines.LabelRow = .below

        /// Where the label sits for a stop drawn at `x` on a lane at `laneY`: the next train's chip starts
        /// just left of its dot, the others are centred on theirs. nil when the label is hidden.
        func labelCenter(x: CGFloat, laneY: CGFloat) -> CGPoint? {
            guard row != .hidden else { return nil }
            return CGPoint(x: kind == .next ? x - 14 + (labelWidth + 40) / 2 : x, y: laneY + (row == .below ? 30 : -30))
        }
    }

    let size: CGSize
    let station: Station
    let lanes: [Lane]
    let stationX: CGFloat = 34
    let stationY: CGFloat
    let capsuleHeight: CGFloat
    let x0: CGFloat, x1: CGFloat, curveEnd: CGFloat, laneEnd: CGFloat, terminusWidth: CGFloat
    let pitch: CGFloat
    let axis: StationLines.Axis
    let hours: [Date], quarters: [Date]
    let groupLabels: (above: String?, below: String?)

    func x(_ date: Date) -> CGFloat {
        x0 + CGFloat(axis.fraction(date)) * (x1 - x0)
    }

    var top: CGFloat { (lanes.first?.y ?? stationY) - 56 }
    var bottom: CGFloat { max(lanes.last?.y ?? stationY, stationY) + 56 }

    init(_ input: MapInput, size: CGSize) {
        self.init(station: input.station, lanes: input.lanes, now: input.now, tonight: input.tonight, size: size)
    }

    init(station: Station, lanes input: [StationLane], now: Date, tonight: Bool, size: CGSize) {
        self.size = size
        self.station = station
        // Tomorrow's trains ride the same lanes; the axis folds the night between them and tonight's.
        let trains = input.flatMap(\.trains)
        let isTomorrow = { (train: TrainDeparture) in BoardState.isLaterServiceDay(train.scheduledDeparture, than: now) }
        let axis = StationLines.axis(now: now, tonight: tonight,
                                     lastTonight: trains.filter { !isTomorrow($0) }.map(\.expectedDeparture).max(),
                                     firstTomorrow: trains.filter(isTomorrow).map { min($0.scheduledDeparture, $0.expectedDeparture) }.min(),
                                     calendar: SNCFTime.calendar)
        self.axis = axis
        let end = axis.end
        let marks = StationLines.marks(from: now, to: end, calendar: SNCFTime.calendar)
        hours = marks.hours.filter { !axis.isFolded($0) }
        quarters = marks.quarters.filter { !axis.isFolded($0) }

        // The mockup's proportions at 1288 pt, squeezed on a narrow column: the axis gives first.
        terminusWidth = min(216, max(140, size.width * 0.17))
        laneEnd = size.width - terminusWidth - 6
        x1 = laneEnd - 30
        x0 = min(386, max(150, size.width * 0.3))
        curveEnd = x0 - 30

        let bearings = input.map { lane in lane.terminus.map { StationLines.bearing(from: station, to: $0) } }
        let sides = StationLines.sides(for: bearings)
        let rows = sides.above.count + 1 + sides.below.count
        // ~130 pt in the mockup, ~90 at eight lanes, never under 56, where a lane still holds one label row.
        pitch = min(130, max(56, (size.height - 120) / CGFloat(rows - 1)))
        let firstY = max(60, (size.height - CGFloat(rows - 1) * pitch) / 2)
        stationY = firstY + CGFloat(sides.above.count) * pitch

        let order = sides.above + sides.below
        let n = order.count
        let exitGap: CGFloat = 14
        capsuleHeight = max(96, CGFloat(n - 1) * exitGap + 40)

        func label(_ fan: [Int]) -> String? {
            // Named after the fan's busiest terminus, and the compass point it lies at.
            // "Other" is not a direction, so it never names a side.
            guard let busiest = fan.filter({ !input[$0].isOther })
                .max(by: { input[$0].trains.count < input[$1].trains.count }) else { return nil }
            let name = "TOWARDS " + input[busiest].name.uppercased()
            return bearings[busiest].map { "\(StationLines.compass($0)) · \(name)" } ?? name
        }
        groupLabels = (label(sides.above), label(sides.below))

        var lanes: [Lane] = []
        let (x0, x1) = (self.x0, self.x1)
        let scale = { (date: Date) in x0 + CGFloat(axis.fraction(date)) * (x1 - x0) }
        let narrow = size.width < 700
        let allowAbove = pitch >= 88
        for (k, index) in order.enumerated() {
            let above = k < sides.above.count
            let y = above ? firstY + CGFloat(k) * pitch : stationY + CGFloat(k - sides.above.count + 1) * pitch
            let exitY = stationY + (CGFloat(k) - CGFloat(n - 1) / 2) * exitGap
            let lane = input[index]
            let shown = lane.trains.filter { ($0.isCancelled ? $0.scheduledDeparture : $0.expectedDeparture) <= end }
            var stops = shown.map { train in
                // Keyed on the train, not its position: an open popover stays on it when an earlier one
                // leaves, and a departure is told by its key going missing from one frame to the next.
                let key = train.vehicleJourneyID
                    ?? "\(train.trainNumber ?? "")@\(Int(train.scheduledDeparture.timeIntervalSinceReferenceDate))"
                return Self.stop(train, id: "\(lane.id)-\(key)", isNext: train == lane.next, other: lane.isOther, x: scale, now: now)
            }
            // The next train's label goes first, so it is never the one pushed up or hidden.
            let placement = stops.indices.sorted { (stops[$0].kind != .next ? 1 : 0, $0) < (stops[$1].kind != .next ? 1 : 0, $1) }
                .filter { !narrow || stops[$0].kind == .next }
            let spans = placement.map { i -> ClosedRange<Double> in
                let left = stops[i].kind == .next ? stops[i].x - 14 : stops[i].x - stops[i].labelWidth / 2
                return Double(left)...Double(left + stops[i].labelWidth)
            }
            for i in stops.indices { stops[i].row = .hidden }
            for (i, row) in zip(placement, StationLines.labelRows(spans, allowAbove: allowAbove)) { stops[i].row = row }
            let path = StationLines.LanePath(stationX: Double(stationX), exitY: Double(exitY), y: Double(y),
                                             curveEnd: Double(curveEnd), laneEnd: Double(laneEnd))
            lanes.append(Lane(lane: lane, y: y, path: path, above: above, stops: stops,
                              summary: Self.summary(lane, shown: shown)))
        }
        self.lanes = lanes
    }

    private static func stop(_ train: TrainDeparture, id: String, isNext: Bool, other: Bool,
                             x: (Date) -> CGFloat, now: Date) -> Stop {
        // "+?" (a delay announced without a figure) gets the late pill, but no ghost: there is no slot to slide.
        let delayed = train.status == .delayed || train.status == .severelyDelayed || train.status == .unknown
        let slid = delayed && (train.delayMinutes ?? 0) > 0
        let kind: Stop.Kind = isNext ? .next : train.isCancelled ? .cancelled : delayed ? .delayed : .onTime
        let time = HallFormat.hm(train.isCancelled ? train.scheduledDeparture : train.expectedDeparture)
        var width = StationLines.monoWidth(time, size: kind == .next ? 17 : 16)
        switch kind {
        case .next: width += 16 + 7 + StationLines.monoWidth(LineSpeech.countdown(train.expectedDeparture, from: now), size: 16)
        case .onTime: break
        case .delayed, .cancelled: width += 7 + LinePill.width(LinePill.text(train), size: 12)
        }
        if kind == .next && delayed { width += 7 + LinePill.width(LinePill.text(train), size: 12) }
        if other { width += 7 + StationLines.monoWidth(train.terminus?.name ?? train.direction ?? "—", size: 13) }
        let at = train.isCancelled ? train.scheduledDeparture : train.expectedDeparture
        return Stop(id: id, train: train, kind: kind, x: x(max(now, at)),
                    ghostX: slid ? x(max(now, train.scheduledDeparture)) : nil, labelWidth: CGFloat(width))
    }

    /// "1 DELAYED · EVERY 30 MIN" under the terminus: what is wrong first, in its colour, then how often.
    private static func summary(_ lane: StationLane, shown: [TrainDeparture]) -> (text: String, color: Color)? {
        var parts: [String] = []
        let delayed = shown.filter { $0.status == .delayed || $0.status == .severelyDelayed || $0.status == .unknown }
        let cancelled = shown.filter(\.isCancelled)
        if !delayed.isEmpty { parts.append("\(delayed.count) DELAYED") }
        if !cancelled.isEmpty { parts.append("\(cancelled.count) CANCELLED") }
        if shown.isEmpty, let next = lane.next { parts.append("NEXT \(HallFormat.hm(next.expectedDeparture))") }
        if let every = StationLines.frequency(of: shown.map(\.scheduledDeparture)) { parts.append(every) }
        guard !parts.isEmpty else { return nil }
        let color: Color = !cancelled.isEmpty || delayed.contains { $0.status == .severelyDelayed } ? .stop
            : delayed.isEmpty ? .inkSecondary : .caution
        return (parts.joined(separator: " · "), color)
    }
}

/// The map, and the one thing it remembers between frames: a departure in flight. At rest it is a plain
/// view of `input`; nothing animates or schedules between departures, so an idle board costs nothing.
private struct LineMap: View {
    let input: MapInput
    let open: (Station?, String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStop: String?
    /// The frame on screen. It trails `input` by the one update `onChange` needs to see both, so a
    /// departure starts from what was drawn rather than flashing the new layout first.
    @State private var shown: MapInput?
    /// The frame a departure animates away from, while it runs.
    @State private var departedFrom: MapInput?
    @State private var elapsed: Double = 0

    var body: some View {
        GeometryReader { geo in
            MapFrame(map: MapGeometry(shown ?? input, size: geo.size),
                     from: departedFrom.map { MapGeometry($0, size: geo.size) },
                     elapsed: elapsed, reduceMotion: reduceMotion, selectedStop: $selectedStop, open: open)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .onChange(of: input) { old, new in advance(from: old, to: new, size: geo.size) }
        }
    }

    private func advance(from old: MapInput, to new: MapInput, size: CGSize) {
        shown = new
        // Only a train leaving is animated: a different station, a range change or a lane coming or going
        // redraws at once. ponytail: one departure at a time, a second landing mid-flight just jumps; the
        // two only meet when a reload lands within a second of a minute tick.
        guard departedFrom == nil, old.station == new.station, old.tonight == new.tonight else { return }
        let before = MapGeometry(old, size: size), after = MapGeometry(new, size: size)
        let kept = Set(after.lanes.flatMap { $0.stops.map(\.id) })
        guard before.lanes.map(\.lane.id) == after.lanes.map(\.lane.id),
              before.lanes.contains(where: { $0.stops.contains { !kept.contains($0.id) } }) else { return }
        departedFrom = old
        // One linear clock for the whole exit; `DepartureClock` shapes each part of it. A single value
        // keeps the parts in step and lets a frame be drawn at any instant.
        let total = DepartureClock.duration(reduceMotion: reduceMotion)
        withAnimation(.linear(duration: total)) { elapsed = total } completion: {
            departedFrom = nil
            elapsed = 0
        }
    }
}

/// Where a departure stands `elapsed` seconds in, and every timing the map reads from it: the label fades
/// first, then the dot slides back along its lane while the others settle, then the new next pastille.
private struct DepartureClock {
    let elapsed: Double
    let reduceMotion: Bool

    /// Under Reduce Motion nothing travels: the label and the dot fade together and the rest just lands.
    static func duration(reduceMotion: Bool) -> Double { reduceMotion ? 0.2 : 1.1 }

    private func phase(from start: Double, over length: Double) -> Double { min(1, max(0, (elapsed - start) / length)) }

    var labelOpacity: Double {
        reduceMotion ? 1 - phase(from: 0, over: 0.2) : 1 - UnitCurve.easeOut.value(at: phase(from: 0, over: 0.22))
    }
    /// How much of its way back to the station the dot has come, by arc length. Ease-in, like a train
    /// pulling out: slow off the stop, quick into the curve.
    var slide: Double { reduceMotion ? 0 : UnitCurve.easeIn.value(at: phase(from: 0.2, over: 0.7)) }
    /// Gone by two thirds of the way, before it reaches the capsule.
    var dotOpacity: Double { reduceMotion ? labelOpacity : 1 - min(1, max(0, (slide - 0.1) / 0.55)) }
    /// The rest of the lane settling into the new NOW, and the label rows recomputed for it.
    var rebalance: Double { reduceMotion ? 1 : UnitCurve.easeInOut.value(at: phase(from: 0.2, over: 0.6)) }
    var pastilleScale: Double {
        reduceMotion ? 1 : 0.6 + 0.4 * Spring(duration: 0.5, bounce: 0.3).value(target: 1.0, time: max(0, elapsed - 0.35))
    }
    var pastilleOpacity: Double { reduceMotion ? 1 : phase(from: 0.35, over: 0.15) }
}

/// One frame of the map, `elapsed` seconds into a departure when there is one. Animatable on that one
/// number, so the body is re-run each frame only while a train leaves, and a frame can be drawn at any
/// instant of it.
private struct MapFrame: View, Animatable {
    let map: MapGeometry
    /// The frame a departure leaves from; nil at rest, when the map is just `map`.
    let from: MapGeometry?
    var elapsed: Double
    let reduceMotion: Bool
    @Binding var selectedStop: String?
    let open: (Station?, String) -> Void

    nonisolated var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    @Environment(\.colorScheme) private var scheme

    private var station: Station { map.station }

    var body: some View {
        let clock = from.map { _ in DepartureClock(elapsed: elapsed, reduceMotion: reduceMotion) }
        let blend = Blend(map: map, from: from, r: CGFloat(clock?.rebalance ?? 1))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(blend, in: &context) }.accessibilityHidden(true)
            axisLabels(blend)
            ForEach(map.lanes, id: \.lane.id) { lane in laneButton(lane) }
            ForEach(map.lanes, id: \.lane.id) { lane in
                ForEach(lane.stops) { stop in
                    stopLabels(stop, lane: lane, blend: blend, clock: clock)
                    stopButton(stop, lane: lane, blend: blend, clock: clock)
                }
            }
            if let clock, let from {
                ForEach(blend.departed, id: \.stop.id) { item in departing(item.stop, lane: item.lane, from: from, clock: clock) }
            }
            stationMark
        }
    }

    private var now: Date { map.axis.start }
    private func rail(_ lane: MapGeometry.Lane) -> Color { lane.above ? .railWarm : .railCool }
    /// The ring round the station and the next stop: the ground on the dark board, ink on paper.
    private var ring: Color { scheme == .dark ? .ground : .ink }

    // MARK: Canvas

    private func draw(_ blend: Blend, in context: inout GraphicsContext) {
        let map = blend.map
        for hour in map.hours {
            let x = blend.x(hour)
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: map.top)); $0.addLine(to: CGPoint(x: x, y: map.bottom)) },
                           with: .color(.ink.opacity(0.06)), lineWidth: 1.5)
        }
        // A quarter tick gives way to an hour label or the NOW flag: on a narrow column they would overprint.
        let hourXs = map.hours.map(blend.x)
        for quarter in map.quarters {
            let x = blend.x(quarter)
            guard x < map.x1, x - map.x0 > 50, hourXs.allSatisfy({ abs($0 - x) > 24 }) else { continue }
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: map.stationY - 4)); $0.addLine(to: CGPoint(x: x, y: map.stationY + 4)) },
                           with: .color(.sleeper), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        if let gap = map.axis.gap {
            // The folded night, as on Lanes: a faint navy wash between two zig-zag cuts, under the lanes so
            // they read as running on through it into the morning.
            let a = blend.x(gap.start), b = blend.x(gap.end)
            context.fill(Path(CGRect(x: a, y: map.top, width: b - a, height: map.bottom - map.top)),
                         with: .color(TomorrowSplit.navy.opacity(0.14)))
            for edge in [a, b] {
                var zig = Path()
                zig.move(to: CGPoint(x: edge, y: map.top))
                var y = map.top, side: CGFloat = 1
                while y < map.bottom {
                    y = min(map.bottom, y + 6)
                    zig.addLine(to: CGPoint(x: edge + 3 * side, y: y))
                    side = -side
                }
                context.stroke(zig, with: .color(.inkSecondary), lineWidth: 1.3)
            }
        }
        context.stroke(Path { $0.move(to: CGPoint(x: map.x0, y: map.top)); $0.addLine(to: CGPoint(x: map.x0, y: map.bottom)) },
                       with: .color(.inkSecondary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))

        for lane in map.lanes {
            let color = rail(lane)
            // Each lane leaves the capsule level, peels off sooner the further it has to climb, and bends
            // into its row with one horizontal-in, horizontal-out cubic, so no two lanes ever cross.
            let track = lane.path
            var path = Path()
            path.move(to: track.start)
            path.addLine(to: track.peel)
            path.addCurve(to: track.curveEnd, control1: track.control1, control2: track.control2)
            path.addLine(to: track.end)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.stroke(Path { $0.move(to: CGPoint(x: map.laneEnd, y: lane.y - 14)); $0.addLine(to: CGPoint(x: map.laneEnd, y: lane.y + 14)) },
                           with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // The time-track grammar: a hollow ghost at the timetabled slot, a dashed arc to where it leaves.
            for stop in lane.stops {
                guard let gx = blend.ghostX(stop) else { continue }
                let x = blend.x(stop)
                let ink = stop.train.status.tableauInk
                var arc = Path()
                arc.move(to: CGPoint(x: gx, y: lane.y - 7))
                arc.addQuadCurve(to: CGPoint(x: x, y: lane.y - 9), control: CGPoint(x: (gx + x) / 2, y: lane.y - 34))
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
                let ghost = Path(ellipseIn: CGRect(x: gx - 5, y: lane.y - 5, width: 10, height: 10))
                context.fill(ghost, with: .color(.surface))
                context.stroke(ghost, with: .color(ink), lineWidth: 1.8)
            }
        }

        // The station on top of the lanes' roots, so they all seem to leave from inside it.
        let capsule = Path(roundedRect: CGRect(x: map.stationX - 20, y: map.stationY - map.capsuleHeight / 2,
                                               width: 40, height: map.capsuleHeight), cornerRadius: 20)
        context.fill(capsule, with: .color(.amber))
        context.stroke(capsule, with: .color(ring), lineWidth: scheme == .dark ? 5 : 3)
    }

    // MARK: Axis and station

    @ViewBuilder private func axisLabels(_ blend: Blend) -> some View {
        ForEach(map.hours, id: \.self) { hour in
            // The NOW flag owns its stretch of the axis.
            if blend.x(hour) - map.x0 > 80 {
                Text(HallFormat.hm(hour)).font(.mono(12.5, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(Color.inkSecondary).fixedSize()
                    .position(x: blend.x(hour), y: map.stationY)
            }
        }
        Text("NOW \(HallFormat.hm(now))").font(.mono(11, weight: .bold)).tracking(0.8)
            .foregroundStyle(Color.ground).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 6))
            .position(x: map.x0, y: map.stationY)
            .accessibilityLabel("Now \(HallFormat.hm(now))")
        if let gap = map.axis.gap {
            // The night's navy, as on the split row of the boards, so the break reads as the same cut. Held
            // clear of the NOW flag when the river starts at the break.
            Label("TOMORROW", systemImage: "moon.fill")
                .font(.mono(10, weight: .bold)).tracking(1).foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(TomorrowSplit.navy, in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
                .position(x: max((blend.x(gap.start) + blend.x(gap.end)) / 2, map.x0 + 92), y: map.stationY)
                .accessibilityLabel("End of service. Tomorrow after the break")
        }
        if let above = map.groupLabels.above, let first = map.lanes.first {
            groupLabel(above).position(x: (map.curveEnd - 8) / 2, y: first.y - 40)
        }
        if let below = map.groupLabels.below, let last = map.lanes.last {
            groupLabel(below).position(x: (map.curveEnd - 8) / 2, y: last.y + 40)
        }
    }

    /// Kept left of where the lanes straighten, so on a narrow column it truncates rather than run into
    /// the bottom lane's time labels.
    private func groupLabel(_ text: String) -> some View {
        Text(text).font(.mono(11, weight: .semibold)).tracking(1.3).foregroundStyle(Color.inkSecondary)
            .lineLimit(1).frame(width: map.curveEnd - 8, alignment: .leading).accessibilityAddTraits(.isHeader)
    }

    private var stationMark: some View {
        Text(station.name.uppercased()).font(.mono(13, weight: .bold)).tracking(1.6).foregroundStyle(Color.ink)
            .fixedSize().position(x: map.stationX, y: map.stationY + map.capsuleHeight / 2 + 20)
            .accessibilityHidden(true)
    }

    // MARK: Lanes

    /// The lane's row and its terminus name, one button with the whole lane spoken as one sentence.
    private func laneButton(_ lane: MapGeometry.Lane) -> some View {
        let height = min(map.pitch - 8, 64)
        return Button { if !lane.lane.isOther { open(lane.lane.terminus, lane.lane.name) } } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: map.laneEnd + 18 - map.curveEnd)
                VStack(alignment: .leading, spacing: 5) {
                    Text(lane.lane.name).font(.system(size: 21, weight: .semibold)).foregroundStyle(Color.ink)
                        .lineLimit(2).minimumScaleFactor(0.75).lineSpacing(-2)
                    if let summary = lane.summary {
                        Text(summary.text).font(.mono(10.5, weight: .semibold)).tracking(1.1)
                            .foregroundStyle(summary.color).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(width: map.terminusWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(width: map.size.width - map.curveEnd, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: (map.curveEnd + map.size.width) / 2, y: lane.y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LineSpeech.lane(lane.lane, shown: lane.stops.map(\.train), now: now))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Stops

    /// Whether this stop is the new next pastille arriving: it grows in on its own spring, after the rest.
    private func pops(_ stop: MapGeometry.Stop, before: MapGeometry.Stop?, clock: DepartureClock?) -> Bool {
        clock != nil && stop.kind == .next && before != nil && before?.kind != .next
    }

    private func stopButton(_ stop: MapGeometry.Stop, lane: MapGeometry.Lane, blend: Blend, clock: DepartureClock?) -> some View {
        let before = blend.before[stop.id]
        let pops = pops(stop, before: before, clock: clock)
        return Button { selectedStop = selectedStop == stop.id ? nil : stop.id } label: {
            ZStack {
                // A stop that changes kind (the next one taking over) crossfades from the mark it had.
                if let before, before.kind != stop.kind { mark(before, lane: lane).opacity(1 - blend.r) }
                mark(stop, lane: lane)
                    .scaleEffect(pops ? clock?.pastilleScale ?? 1 : 1)
                    .opacity(pops ? clock?.pastilleOpacity ?? 1 : before?.kind == stop.kind ? 1 : blend.r)
            }
            .frame(width: 30, height: 30).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { selectedStop == stop.id },
                                      set: { if !$0, selectedStop == stop.id { selectedStop = nil } })) {
            LaneTrainPopover(train: stop.train, leg: Leg(from: station, to: destination(stop.train, lane: lane.lane)))
        }
        .position(x: blend.x(stop), y: lane.y)
        .accessibilityLabel(LineSpeech.stop(stop.train, to: destination(stop.train, lane: lane.lane).name))
    }

    /// The popover's "to …" and Watch's notification text only need a name, so a headsign-only terminus
    /// gets a placeholder station rather than a search.
    private func destination(_ train: TrainDeparture, lane: StationLane) -> Station {
        train.terminus ?? lane.terminus
            ?? Station(id: "", name: train.direction ?? lane.name, latitude: 0, longitude: 0)
    }

    @ViewBuilder private func mark(_ stop: MapGeometry.Stop, lane: MapGeometry.Lane) -> some View {
        switch stop.kind {
        case .next:
            NextDot(size: 20, ring: 3)
        case .onTime:
            Circle().fill(Color.surface).overlay(Circle().stroke(rail(lane), lineWidth: 3)).frame(width: 14, height: 14)
        case .delayed:
            Circle().fill(stop.train.status.tableauInk).overlay(Circle().stroke(Color.ground, lineWidth: 2.5))
                .frame(width: 16, height: 16)
        case .cancelled:
            ZStack {
                Circle().fill(Color.surface).overlay(Circle().stroke(Color.stop, lineWidth: 2.2))
                Path { p in
                    p.move(to: CGPoint(x: 4.5, y: 4.5)); p.addLine(to: CGPoint(x: 11.5, y: 11.5))
                    p.move(to: CGPoint(x: 11.5, y: 4.5)); p.addLine(to: CGPoint(x: 4.5, y: 11.5))
                }
                .stroke(Color.stop, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 16, height: 16)
        }
    }

    /// A stop's label, travelling with its dot. One that keeps its kind slides to its new row; one that
    /// changes kind or shows up crossfades, and the new next chip grows in with the pastille.
    @ViewBuilder private func stopLabels(_ stop: MapGeometry.Stop, lane: MapGeometry.Lane, blend: Blend, clock: DepartureClock?) -> some View {
        let before = blend.before[stop.id]
        let x = blend.x(stop)
        let old = before?.labelCenter(x: x, laneY: lane.y)
        let new = stop.labelCenter(x: x, laneY: lane.y)
        if let before, let old, let new, before.kind == stop.kind {
            placedLabel(stop, lane: lane, now: now)
                .position(x: new.x, y: old.y + (new.y - old.y) * blend.r)
        } else {
            if let before, let old, let from {
                placedLabel(before, lane: lane, now: from.axis.start).position(old).opacity(1 - blend.r)
            }
            if let new {
                let pops = pops(stop, before: before, clock: clock)
                placedLabel(stop, lane: lane, now: now)
                    .scaleEffect(pops ? clock?.pastilleScale ?? 1 : 1, anchor: .leading)
                    .position(new)
                    .opacity(pops ? clock?.pastilleOpacity ?? 1 : blend.r)
            }
        }
    }

    /// The train that just left: its label fades where it stood, then its dot rides back along the lane
    /// into the station, fading on the way. Only there for the eye, so VoiceOver never meets it.
    private func departing(_ stop: MapGeometry.Stop, lane: MapGeometry.Lane, from: MapGeometry, clock: DepartureClock) -> some View {
        let start = lane.path.distance(toX: Double(stop.x))
        return ZStack(alignment: .topLeading) {
            if let center = stop.labelCenter(x: stop.x, laneY: lane.y) {
                placedLabel(stop, lane: lane, now: from.axis.start).position(center).opacity(clock.labelOpacity)
            }
            mark(stop, lane: lane)
                .position(lane.path.point(atDistance: start * (1 - clock.slide)))
                .opacity(clock.dotOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placedLabel(_ stop: MapGeometry.Stop, lane: MapGeometry.Lane, now: Date) -> some View {
        label(stop, other: lane.lane.isOther, now: now)
            .frame(width: stop.labelWidth + 40, height: 28, alignment: stop.kind == .next ? .leading : .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func label(_ stop: MapGeometry.Stop, other: Bool, now: Date) -> some View {
        let train = stop.train
        let time = HallFormat.hm(train.isCancelled ? train.scheduledDeparture : train.expectedDeparture)
        return HStack(spacing: 7) {
            switch stop.kind {
            case .next:
                Text(time).font(.mono(17, weight: .bold)).foregroundStyle(Color.onAmber)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.amber, in: RoundedRectangle(cornerRadius: 7))
                if [.delayed, .severelyDelayed, .unknown].contains(train.status) {
                    LinePill(text: LinePill.text(train), status: train.status, size: 12)
                }
                let minutes = Int(train.expectedDeparture.timeIntervalSince(now) / 60)
                Text(LineSpeech.countdown(train.expectedDeparture, from: now)).font(.mono(16, weight: .bold))
                    .foregroundStyle(minutes <= 10 ? Color.soon : Color.ink)
            case .onTime:
                Text(time).font(.mono(16, weight: .medium)).foregroundStyle(Color.ink)
            case .delayed:
                Text(time).font(.mono(16, weight: .semibold)).foregroundStyle(train.status.tableauInk)
                LinePill(text: LinePill.text(train), status: train.status, size: 12)
            case .cancelled:
                Text(time).font(.mono(16, weight: .semibold)).foregroundStyle(Color.stop).strikethrough()
                LinePill(text: "CANC.", status: .cancelled, size: 11)
            }
            if other {
                Text(train.terminus?.name ?? train.direction ?? "—").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.85))
            }
        }
        .fixedSize()
    }
}

/// One frame between the layout a departure leaves (`from`) and the one it lands on (`map`), `r` of the
/// way: every x is read from both and blended, so the axis, the stops and their labels move as one.
private struct Blend {
    let map: MapGeometry
    let from: MapGeometry?
    let r: CGFloat
    /// The stops as they were, by id.
    let before: [String: MapGeometry.Stop]

    init(map: MapGeometry, from: MapGeometry?, r: CGFloat) {
        self.map = map
        self.from = from
        self.r = r
        before = Dictionary((from?.lanes ?? []).flatMap(\.stops).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * r }

    func x(_ date: Date) -> CGFloat { from.map { lerp($0.x(date), map.x(date)) } ?? map.x(date) }
    func x(_ stop: MapGeometry.Stop) -> CGFloat { before[stop.id].map { lerp($0.x, stop.x) } ?? stop.x }
    func ghostX(_ stop: MapGeometry.Stop) -> CGFloat? {
        guard let ghost = stop.ghostX else { return nil }
        return before[stop.id]?.ghostX.map { lerp($0, ghost) } ?? ghost
    }

    /// The stops `from` had that `map` no longer does: the trains that just left.
    var departed: [(stop: MapGeometry.Stop, lane: MapGeometry.Lane)] {
        let kept = Set(map.lanes.flatMap { $0.stops.map(\.id) })
        return (from?.lanes ?? []).flatMap { lane in lane.stops.filter { !kept.contains($0.id) }.map { ($0, lane) } }
    }
}

/// The amber stop of the next train, ringed so it stands off the lane in both schemes.
private struct NextDot: View {
    @Environment(\.colorScheme) private var scheme
    let size: CGFloat
    let ring: CGFloat

    var body: some View {
        Circle().fill(Color.amber).overlay(Circle().stroke(scheme == .dark ? Color.ground : Color.ink, lineWidth: ring))
            .frame(width: size, height: size)
    }
}

/// `StatusPill`'s colours at the size of a time label: the board's pill is a row badge, two sizes up from
/// what fits beside a stop on a 56 pt lane.
private struct LinePill: View {
    let text: String
    let status: DepartureStatus
    let size: CGFloat

    static func text(_ train: TrainDeparture) -> String {
        train.status == .unknown ? "+?" : "+\(train.delayMinutes ?? 0)"
    }

    static func width(_ text: String, size: Double) -> Double { StationLines.monoWidth(text, size: size) + 14 }

    var body: some View {
        Text(text).font(.mono(size, weight: .bold)).foregroundStyle(status.tableauInk)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status.tableauFill, in: RoundedRectangle(cornerRadius: 7))
            .fixedSize()
    }
}

/// The words for the map: the "in 7′" countdowns and the spoken lane summaries.
private enum LineSpeech {
    /// "in 7′", or "tomorrow" past the axis break, where a countdown would run to hours, as on the boards.
    static func countdown(_ date: Date, from now: Date) -> String {
        if BoardState.isLaterServiceDay(date, than: now) { return "tomorrow" }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "in \(minutes)′" }
        return "in \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// "To Lyon Part-Dieu: next 17:51 in 11 minutes, then 18:21 plus 12, 18:51, 19:21". Past the axis
    /// break the morning's times say so, since the map's fold is drawn, not spoken.
    static func lane(_ lane: StationLane, shown: [TrainDeparture], now: Date) -> String {
        guard let next = lane.next else { return "To \(lane.name): every train cancelled" }
        func said(_ departure: TrainDeparture) -> String {
            (BoardState.isLaterServiceDay(departure.scheduledDeparture, than: now) ? "tomorrow " : "") + train(departure)
        }
        var line = "To \(lane.name): next \(said(next)) in \(minutes(next.expectedDeparture, from: now))"
        let then = shown.filter { $0.scheduledDeparture > next.scheduledDeparture }.map(said)
        if !then.isEmpty { line += ", then " + then.joined(separator: ", ") }
        return line
    }

    static func stop(_ departure: TrainDeparture, to destination: String) -> String {
        var parts = departure.trainNumber.map { ["Train \($0)"] } ?? []
        parts.append(train(departure))
        parts.append("to \(destination)")
        return parts.joined(separator: ", ")
    }

    private static func train(_ train: TrainDeparture) -> String {
        let time = HallFormat.hm(train.scheduledDeparture)
        switch train.status {
        case .onTime: return time
        case .delayed, .severelyDelayed: return "\(time) plus \(train.delayMinutes ?? 0)"
        case .unknown: return "\(time) delayed"
        case .cancelled: return "\(time) cancelled"
        }
    }

    private static func minutes(_ date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

// MARK: - Preview

/// Voiron at 17:40 on the mockup Thursday: Lyon and St-André up the line, Grenoble, Gières and Valence
/// down it, with real coordinates so the sides split the way the mockup draws them, a +12, a +24 that
/// overtakes the 18:28 and a cancellation.
private struct PreviewLines: StationBoardProviding {
    static let standre = Station(id: "stop_area:SNCF:87747345", name: "St-André-le-Gaz", latitude: 45.545100, longitude: 5.528600)
    static let gieres = Station(id: "stop_area:SNCF:87747402", name: "Grenoble Universités-Gières", latitude: 45.185600, longitude: 5.781100)

    static var trains: [TrainDeparture] {
        let f = BigScreenFixtures.self
        func t(_ h: Int, _ m: Int, _ to: Station, _ number: String, delay: Int? = 0, cancelled: Bool = false) -> TrainDeparture {
            TrainDeparture(scheduledDeparture: f.at(h, m), direction: to.name, mode: "TER", delayMinutes: delay,
                           isCancelled: cancelled, trainNumber: number, terminus: to)
        }
        return [
            t(17, 51, f.lyon, "17614"), t(18, 21, f.lyon, "17616", delay: 12), t(18, 51, f.lyon, "17618"), t(19, 21, f.lyon, "17620"),
            t(18, 5, standre, "17710"), t(19, 5, standre, "17712", cancelled: true), t(20, 5, standre, "17714"),
            t(17, 46, f.grenoble, "17613"), t(17, 58, f.grenoble, "17615"), t(18, 16, f.grenoble, "17617", delay: 24),
            t(18, 28, f.grenoble, "17619"), t(18, 46, f.grenoble, "17621"),
            t(18, 10, gieres, "17717"), t(19, 10, gieres, "17719"),
            t(18, 2, f.valence, "17853"), t(19, 2, f.valence, "17855"), t(20, 2, f.valence, "17857"),
        ].sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    func board(for station: Station, at now: Date) async -> BoardState { .departures(Self.trains) }
    func serviceDayBoard(for station: Station, at now: Date) async -> StationDayBoard { StationDayBoard(state: .departures(Self.trains)) }
    func via(forVehicleJourneyID id: String) async -> [String] { [] }

    static var data: BigScreenData {
        let fake = BigScreenData.fake
        return BigScreenData(journeyBoards: fake.journeyBoards, stationBoard: PreviewLines(), trainStops: fake.trainStops,
                             serviceDay: fake.serviceDay, roundTrip: fake.roundTrip, leaveBy: fake.leaveBy,
                             watching: fake.watching, eta: fake.eta, stationSearch: fake.stationSearch)
    }
}

#Preview("Station lines") {
    StationBoardView(station: BigScreenFixtures.voiron, now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .environment(\.bigScreenData, PreviewLines.data)
        .frame(width: 1376, height: 1032)
        .preferredColorScheme(.dark)
}

#Preview("Station lines · late evening") {
    StationBoardView(station: BigScreenFixtures.voiron, now: BigScreenFixtures.lateNow)
        .environment(BigScreenModel())
        .environment(\.bigScreenData, .fakeLateEvening)
        .frame(width: 1376, height: 1032)
}

#if DEBUG
/// The minute ticks come from `.everyMinute`, far too slow to watch a departure by, so this fake clock
/// jumps to just past the next train every three seconds. Previews only; the app never runs it.
private struct DepartingEveryFewSeconds: View {
    @State private var now = BigScreenFixtures.now

    var body: some View {
        StationBoardView(station: BigScreenFixtures.voiron, now: now)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    let next = PreviewLines.trains.map(\.expectedDeparture).filter { $0 > now }.min()
                    now = next?.addingTimeInterval(20) ?? BigScreenFixtures.now
                }
            }
    }
}

#Preview("Station lines · a train leaves every 3 s") {
    DepartingEveryFewSeconds()
        .environment(BigScreenModel())
        .environment(\.bigScreenData, PreviewLines.data)
        .frame(width: 1376, height: 1032)
        .preferredColorScheme(.dark)
}
#endif
