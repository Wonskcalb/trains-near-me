import SNCFCore
import SwiftUI

/// One station's departures in the detail column — what a "Go to station" pick or the NEAR ME row opens —
/// drawn as a star: the station at the centre, one branch per terminus pointing the way the terminus
/// really lies, the next trains along each. A branch opens that journey unsaved in the station hall
/// board; pinning the station for Wall mode is the one action that belongs to the station itself.
struct StationBoardView: View {
    let station: Station
    /// A frozen anchor for the `#Preview`; nil follows the real clock.
    private let frozenNow: Date?

    init(station: Station, now: Date? = nil) {
        self.station = station
        frozenNow = now
    }

    // `.everyMinute` moves the "in 7′" countdowns and drops departed trains; the fetch is keyed on the
    // station and ⌘R, not on the time, so a tick never costs a request.
    var body: some View {
        TimelineView(.everyMinute) { context in
            StationStarBoard(station: station, now: frozenNow ?? context.date)
        }
    }
}

/// What the header's picker trades: a short look ahead with room for more times, or the whole evening.
private enum StarRange: String, CaseIterable {
    case nextTwoHours = "NEXT 2 H"
    case tonight = "TONIGHT"

    /// nil is the whole fetched window, which already ends at the 03:00 service-day close.
    var horizon: TimeInterval? { self == .nextTwoHours ? 2 * 3600 : nil }
    /// Times after the next one, at most; `ViewThatFits` drops them first when a label is short of room.
    var extraTimes: Int { self == .nextTwoHours ? 3 : 5 }
}

/// Headsigns that came without a stop_area, resolved through the station search the first time they are
/// tapped and remembered for the session: the same terminus never costs a second `places` request.
@MainActor private enum TerminusNames {
    static var resolved: [String: Station] = [:]
}

private struct StationStarBoard: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model
    let station: Station
    let now: Date

    @State private var board: BoardState?
    @State private var fetchedAt: Date?
    @State private var pinned: Station?
    @State private var range = StarRange.nextTwoHours
    @State private var openFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ground.ignoresSafeArea())
        // One request on open, on ⌘R and every five minutes: the whole evening comes in that one answer,
        // and the countdowns and departed trains are recomputed from `now` in between.
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

    private var trains: [TrainDeparture] { BoardReading.departures(board) }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEPARTURES · EVERY DIRECTION").font(.mono(11, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Color.inkSecondary)
                Text(station.name).font(.system(size: 38, weight: .bold)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 7) {
                    // Amber-free freshness: green while the last answer is recent, caution once it is old.
                    Circle().fill(isStale ? Color.caution : Color.soon).frame(width: 7, height: 7)
                    Text(subtitle).font(.mono(12)).foregroundStyle(Color.inkSecondary)
                }
                if let openFailure {
                    Text(openFailure).font(.system(size: 13)).foregroundStyle(Color.caution)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            rangePicker
            pinButton
        }
    }

    private var subtitle: String {
        let count = StationStar.branches(from: trains, now: now, maxBranches: .max).count
        let updated = fetchedAt.map { " · updated \(HallFormat.hm($0))" } ?? ""
        return "\(count) destination\(count == 1 ? "" : "s")\(updated)"
    }

    private var isStale: Bool { fetchedAt.map { now.timeIntervalSince($0) > 30 * 60 } ?? false }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(StarRange.allCases, id: \.self) { option in
                Button { range = option } label: {
                    Text(option.rawValue).font(.mono(11.5, weight: .semibold)).tracking(1)
                        .foregroundStyle(range == option ? Color.ink : Color.ink.opacity(0.6))
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(range == option ? Color.ground.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == option ? .isSelected : [])
            }
        }
        .padding(3).background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ink.opacity(0.06), lineWidth: 1))
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
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Color.raised, in: Capsule())
                .overlay(Capsule().stroke(Color.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isPinned ? "Pinned" : "Not pinned")
    }

    private var isPinned: Bool { pinned?.id == station.id }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch board {
        case nil:
            ProgressView().tint(.amberText).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .departures(let trains):
            let branches = StationStar.branches(from: trains, now: now)
            if branches.isEmpty {
                note("No more departures", "Every train fetched has left. ⌘R looks again.")
            } else {
                StarMap(station: station, branches: branches, now: now, range: range, open: open)
            }
        case .endOfService(let first):
            VStack { EndOfServiceCard(first: first); Spacer(minLength: 0) }
        case .noService:
            note("No service", "Every remaining train is cancelled.")
        case .noTrains:
            note("No departures", "Nothing leaves this station right now.")
        case .unavailable(let error):
            note("Board unavailable", error.appDescription)
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

// MARK: - The star

/// The branches round the roundel. Each branch runs as far as its label still fits inside the pane, so
/// the star fills whatever space the detail column has.
private struct StarMap: View {
    let station: Station
    let branches: [StarBranch]
    let now: Date
    let range: StarRange
    let open: (Station?, String) -> Void

    private static let labelGap: CGFloat = 12
    private static let margin: CGFloat = 6
    private static let roundel: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            let spokes = layout(in: geo.size)
            ZStack {
                Canvas { context, _ in
                    for spoke in spokes { draw(spoke, in: &context) }
                }
                .accessibilityHidden(true)
                ForEach(spokes) { spoke in
                    // The rail itself is a tap target too; the label's button is the accessible one.
                    Color.clear.contentShape(Rectangle())
                        .frame(width: max(0, spoke.length - Self.roundel / 2), height: 26)
                        .rotationEffect(.radians(atan2(spoke.end.y - spoke.start.y, spoke.end.x - spoke.start.x)))
                        .position(x: (spoke.start.x + spoke.end.x) / 2 + spoke.direction.dx * Self.roundel / 4,
                                  y: (spoke.start.y + spoke.end.y) / 2 + spoke.direction.dy * Self.roundel / 4)
                        .onTapGesture { if !spoke.branch.isOther { open(spoke.branch.terminus, spoke.branch.name) } }
                        .accessibilityHidden(true)
                    terminusDot(spoke).position(spoke.end).accessibilityHidden(true)
                    BranchLabel(branch: spoke.branch, side: spoke.side, now: now, range: range, open: open)
                        .frame(width: spoke.labelSize.width, height: spoke.labelSize.height, alignment: spoke.side.frameAlignment)
                        .position(spoke.labelCentre)
                }
                StationRoundel(name: station.name).position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Geometry

    private struct Spoke: Identifiable {
        let branch: StarBranch
        let start: CGPoint
        let end: CGPoint
        let direction: CGVector
        let length: CGFloat
        let side: LabelSide
        let labelSize: CGSize
        let labelCentre: CGPoint
        let quiet: Bool
        var id: String { branch.id }
    }

    private func layout(in size: CGSize) -> [Spoke] {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let angles = StationStar.angles(for: branches.map { branch in
            branch.terminus.map { StationStar.bearing(from: station, to: $0) }
        })
        let width = min(260, max(170, size.width * 0.27))
        return zip(branches, angles).map { branch, degrees in
            let θ = degrees * .pi / 180
            let d = CGVector(dx: sin(θ), dy: -cos(θ))
            let side = LabelSide(d)
            let label = CGSize(width: width, height: branch.isOther ? 132 : 62)
            let box = side.box(label, gap: Self.labelGap)
            // The longest run that keeps the label box inside the pane, on each axis it moves along.
            var length = CGFloat.greatestFiniteMagnitude
            if d.dx > 0.001 { length = min(length, (size.width - Self.margin - box.maxX - centre.x) / d.dx) }
            if d.dx < -0.001 { length = min(length, (Self.margin - box.minX - centre.x) / d.dx) }
            if d.dy > 0.001 { length = min(length, (size.height - Self.margin - box.maxY - centre.y) / d.dy) }
            if d.dy < -0.001 { length = min(length, (Self.margin - box.minY - centre.y) / d.dy) }
            length = max(length, Self.roundel / 2 + 36)
            let end = CGPoint(x: centre.x + d.dx * length, y: centre.y + d.dy * length)
            return Spoke(branch: branch, start: centre, end: end, direction: d, length: length, side: side, labelSize: label,
                         labelCentre: CGPoint(x: end.x + box.midX, y: end.y + box.midY),
                         quiet: !BranchReading(branch: branch, now: now, range: range).runsInWindow)
        }
    }

    /// Track: sleepers across, one rail along. Dashed when nothing runs to that terminus in the range.
    private func draw(_ spoke: Spoke, in context: inout GraphicsContext) {
        let d = spoke.direction
        let normal = CGVector(dx: -d.dy, dy: d.dx)
        let from = Self.roundel / 2 + 4
        var sleepers = Path()
        var t = from
        while t < spoke.length - 10 {
            let p = CGPoint(x: spoke.start.x + d.dx * t, y: spoke.start.y + d.dy * t)
            sleepers.move(to: CGPoint(x: p.x - normal.dx * 6, y: p.y - normal.dy * 6))
            sleepers.addLine(to: CGPoint(x: p.x + normal.dx * 6, y: p.y + normal.dy * 6))
            t += 13
        }
        if !spoke.quiet { context.stroke(sleepers, with: .color(.sleeper), lineWidth: 3) }
        var rail = Path()
        rail.move(to: CGPoint(x: spoke.start.x + d.dx * from, y: spoke.start.y + d.dy * from))
        rail.addLine(to: spoke.end)
        context.stroke(rail, with: .color(spoke.quiet ? .inkSecondary.opacity(0.6) : .rail),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: spoke.quiet ? [6, 6] : []))
    }

    /// `RoutePins`' destination: an amber solid dot; a ring for "Other", which is not one place; ink
    /// grey when nothing runs there in the range.
    @ViewBuilder private func terminusDot(_ spoke: Spoke) -> some View {
        if spoke.branch.isOther {
            Circle().strokeBorder(Color.inkSecondary, lineWidth: 2.5).frame(width: 14, height: 14)
                .background(Circle().fill(Color.ground))
        } else {
            Circle().fill(spoke.quiet ? Color.inkSecondary : Color.amber).frame(width: 14, height: 14)
        }
    }
}

/// Which side of its terminus dot a label sits: beside it on a branch that runs sideways, above or below
/// on one that runs up or down, so a label always grows away from the centre.
private enum LabelSide {
    case trailing, leading, top, bottom

    init(_ d: CGVector) {
        if d.dx > 0.38 { self = .trailing } else if d.dx < -0.38 { self = .leading } else { self = d.dy < 0 ? .top : .bottom }
    }

    /// The label's box relative to the dot.
    func box(_ size: CGSize, gap: CGFloat) -> CGRect {
        switch self {
        case .trailing: CGRect(x: gap, y: -size.height / 2, width: size.width, height: size.height)
        case .leading: CGRect(x: -gap - size.width, y: -size.height / 2, width: size.width, height: size.height)
        case .top: CGRect(x: -size.width / 2, y: -gap - size.height, width: size.width, height: size.height)
        case .bottom: CGRect(x: -size.width / 2, y: gap, width: size.width, height: size.height)
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .trailing: .leading
        case .leading: .trailing
        case .top: .bottom
        case .bottom: .top
        }
    }

    var textAlignment: HorizontalAlignment {
        switch self {
        case .trailing: .leading
        case .leading: .trailing
        case .top, .bottom: .center
        }
    }
}

/// The station at the centre: a ring round an ink bar carrying the name in heavy type.
private struct StationRoundel: View {
    let name: String

    var body: some View {
        ZStack {
            Circle().fill(Color.ground).frame(width: 92, height: 92)
            Circle().strokeBorder(Color.amber, lineWidth: 12).frame(width: 92, height: 92)
            Text(name.uppercased()).font(.system(size: 17, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Color.ground).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 14).frame(height: 30).frame(maxWidth: 240)
                .background(Color.ink, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Labels

/// The trains of one branch inside the picked range, and the next one even when it is further out.
private struct BranchReading {
    let branch: StarBranch
    let now: Date
    let range: StarRange

    var inRange: [TrainDeparture] {
        guard let horizon = range.horizon else { return branch.trains }
        return branch.trains.filter { $0.expectedDeparture <= now.addingTimeInterval(horizon) }
    }

    var runsInWindow: Bool { branch.next.map { next in inRange.contains(next) } ?? false }

    /// What the times row lists, in timetable order, with the index of the next train. A next train beyond
    /// the range is still appended: a far-away terminus keeps its branch and says when it is served.
    var timeline: (trains: [TrainDeparture], next: Int?) {
        var trains = inRange
        guard let next = branch.next else { return (trains.isEmpty ? Array(branch.trains.prefix(3)) : trains, nil) }
        if !trains.contains(next) { trains.append(next) }
        return (trains, trains.firstIndex(of: next))
    }
}

private struct BranchLabel: View {
    let branch: StarBranch
    let side: LabelSide
    let now: Date
    let range: StarRange
    let open: (Station?, String) -> Void

    private var reading: BranchReading { BranchReading(branch: branch, now: now, range: range) }

    var body: some View {
        if branch.isOther { other } else { single }
    }

    private var single: some View {
        Button { open(branch.terminus, branch.name) } label: {
            VStack(alignment: side.textAlignment, spacing: 6) {
                Text(branch.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
                times
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StarSpeech.branch(branch, reading: reading, now: now))
        .accessibilityAddTraits(.isButton)
    }

    /// The next train first in line of sight; the later ones go first when room runs short, never it.
    private var times: some View {
        ViewThatFits(in: .horizontal) {
            ForEach((0...range.extraTimes).reversed(), id: \.self) { extra in row(extra: extra) }
        }
    }

    private func row(extra: Int) -> some View {
        let (trains, next) = reading.timeline
        let anchor = next ?? 0
        // With room to spare, the cancelled train just before the next one stays visible, struck through.
        let start = extra > 0 && anchor > 0 ? anchor - 1 : anchor
        let shown = Array(trains[start..<min(trains.count, anchor + extra + 1)])
        return HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, train in
                if index > 0 { Text("·").font(.mono(13)).foregroundStyle(Color.inkSecondary) }
                if train == branch.next { NextChip(train: train, now: now) } else { TimeText(train: train) }
            }
        }
        .fixedSize()
    }

    /// "Other destinations": the folded termini as rows, each its own way into its journey.
    private var other: some View {
        VStack(alignment: side.textAlignment, spacing: 5) {
            Text(branch.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(reading.inRange.prefix(range == .tonight ? 4 : 3).enumerated()), id: \.offset) { _, train in
                Button { open(train.terminus, train.direction ?? "") } label: {
                    HStack(spacing: 7) {
                        if train == branch.next { NextChip(train: train, now: now) } else { TimeText(train: train) }
                        Text(train.terminus?.name ?? train.direction ?? "—").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.85)).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StarSpeech.otherRow(train, now: now))
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// The next train: an amber chip, its delay beside it, and how long until it leaves.
private struct NextChip: View {
    let train: TrainDeparture
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            Text(HallFormat.hm(train.scheduledDeparture)).font(.mono(15, weight: .bold)).foregroundStyle(Color.onAmber)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 6))
            DelayText(train: train)
            Text(StarSpeech.countdown(train.expectedDeparture, from: now)).font(.mono(12.5, weight: .semibold))
                .foregroundStyle(Color.soon)
        }
        .fixedSize()
    }
}

private struct TimeText: View {
    let train: TrainDeparture

    var body: some View {
        HStack(spacing: 2) {
            Text(HallFormat.hm(train.scheduledDeparture)).font(.mono(14, weight: .medium))
                .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.ink.opacity(0.85))
                .strikethrough(train.isCancelled)
            DelayText(train: train)
        }
        .fixedSize()
    }
}

/// "+12" in the caution or stop colour; "+?" when SNCF announced a delay without a figure.
private struct DelayText: View {
    let train: TrainDeparture

    var body: some View {
        switch train.status {
        case .delayed, .severelyDelayed:
            Text("+\(train.delayMinutes ?? 0)").font(.mono(13, weight: .bold)).foregroundStyle(train.status.tableauInk)
        case .unknown:
            Text("+?").font(.mono(13, weight: .bold)).foregroundStyle(Color.caution)
        case .onTime, .cancelled:
            EmptyView()
        }
    }
}

/// The words for the star: the "in 7′" countdowns and the spoken branch summaries.
private enum StarSpeech {
    static func countdown(_ date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "in \(minutes)′" }
        return "in \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// "To Lyon Part-Dieu: next 17:47 in 7 minutes, then 18:47, 19:47".
    static func branch(_ branch: StarBranch, reading: BranchReading, now: Date) -> String {
        guard let next = branch.next else { return "To \(branch.name): every train cancelled" }
        var line = "To \(branch.name): next \(train(next)) in \(minutes(next.expectedDeparture, from: now))"
        let then = reading.timeline.trains.filter { $0.scheduledDeparture > next.scheduledDeparture }.prefix(3).map(train)
        if !then.isEmpty { line += ", then " + then.joined(separator: ", ") }
        return line
    }

    static func otherRow(_ departure: TrainDeparture, now: Date) -> String {
        "To \(departure.terminus?.name ?? departure.direction ?? "an unnamed station"): \(train(departure))"
            + (departure.isCancelled ? "" : " in \(minutes(departure.expectedDeparture, from: now))")
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

/// Grenoble at 17:40 on the mockup Thursday: five termini with real coordinates, so the branches point
/// the way the map does (Lyon up-left, Chambéry and Annecy up-right and spread apart, Valence and Gap
/// below), with a delay, a cancellation and a terminus with nothing in the next two hours.
private struct PreviewStar: StationBoardProviding {
    static let gap = Station(id: "stop_area:SNCF:87763664", name: "Gap", latitude: 44.559600, longitude: 6.079000)
    static let annecy = Station(id: "stop_area:SNCF:87746008", name: "Annecy", latitude: 45.901200, longitude: 6.121900)

    static var trains: [TrainDeparture] {
        let f = BigScreenFixtures.self
        func t(_ h: Int, _ m: Int, _ to: Station, delay: Int? = 0, cancelled: Bool = false) -> TrainDeparture {
            TrainDeparture(scheduledDeparture: f.at(h, m), direction: to.name, mode: "TER", delayMinutes: delay,
                           isCancelled: cancelled, trainNumber: "\(h)\(m)", terminus: to)
        }
        return [
            t(17, 47, f.lyon), t(17, 52, f.chambery, delay: 12), t(18, 5, gap), t(18, 16, f.valence),
            t(18, 22, f.chambery), t(18, 47, f.lyon, cancelled: true), t(18, 52, f.chambery),
            t(19, 16, f.valence), t(19, 47, f.lyon), t(20, 5, gap), t(20, 47, f.lyon),
            t(21, 2, annecy), t(23, 2, annecy),
        ].sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    func board(for station: Station, at now: Date) async -> BoardState { .departures(Self.trains) }
    func serviceDayBoard(for station: Station, at now: Date) async -> BoardState { .departures(Self.trains) }
    func via(forVehicleJourneyID id: String) async -> [String] { [] }
}

#Preview("Station star") {
    let fake = BigScreenData.fake
    let data = BigScreenData(journeyBoards: fake.journeyBoards, stationBoard: PreviewStar(), trainStops: fake.trainStops,
                             serviceDay: fake.serviceDay, roundTrip: fake.roundTrip, leaveBy: fake.leaveBy,
                             watching: fake.watching, eta: fake.eta, stationSearch: fake.stationSearch)
    return StationBoardView(station: BigScreenFixtures.grenoble, now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .environment(\.bigScreenData, data)
        .frame(width: 1100, height: 780)
        .preferredColorScheme(.dark)
}
