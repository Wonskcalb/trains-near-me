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
