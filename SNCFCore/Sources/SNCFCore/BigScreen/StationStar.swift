import Foundation

/// One branch of the big-screen station star: every upcoming train to one terminus, or to several when
/// the smallest ones are folded into "Other destinations".
public struct StarBranch: Equatable, Sendable, Identifiable {
    /// The terminus stop_area id, the headsign when no stop_area came with it, or `StationStar.otherID`.
    public let id: String
    public let name: String
    /// What a journey from the branch is opened to. nil on "Other" and on a headsign-only branch, which
    /// is then resolved by name when someone actually taps it.
    public let terminus: Station?
    /// Upcoming trains in timetable order, cancelled ones kept so they can be struck through.
    public let trains: [TrainDeparture]

    public var isOther: Bool { id == StationStar.otherID }

    /// The first train you can still take: a cancelled one is listed but never "next".
    public var next: TrainDeparture? { trains.first { !$0.isCancelled } }
}

/// The pure half of the station star: which branches there are and which way each one points.
public enum StationStar {
    public static let otherID = "other"

    /// Groups the trains leaving after `now` by terminus. Beyond `maxBranches` the termini with the fewest
    /// trains share one "Other destinations" branch, because labels stop fitting round a circle well
    /// before a big station runs out of termini. Ordered by the soonest train, "Other" last.
    public static func branches(from trains: [TrainDeparture], now: Date, maxBranches: Int = 8) -> [StarBranch] {
        var order: [String] = []
        var groups: [String: [TrainDeparture]] = [:]
        for train in trains.sorted(by: { $0.scheduledDeparture < $1.scheduledDeparture }) where train.expectedDeparture > now {
            let key = train.terminus?.id ?? train.direction ?? "—"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(train)
        }
        func branch(_ key: String) -> StarBranch {
            let first = groups[key]![0]
            return StarBranch(id: key, name: first.terminus?.name ?? first.direction ?? "—",
                              terminus: first.terminus, trains: groups[key]!)
        }
        guard order.count > maxBranches else { return order.map(branch) }

        // The biggest keep their branch; ties go to the sooner one, which `order` already lists first.
        let kept = Set(order.enumerated()
            .sorted { groups[$0.element]!.count != groups[$1.element]!.count
                ? groups[$0.element]!.count > groups[$1.element]!.count : $0.offset < $1.offset }
            .prefix(max(0, maxBranches - 1)).map(\.element))
        let folded = order.filter { !kept.contains($0) }.flatMap { groups[$0]! }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        return order.filter(kept.contains).map(branch)
            + [StarBranch(id: otherID, name: "Other destinations", terminus: nil, trains: folded)]
    }

    /// The initial great-circle bearing, in degrees clockwise from north.
    public static func bearing(from origin: Station, to target: Station) -> Double {
        let φ1 = origin.latitude * .pi / 180, φ2 = target.latitude * .pi / 180
        let Δλ = (target.longitude - origin.longitude) * .pi / 180
        let θ = atan2(sin(Δλ) * cos(φ2), cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ))
        return normalized(θ * 180 / .pi)
    }

    /// Where each branch points, in degrees clockwise from up, one per bearing. A known bearing is used as
    /// is, so the star reads like a map; an unknown one takes the middle of the widest free gap; with no
    /// bearing at all the branches spread evenly from the top. Branches closer than `minimumSeparation`
    /// are then pushed apart in pairs until every gap holds it (or 360/n when there are too many), so two
    /// termini up the same line never print their labels on top of each other.
    public static func angles(for bearings: [Double?], minimumSeparation: Double = 25) -> [Double] {
        let n = bearings.count
        guard n > 1 else { return bearings.map { $0.map(normalized) ?? 0 } }
        guard bearings.contains(where: { $0 != nil }) else {
            return (0..<n).map { Double($0) * 360 / Double(n) }
        }

        var angles = bearings.map { $0.map(normalized) }
        for index in angles.indices where angles[index] == nil {
            let known = angles.compactMap { $0 }.sorted()
            var best = (start: known[known.count - 1], width: known[0] + 360 - known[known.count - 1])
            for (a, b) in zip(known, known.dropFirst()) where b - a > best.width { best = (a, b - a) }
            angles[index] = normalized(best.start + best.width / 2)
        }

        // The ring order is fixed once from the bearings, and every gap is pushed at the same time, so a
        // branch is never shoved past its neighbour: a negative gap is just a bigger push back.
        let ring = angles.indices.sorted { angles[$0]! != angles[$1]! ? angles[$0]! < angles[$1]! : $0 < $1 }
        var positions = ring.map { angles[$0]! }
        // A hair under 360/n, so a full ring settles instead of chasing an exact fit forever.
        let separation = min(minimumSeparation, 360 / Double(n) * 0.98)
        // ponytail: plain relaxation, plenty for the ≤ 8 branches the star draws.
        for _ in 0..<1000 {
            var shift = [Double](repeating: 0, count: n)
            for k in 0..<n {
                let next = (k + 1) % n
                let gap = positions[next] - positions[k] + (next == 0 ? 360 : 0)
                guard gap < separation - 0.01 else { continue }
                let push = (separation - gap) / 2
                shift[k] -= push
                shift[next] += push
            }
            guard shift.contains(where: { $0 != 0 }) else { break }
            for k in 0..<n { positions[k] += shift[k] }
        }
        var result = [Double](repeating: 0, count: n)
        for (k, index) in ring.enumerated() { result[index] = normalized(positions[k]) }
        return result
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
