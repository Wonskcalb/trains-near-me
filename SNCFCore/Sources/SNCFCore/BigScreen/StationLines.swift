import Foundation

/// One lane of the big-screen station board: every upcoming train to one terminus, or to several when
/// the smallest ones are folded into "Other destinations".
public struct StationLane: Equatable, Sendable, Identifiable {
    /// The terminus stop_area id, the headsign when no stop_area came with it, or `StationLines.otherID`.
    public let id: String
    public let name: String
    /// What a journey from the lane is opened to. nil on "Other" and on a headsign-only lane, which is
    /// then resolved by name when someone actually taps it.
    public let terminus: Station?
    /// Upcoming trains in timetable order, cancelled ones kept so they can be struck through.
    public let trains: [TrainDeparture]

    public var isOther: Bool { id == StationLines.otherID }

    /// The first train you can still take: a cancelled one is listed but never "next".
    public var next: TrainDeparture? { trains.first { !$0.isCancelled } }
}

/// The pure half of the station line map: which lanes there are, which side of the time axis each one
/// runs on, the shared time scale, and where the time labels go.
public enum StationLines {
    public static let otherID = "other"

    /// Groups the trains leaving after `now` by terminus. Beyond `maxLanes` the termini with the fewest
    /// trains share one "Other destinations" lane, because a lane under ~56 pt no longer holds its labels.
    /// Ordered by the soonest train, "Other" last.
    public static func lanes(from trains: [TrainDeparture], now: Date, maxLanes: Int = 8) -> [StationLane] {
        var order: [String] = []
        var groups: [String: [TrainDeparture]] = [:]
        for train in trains.sorted(by: { $0.scheduledDeparture < $1.scheduledDeparture }) where train.expectedDeparture > now {
            let key = train.terminus?.id ?? train.direction ?? "—"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(train)
        }
        func lane(_ key: String) -> StationLane {
            let first = groups[key]![0]
            return StationLane(id: key, name: first.terminus?.name ?? first.direction ?? "—",
                               terminus: first.terminus, trains: groups[key]!)
        }
        guard order.count > maxLanes else { return order.map(lane) }

        // The biggest keep their lane; ties go to the sooner one, which `order` already lists first.
        let kept = Set(order.enumerated()
            .sorted { groups[$0.element]!.count != groups[$1.element]!.count
                ? groups[$0.element]!.count > groups[$1.element]!.count : $0.offset < $1.offset }
            .prefix(max(0, maxLanes - 1)).map(\.element))
        let folded = order.filter { !kept.contains($0) }.flatMap { groups[$0]! }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        return order.filter(kept.contains).map(lane)
            + [StationLane(id: otherID, name: "Other destinations", terminus: nil, trains: folded)]
    }

    /// The initial great-circle bearing, in degrees clockwise from north.
    public static func bearing(from origin: Station, to target: Station) -> Double {
        let φ1 = origin.latitude * .pi / 180, φ2 = target.latitude * .pi / 180
        let Δλ = (target.longitude - origin.longitude) * .pi / 180
        let θ = atan2(sin(Δλ) * cos(φ2), cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ))
        let degrees = (θ * 180 / .pi).truncatingRemainder(dividingBy: 360)
        return degrees < 0 ? degrees + 360 : degrees
    }

    // MARK: Sides

    /// Splits the lanes into the two sides of the line, as indices into `bearings`, each listed top to
    /// bottom. The bearings are read round the circle and cut at the two widest empty arcs: a station sits
    /// on a line, so its termini bunch into two fans, and a terminus off to one side (Valence, south-west
    /// of Voiron) still rides with the fan it shares track with (Grenoble, via Moirans). The fan that
    /// points further north goes above, so the map keeps its up. Termini without coordinates join the
    /// bigger fan, at its end; with fewer than two known bearings everything goes above.
    public static func sides(for bearings: [Double?]) -> (above: [Int], below: [Int]) {
        let known = bearings.indices.filter { bearings[$0] != nil }
            .sorted { (bearings[$0]!, $0) < (bearings[$1]!, $1) }
        let unknown = bearings.indices.filter { bearings[$0] == nil }
        let n = known.count
        guard n >= 2 else { return (known + unknown, []) }

        let gaps = (0..<n).map { k in
            let gap = bearings[known[(k + 1) % n]]! - bearings[known[k]]!
            return k == n - 1 ? gap + 360 : gap
        }
        // The two widest gaps, the earlier one on a tie, so the cut never depends on the sort's mood.
        let cuts = gaps.indices.sorted { (gaps[$0], -$0) > (gaps[$1], -$1) }.prefix(2).sorted()
        // Every termini on one bearing: no second gap to cut at, one fan.
        guard gaps[cuts[0]] > 0.5, gaps[cuts[1]] > 0.5 else { return (known + unknown, []) }
        // Each fan runs clockwise from just after one cut to the next.
        var first = Array(known[(cuts[0] + 1)...cuts[1]])
        var second = Array(known[(cuts[1] + 1)...] + known[...cuts[0]])

        func north(_ fan: [Int]) -> Double { fan.map { cos(bearings[$0]! * .pi / 180) }.reduce(0, +) / Double(fan.count) }
        if north(second) > north(first) { swap(&first, &second) }
        if second.count > first.count { second += unknown } else { first += unknown }
        return (first, second)
    }

    /// "SOUTH-EAST": the eight-point compass word a side's label is named with.
    public static func compass(_ bearing: Double) -> String {
        let words = ["NORTH", "NORTH-EAST", "EAST", "SOUTH-EAST", "SOUTH", "SOUTH-WEST", "WEST", "NORTH-WEST"]
        return words[Int(((bearing + 22.5) / 45).rounded(.down)) % 8]
    }

    // MARK: Time

    /// Where the axis ends: two and a half hours out for NEXT 2 H, which leaves the last train's label room
    /// before the terminus. TONIGHT runs to the 03:00 service-day close, but stops a quarter past the
    /// last train, so an evening that ends at 22:00 does not squeeze every lane into the left third.
    public static func windowEnd(now: Date, tonight: Bool, lastDeparture: Date?, calendar: Calendar) -> Date {
        let short = now.addingTimeInterval(150 * 60)
        guard tonight else { return short }
        let close = now.addingTimeInterval(BoardState.restOfServiceDay(after: now, atLeast: 150 * 60, calendar: calendar))
        guard let lastDeparture else { return close }
        return min(close, max(short, lastDeparture.addingTimeInterval(15 * 60)))
    }

    /// The map's time axis, `start` (now) to `end`. Late in the evening it holds a break: the dead night
    /// between tonight's last train and tomorrow's first, folded into `breakSpan` of track so the morning
    /// sits beside the evening instead of seven empty hours away, as on Lanes.
    public struct Axis: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let gap: DateInterval?

        /// How much track the break takes, in seconds of axis: enough for its zig-zag and "TOMORROW".
        public static let breakSpan: TimeInterval = 25 * 60

        public init(start: Date, end: Date, gap: DateInterval? = nil) {
            self.start = start
            self.end = end
            self.gap = gap
        }

        /// How far along the axis `date` sits, 0 at `start` and 1 at `end`, the night folded.
        public func fraction(_ date: Date) -> Double {
            let span = folded(end) - folded(start)
            return span > 0 ? (folded(date) - folded(start)) / span : 0
        }

        /// Whether a mark falls inside the folded night, where it would only crowd the zig-zag.
        public func isFolded(_ date: Date) -> Bool { gap.map { date > $0.start && date < $0.end } ?? false }

        private func folded(_ date: Date) -> TimeInterval {
            let t = date.timeIntervalSinceReferenceDate
            guard let gap else { return t }
            let from = gap.start.timeIntervalSinceReferenceDate, to = gap.end.timeIntervalSinceReferenceDate
            if t <= from { return t }
            if t >= to { return t - (to - from) + Self.breakSpan }
            return from + (t - from) / (to - from) * Self.breakSpan
        }
    }

    /// The axis for a board that may carry tomorrow's first trains. Without a morning it is `windowEnd`'s.
    /// With one, the break opens 25 minutes after tonight's last train, which leaves its "23:21 in 51′"
    /// label clear of the zig-zag (at once when none is left, so the river starts at the break), closes a
    /// quarter before the first, and about two hours of the morning follow it. NEXT 2 H keeps its plain
    /// window while tonight still fills it.
    public static func axis(now: Date, tonight: Bool, lastTonight: Date?, firstTomorrow: Date?, calendar: Calendar) -> Axis {
        let plain = Axis(start: now, end: windowEnd(now: now, tonight: tonight, lastDeparture: lastTonight, calendar: calendar))
        guard let first = firstTomorrow else { return plain }
        let from = lastTonight.map { max(now, $0.addingTimeInterval(25 * 60)) } ?? now
        let to = first.addingTimeInterval(-15 * 60)
        // A night under half an hour is not worth a break, and a short look ahead that ends before tonight
        // does has no morning to show.
        guard to.timeIntervalSince(from) > 30 * 60, tonight || from < plain.end else { return plain }
        return Axis(start: now, end: first.addingTimeInterval(2 * 3600), gap: DateInterval(start: from, end: to))
    }

    /// The axis marks between `start` and `end`: whole hours, labelled, and the quarters between them.
    public static func marks(from start: Date, to end: Date, calendar: Calendar) -> (hours: [Date], quarters: [Date]) {
        var hours: [Date] = [], quarters: [Date] = []
        var date = calendar.nextDate(after: start, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? start
        while calendar.component(.minute, from: date) % 15 != 0 { date.addTimeInterval(60) }
        while date < end {
            if calendar.component(.minute, from: date) == 0 { hours.append(date) } else { quarters.append(date) }
            date.addTimeInterval(15 * 60)
        }
        return (hours, quarters)
    }

    /// "EVERY 15 MIN", "HOURLY": the median gap between departures, said only when every gap sits within
    /// a fifth of it (3 min at least), because "every 30 min" over a 30-then-90 evening would lie.
    public static func frequency(of departures: [Date]) -> String? {
        let sorted = departures.sorted()
        let gaps = zip(sorted.dropFirst(), sorted).map { $0.timeIntervalSince($1) / 60 }.sorted()
        guard !gaps.isEmpty else { return nil }
        let mid = gaps.count / 2
        let median = gaps.count % 2 == 0 ? (gaps[mid - 1] + gaps[mid]) / 2 : gaps[mid]
        let tolerance = max(3, median / 5)
        guard median >= 1, gaps.allSatisfy({ abs($0 - median) <= tolerance }) else { return nil }
        let minutes = Int(median.rounded())
        if minutes == 60 { return "HOURLY" }
        if minutes % 60 == 0 { return "EVERY \(minutes / 60) H" }
        return "EVERY \(minutes) MIN"
    }

    // MARK: Lane path

    /// One lane's track: level out of the station capsule, a straight run to `peel`, one horizontal-in,
    /// horizontal-out cubic up or down to the lane's row, then straight on to the terminus. The map strokes
    /// it and a departing train's dot rides back along it, so both read the same numbers.
    public struct LanePath: Equatable, Sendable {
        public let start: CGPoint
        public let peel: CGPoint
        public let control1: CGPoint
        public let control2: CGPoint
        public let curveEnd: CGPoint
        public let end: CGPoint
        /// Arc length along the cubic at each of `samples` even steps of its parameter: a cubic has no
        /// closed-form length, and 48 chords are within a hair of it at this size.
        private let curveLengths: [Double]
        private static let samples = 48

        public init(stationX: Double, exitY: Double, y: Double, curveEnd: Double, laneEnd: Double) {
            // Peels off sooner the further it has to climb, so no two lanes ever cross.
            let peelX = stationX + max(20, 92 - 0.17 * abs(y - exitY))
            let mid = (curveEnd - peelX) / 2
            start = CGPoint(x: stationX, y: exitY)
            peel = CGPoint(x: peelX, y: exitY)
            control1 = CGPoint(x: peelX + mid, y: exitY)
            control2 = CGPoint(x: curveEnd - mid, y: y)
            self.curveEnd = CGPoint(x: curveEnd, y: y)
            end = CGPoint(x: laneEnd, y: y)
            var lengths = [0.0]
            var last = peel
            for i in 1...Self.samples {
                let point = Self.cubic(peel, control1, control2, self.curveEnd, Double(i) / Double(Self.samples))
                lengths.append(lengths[i - 1] + Self.distance(last, point))
                last = point
            }
            curveLengths = lengths
        }

        private var lead: Double { Double(peel.x - start.x) }
        private var curveLength: Double { curveLengths[Self.samples] }
        public var length: Double { lead + curveLength + Double(end.x - curveEnd.x) }

        /// The arc length from the station to `x` on the lane's row, where every stop sits.
        public func distance(toX x: Double) -> Double {
            lead + curveLength + min(max(0, x - Double(curveEnd.x)), Double(end.x - curveEnd.x))
        }

        /// The point `t` of the way along the track by arc length, 0 at the station and 1 at the terminus.
        public func point(at t: Double) -> CGPoint { point(atDistance: t * length) }

        public func point(atDistance s: Double) -> CGPoint {
            let s = min(max(0, s), length)
            if s <= lead { return CGPoint(x: Double(start.x) + s, y: Double(start.y)) }
            let along = s - lead
            guard along < curveLength else { return CGPoint(x: Double(curveEnd.x) + along - curveLength, y: Double(end.y)) }
            // The chord the distance falls in, then the parameter linearly within it.
            let i = curveLengths.firstIndex { $0 >= along } ?? Self.samples
            let below = curveLengths[i - 1], chord = curveLengths[i] - below
            let u = (Double(i - 1) + (chord > 0 ? (along - below) / chord : 0)) / Double(Self.samples)
            return Self.cubic(peel, control1, control2, curveEnd, u)
        }

        private static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u: Double) -> CGPoint {
            let v = 1 - u
            let a = v * v * v, b = 3 * v * v * u, c = 3 * v * u * u, d = u * u * u
            return CGPoint(x: a * Double(p0.x) + b * Double(p1.x) + c * Double(p2.x) + d * Double(p3.x),
                           y: a * Double(p0.y) + b * Double(p1.y) + c * Double(p2.y) + d * Double(p3.y))
        }

        private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
            hypot(Double(b.x - a.x), Double(b.y - a.y))
        }
    }

    // MARK: Labels

    public enum LabelRow: Equatable, Sendable { case below, above, hidden }

    /// A label's width in points, from its character count: JetBrains Mono advances 0.6 em per glyph.
    /// An estimate is enough because the rows keep a 10 pt gap, and it keeps the pass free of text layout.
    public static func monoWidth(_ text: String, size: Double) -> Double { Double(text.count) * 0.6 * size }

    /// Which side of its lane each label goes, given as `minX…maxX` spans in placement order (the next
    /// train first, then the timetable). Greedy: below when the row is free there, otherwise above, and
    /// hidden when both collide, or when `allowAbove` is off on a lane too tight for a second row.
    public static func labelRows(_ spans: [ClosedRange<Double>], allowAbove: Bool = true, gap: Double = 10) -> [LabelRow] {
        var taken: [LabelRow: [ClosedRange<Double>]] = [:]
        return spans.map { span in
            for row in allowAbove ? [LabelRow.below, .above] : [.below]
            where taken[row, default: []].allSatisfy({ span.upperBound + gap < $0.lowerBound || span.lowerBound > $0.upperBound + gap }) {
                taken[row, default: []].append(span)
                return row
            }
            return .hidden
        }
    }
}
