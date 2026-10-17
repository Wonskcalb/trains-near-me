import SwiftUI

// The reusable Tableau pieces, shared by the app screens and the widgets. They carry no data logic:
// each takes already-decided values (a time, two colours, a status) and draws the house style.

/// A split-flap time: four tiles with a colon, the digit in amber, a ground-coloured seam across the
/// middle of each tile. Used for the single next train on Near me, where one time is worth the room.
public struct FlapTime: View {
    let date: Date
    var digitColor: Color
    var tileWidth: CGFloat
    var tileHeight: CGFloat
    var tileColor: Color
    var seamColor: Color
    var cornerRadius: CGFloat
    /// nil draws the colon in `digitColor`. The colon sits on the panel, not on a tile, so where the
    /// digits are amber on an ink tile over paper it must be ink instead: amber text on paper is out.
    var colonColor: Color?

    // The tile sizes the mockups use are all passed in: 46×66 hero, 52×74 wall clock, 25×38 wall rows,
    // 62×88 leave-by, 30×44 menu bar, 34×50 extra-tall. The digit and colon scale from `tileHeight`, so
    // one geometry serves them all. `tileColor` defaults to `flapTile`, so the amber digit always sits on
    // a dark tile: raised on dark, ink on light (the extra-tall widget's light treatment). The `ground`
    // seam reads either way: a black line on a raised tile, a paper line on an ink one.
    public init(date: Date, digitColor: Color = .amber, tileWidth: CGFloat = 36, tileHeight: CGFloat = 52,
                tileColor: Color = .flapTile, seamColor: Color = .ground, cornerRadius: CGFloat = 7,
                colonColor: Color? = nil) {
        self.date = date
        self.digitColor = digitColor
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tileColor = tileColor
        self.seamColor = seamColor
        self.cornerRadius = cornerRadius
        self.colonColor = colonColor
    }

    /// Always two-and-two in 24-hour form whatever the device clock: the flap has four tiles, so a
    /// 12-hour "9:05" with its am/pm would not fit the geometry the tiles are drawn to.
    private var digits: [Character] {
        Array(Self.formatter.string(from: date))
    }

    public var body: some View {
        HStack(spacing: 4) {
            tile(digits, 0)
            tile(digits, 1)
            Text(":")
                .font(.monoFixed(tileHeight * 0.54, weight: .bold))
                .foregroundStyle(colonColor ?? digitColor)
                .frame(width: 10)
            tile(digits, 2)
            tile(digits, 3)
        }
        .accessibilityElement()
        .accessibilityLabel(date.formatted(SNCFTime.shortTime))
    }

    // ponytail: the stagger is per column (50 ms each), not per changed tile, so a lone minute flip
    // starts 150 ms late; ranking only the changed tiles would need the previous time held here too.
    private func tile(_ digits: [Character], _ column: Int) -> some View {
        FlapTile(digit: digits[column], delay: .milliseconds(50 * column), digitColor: digitColor,
                 tileWidth: tileWidth, tileHeight: tileHeight, tileColor: tileColor, seamColor: seamColor,
                 cornerRadius: cornerRadius)
    }

    /// Paris, like every train time beside it.
    private static let formatter = SNCFTime.formatter("HHmm")
}

/// The route glyph: a hollow origin dot, a line, a solid destination dot. The destination carries the
/// accent — either amber filled (a board) or an ink core inside an amber ring (a card).
public struct RoutePins: View {
    public enum Destination {
        /// A filled dot, the whole thing one colour. The widget and the board headers.
        case solid(Color)
        /// An ink core inside a coloured ring. The journey cards.
        case ring(core: Color, ring: Color)
    }

    var lineColor: Color
    var destination: Destination
    var originDiameter: CGFloat
    var destinationDiameter: CGFloat
    var lineWidth: CGFloat
    /// nil lets the line stretch to the glyph's height; a value pins it, for a fixed widget layout.
    var lineLength: CGFloat?

    public init(lineColor: Color = .inkSecondary,
                destination: Destination = .solid(.amber),
                originDiameter: CGFloat = 9,
                destinationDiameter: CGFloat = 12,
                lineWidth: CGFloat = 2,
                lineLength: CGFloat? = nil) {
        self.lineColor = lineColor
        self.destination = destination
        self.originDiameter = originDiameter
        self.destinationDiameter = destinationDiameter
        self.lineWidth = lineWidth
        self.lineLength = lineLength
    }

    public var body: some View {
        VStack(spacing: 2) {
            Circle()
                .strokeBorder(lineColor, lineWidth: originDiameter > 10 ? 2.5 : 2)
                .frame(width: originDiameter, height: originDiameter)
            Rectangle()
                .fill(lineColor)
                .frame(width: lineWidth)
                .frame(maxHeight: lineLength == nil ? .infinity : nil)
                .frame(height: lineLength)
            destinationDot
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var destinationDot: some View {
        switch destination {
        case .solid(let color):
            Circle().fill(color).frame(width: destinationDiameter, height: destinationDiameter)
        case .ring(let core, let ring):
            Circle().fill(core)
                .frame(width: destinationDiameter, height: destinationDiameter)
                .overlay(Circle().stroke(ring, lineWidth: 3).padding(-3))
        }
    }
}

/// A section divider drawn as a length of track: sleepers crossing, two rails inset from the edges.
/// An optional mono caps label sits to its left ("THEN").
public struct TrackRule: View {
    var label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let label {
                Text(label)
                    .font(.mono(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.inkSecondary)
            }
            Canvas { context, size in
                // Sleepers: 4px wide every 13px, wider-spaced than the rails are apart.
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 4, height: size.height)), with: .color(.sleeper))
                    x += 13
                }
                // Two rails, 2px, inset 3px from the top and the bottom.
                context.fill(Path(CGRect(x: 0, y: 3, width: size.width, height: 2)), with: .color(.rail))
                context.fill(Path(CGRect(x: 0, y: size.height - 5, width: size.width, height: 2)), with: .color(.rail))
            }
            .frame(height: 14)
        }
    }
}

/// Where the dots of a `TimeTrack` sit: a time window and the whole-hour marks inside it. Pure so the
/// mapping can be tested without rendering. The window runs from the first train to the hour after the
/// last, so the final dot has room and the closing hour gets a label.
public struct TimeTrackLayout {
    public let start: Date
    public let end: Date
    /// Whole hours strictly after `start`, up to and including `end` — the labelled, taller sleepers.
    public let hours: [Date]

    /// The footer window: from the first train to the hour after the last, so the final dot has room and
    /// the closing hour gets a label. Paris hours, like the labels drawn on them.
    public init(times: [Date], calendar: Calendar = SNCFTime.calendar) {
        let sorted = times.sorted()
        let first = sorted.first ?? Date()
        let last = sorted.last ?? first
        let lastHour = calendar.dateInterval(of: .hour, for: last)?.start ?? last
        let padded = calendar.date(byAdding: .hour, value: 1, to: lastHour) ?? last.addingTimeInterval(3600)
        self.init(start: first, end: max(padded, first.addingTimeInterval(600)), calendar: calendar)
    }

    /// A now-anchored window: `start` now, `end` `minutesSpan` later. Used by the big-screen rails, which
    /// always read from "now" (17:40 → 21:00 in the mockups) rather than from the first listed train.
    public init(start: Date, minutesSpan: Int, calendar: Calendar = SNCFTime.calendar) {
        let end = calendar.date(byAdding: .minute, value: minutesSpan, to: start) ?? start.addingTimeInterval(Double(minutesSpan) * 60)
        self.init(start: start, end: max(end, start.addingTimeInterval(600)), calendar: calendar)
    }

    public init(start: Date, end: Date, calendar: Calendar = SNCFTime.calendar) {
        self.start = start
        self.end = end

        var marks: [Date] = []
        if let startHour = calendar.dateInterval(of: .hour, for: start)?.start,
           var mark = calendar.date(byAdding: .hour, value: 1, to: startHour) {
            while mark <= end, marks.count <= 48 {
                marks.append(mark)
                guard let next = calendar.date(byAdding: .hour, value: 1, to: mark) else { break }
                mark = next
            }
        }
        hours = marks
    }

    /// 0 at the window's start, 1 at its end, clamped.
    public func fraction(of date: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }
}

/// Sizes for the now-anchored rail (`TimeTrack(trains:now:…)`): sleepers, rail gap, marker radii and the
/// room the hour labels need. The footer `TimeTrack(trains:)` ignores these — it keeps its own fixed
/// 44 pt geometry so the large widget renders exactly as before.
public struct TimeTrackMetrics: Sendable {
    public var sleeperMinutes: Int
    public var sleeperThickness: CGFloat
    public var sleeperLength: CGFloat
    public var hourSleeperLength: CGFloat
    public var railThickness: CGFloat
    public var railGap: CGFloat
    public var markerRadius: CGFloat
    public var nextMarkerRadius: CGFloat
    public var ghostRadius: CGFloat
    public var cancelledRadius: CGFloat
    public var labelSize: CGFloat
    /// The across-axis size of the whole view (rail band plus the label gutter).
    public var acrossExtent: CGFloat
    /// The across-axis coordinate of the track centreline (the rails straddle it; the markers sit on it).
    public var bandCentre: CGFloat
    /// The across-axis coordinate of the hour-label baseline (below the track, or in the left gutter).
    public var labelAcross: CGFloat
    /// How far the window ends sit from the along-axis edges, so the first and last marks have room.
    public var startInset: CGFloat
    public var endInset: CGFloat

    public init(sleeperMinutes: Int = 10, sleeperThickness: CGFloat, sleeperLength: CGFloat,
                hourSleeperLength: CGFloat, railThickness: CGFloat, railGap: CGFloat, markerRadius: CGFloat,
                nextMarkerRadius: CGFloat, ghostRadius: CGFloat, cancelledRadius: CGFloat, labelSize: CGFloat,
                acrossExtent: CGFloat, bandCentre: CGFloat, labelAcross: CGFloat, startInset: CGFloat, endInset: CGFloat) {
        self.sleeperMinutes = sleeperMinutes
        self.sleeperThickness = sleeperThickness
        self.sleeperLength = sleeperLength
        self.hourSleeperLength = hourSleeperLength
        self.railThickness = railThickness
        self.railGap = railGap
        self.markerRadius = markerRadius
        self.nextMarkerRadius = nextMarkerRadius
        self.ghostRadius = ghostRadius
        self.cancelledRadius = cancelledRadius
        self.labelSize = labelSize
        self.acrossExtent = acrossExtent
        self.bandCentre = bandCentre
        self.labelAcross = labelAcross
        self.startInset = startInset
        self.endInset = endInset
    }

    /// Main's full-width board rail: 672 pt over 200 min, sleepers 4×20 (28 on the hour), rails 10 apart,
    /// markers r7–8, hour labels below the track.
    public static let board = TimeTrackMetrics(
        sleeperThickness: 4, sleeperLength: 20, hourSleeperLength: 28, railThickness: 2, railGap: 10,
        markerRadius: 7, nextMarkerRadius: 8, ghostRadius: 4.6, cancelledRadius: 6.4, labelSize: 11,
        acrossExtent: 62, bandCentre: 22, labelAcross: 50, startInset: 8, endInset: 8)

    /// The extra-tall widget's vertical rail: 2.6 pt/min, horizontal sleepers, vertical rails, markers r5,
    /// hour labels in the left gutter.
    public static let vertical = TimeTrackMetrics(
        sleeperThickness: 3, sleeperLength: 20, hourSleeperLength: 26, railThickness: 1.8, railGap: 9,
        markerRadius: 5, nextMarkerRadius: 5.5, ghostRadius: 3.2, cancelledRadius: 4.6, labelSize: 10,
        acrossExtent: 70, bandCentre: 48, labelAcross: 2, startInset: 13, endInset: 10)

    /// The large widget's footer geometry on a now-anchored rail, for the menu bar popover: 44 pt tall,
    /// sleepers 3×14 (3×18 on the hour), 1.6 pt rails 7.4 apart, markers r5–5.5, 9 pt labels.
    public static let compact = TimeTrackMetrics(
        sleeperThickness: 3, sleeperLength: 14, hourSleeperLength: 18, railThickness: 1.6, railGap: 7.4,
        markerRadius: 5, nextMarkerRadius: 5.5, ghostRadius: 3.2, cancelledRadius: 4.6, labelSize: 9,
        acrossExtent: 44, bandCentre: 17.5, labelAcross: 37, startInset: 6, endInset: 6)
}

/// A time axis with the next departures placed along it. Two shapes share the drawing:
/// - `TimeTrack(trains:)` is the large widget's foot — a fixed 44 pt horizontal rail whose window runs
///   from the first train to the hour after the last, no "now" mark. Its geometry is frozen so the widget
///   renders identically to before.
/// - `TimeTrack(trains:now:axis:…)` is the big-screen rail — a now-anchored window (17:40 → 21:00 in the
///   mockups) drawn horizontally (Main's board) or vertically (the extra-tall widget).
/// Either way the soonest on-time train is amber, a delay slides the dot to the amended time and leaves a
/// dashed-arc ghost at the scheduled one, and a cancelled train is crossed out. The footer is decorative
/// to VoiceOver (the rows above already name each train); the big-screen rail reads as one sentence.
public struct TimeTrack: View {
    public enum Axis: Sendable { case horizontal, vertical }

    var trains: [TrainDeparture]
    /// nil → the footer window and fixed geometry; non-nil → a now-anchored window along `axis`.
    var anchor: Date?
    var axis: Axis
    var minutesSpan: Int
    var length: CGFloat?
    var metrics: TimeTrackMetrics

    public init(trains: [TrainDeparture]) {
        self.trains = trains
        self.anchor = nil
        self.axis = .horizontal
        self.minutesSpan = 200
        self.length = nil
        self.metrics = .board
    }

    public init(trains: [TrainDeparture], now: Date, axis: Axis = .horizontal,
                minutesSpan: Int = 200, length: CGFloat? = nil, metrics: TimeTrackMetrics = .board) {
        self.trains = trains
        self.anchor = now
        self.axis = axis
        self.minutesSpan = minutesSpan
        self.length = length
        self.metrics = metrics
    }

    // Paris hours and labels, so a rail's 18h stands where the 18:00 train does whatever the device zone.
    private static let hourLabel = SNCFTime.hhmmFormatter

    /// Big-screen rails label the hour as "18h", not "18:00".
    private static let hourShort = SNCFTime.formatter("H'h'")

    @ViewBuilder public var body: some View {
        // nil anchor is the legacy widget footer (frozen geometry); a now-anchored call draws the
        // big-screen rail along its axis. Without this dispatch every big-screen track fell back to
        // the horizontal footer.
        if let anchor { anchoredRail(now: anchor) } else { footer }
    }

    // The large widget's foot. Geometry unchanged — do not touch without re-checking the screenshots.
    private var footer: some View {
        let layout = TimeTrackLayout(times: trains.map(\.expectedDeparture))
        let nextIndex = trains.firstIndex { !$0.isCancelled }
        let calendar = SNCFTime.calendar
        return Canvas { context, size in
            let inset: CGFloat = 6                    // keep the edge dots off the panel border
            func x(_ date: Date) -> CGFloat { inset + CGFloat(layout.fraction(of: date)) * (size.width - 2 * inset) }
            func fill(_ c: CGPoint, _ r: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }
            func ring(_ c: CGPoint, _ r: CGFloat, _ color: Color, _ width: CGFloat = 1.6) {
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: width)
            }

            // Sleepers every 10 minutes; the ones on the hour are taller, darker and carry a label.
            if let hour0 = calendar.dateInterval(of: .hour, for: layout.start)?.start {
                var tick = hour0
                while tick <= layout.end {
                    if tick >= layout.start {
                        let onHour = calendar.component(.minute, from: tick) == 0
                        context.fill(Path(roundedRect: CGRect(x: x(tick) - 1.5, y: onHour ? 8 : 10, width: 3, height: onHour ? 18 : 14), cornerRadius: 1),
                                     with: .color(onHour ? .rail : .sleeper))
                    }
                    guard let next = calendar.date(byAdding: .minute, value: 10, to: tick) else { break }
                    tick = next
                }
            }
            // Two rails over the sleepers.
            context.fill(Path(CGRect(x: 0, y: 13, width: size.width, height: 1.6)), with: .color(.rail))
            context.fill(Path(CGRect(x: 0, y: 20.4, width: size.width, height: 1.6)), with: .color(.rail))

            for (i, train) in trains.enumerated() {
                let cx = x(train.expectedDeparture)
                let centre = CGPoint(x: cx, y: 17.5)
                switch train.status {
                case .cancelled:
                    fill(centre, 4.6, .surface)
                    ring(centre, 4.6, .stop)
                    var cross = Path()
                    cross.move(to: CGPoint(x: cx - 2.4, y: 15.1)); cross.addLine(to: CGPoint(x: cx + 2.4, y: 19.9))
                    cross.move(to: CGPoint(x: cx + 2.4, y: 15.1)); cross.addLine(to: CGPoint(x: cx - 2.4, y: 19.9))
                    context.stroke(cross, with: .color(.stop), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                case .delayed, .severelyDelayed:
                    let color = train.status.tableauInk
                    let sx = x(train.scheduledDeparture)
                    var arc = Path()
                    arc.move(to: CGPoint(x: sx, y: 12))
                    arc.addQuadCurve(to: CGPoint(x: cx, y: 12), control: CGPoint(x: (sx + cx) / 2, y: 2))
                    context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 1.3, dash: [2, 2]))
                    fill(CGPoint(x: sx, y: 17.5), 3.2, .surface)
                    ring(CGPoint(x: sx, y: 17.5), 3.2, color, 1.3)
                    fill(centre, 5, color)
                case .unknown:
                    fill(centre, 5, .caution)
                case .onTime:
                    if i == nextIndex {
                        fill(centre, 5.5, .amber)
                        ring(centre, 5.5, .ink, 2)
                    } else {
                        fill(centre, 5, .ink)
                    }
                }
            }

            for hour in layout.hours {
                context.draw(Text(Self.hourLabel.string(from: hour)).font(.mono(9, weight: .medium)).foregroundStyle(Color.inkSecondary),
                             at: CGPoint(x: x(hour), y: 37), anchor: .center)
            }
        }
        .frame(height: 44)
        // The rows above already name each train for VoiceOver; the track just repeats them visually.
        .accessibilityHidden(true)
    }

    // The big-screen rail: a now-anchored window drawn along either axis. Positions come from `size`, so
    // the caller only fixes the across extent and (optionally) the along length.
    private func anchoredRail(now: Date) -> some View {
        let layout = TimeTrackLayout(start: now, minutesSpan: minutesSpan)
        let nextIndex = trains.firstIndex { !$0.isCancelled }
        let m = metrics
        let horizontal = axis == .horizontal
        let calendar = SNCFTime.calendar
        return Canvas { context, size in
            let alongLength = horizontal ? size.width : size.height
            func along(_ date: Date) -> CGFloat {
                m.startInset + CGFloat(layout.fraction(of: date)) * (alongLength - m.startInset - m.endInset)
            }
            func point(_ date: Date, _ off: CGFloat = 0) -> CGPoint {
                horizontal ? CGPoint(x: along(date), y: m.bandCentre + off)
                           : CGPoint(x: m.bandCentre + off, y: along(date))
            }
            func fill(_ c: CGPoint, _ r: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }
            func ring(_ c: CGPoint, _ r: CGFloat, _ color: Color, _ width: CGFloat) {
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: width)
            }

            // Sleepers every `sleeperMinutes`, clock-aligned; the ones on the hour are taller and labelled.
            if let hour0 = calendar.dateInterval(of: .hour, for: now)?.start {
                var tick = hour0
                while tick <= layout.end {
                    if tick >= now {
                        let onHour = calendar.component(.minute, from: tick) == 0
                        let length = onHour ? m.hourSleeperLength : m.sleeperLength
                        let a = along(tick)
                        let rect = horizontal
                            ? CGRect(x: a - m.sleeperThickness / 2, y: m.bandCentre - length / 2, width: m.sleeperThickness, height: length)
                            : CGRect(x: m.bandCentre - length / 2, y: a - m.sleeperThickness / 2, width: length, height: m.sleeperThickness)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(onHour ? .rail : .sleeper))
                    }
                    guard let next = calendar.date(byAdding: .minute, value: m.sleeperMinutes, to: tick) else { break }
                    tick = next
                }
            }

            // Two rails along the full length, `railGap` apart, centred on the band.
            for off in [-m.railGap / 2, m.railGap / 2] {
                let rect = horizontal
                    ? CGRect(x: 0, y: m.bandCentre + off - m.railThickness / 2, width: size.width, height: m.railThickness)
                    : CGRect(x: m.bandCentre + off - m.railThickness / 2, y: 0, width: m.railThickness, height: size.height)
                context.fill(Path(rect), with: .color(.rail))
            }

            for (i, train) in trains.enumerated() where train.expectedDeparture <= layout.end {
                let centre = point(train.expectedDeparture)
                switch train.status {
                case .cancelled:
                    let c = point(train.scheduledDeparture)
                    fill(c, m.cancelledRadius, .surface)
                    ring(c, m.cancelledRadius, .stop, m.railThickness)
                    let d = m.cancelledRadius * 0.52
                    var cross = Path()
                    cross.move(to: CGPoint(x: c.x - d, y: c.y - d)); cross.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
                    cross.move(to: CGPoint(x: c.x + d, y: c.y - d)); cross.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
                    context.stroke(cross, with: .color(.stop), style: StrokeStyle(lineWidth: m.railThickness, lineCap: .round))
                case .delayed, .severelyDelayed:
                    let color = train.status.tableauInk
                    // A dashed arc from the scheduled ghost's centre to the amended marker's, bowed away from
                    // the hour labels (up on a horizontal rail; right on the vertical one, whose labels sit
                    // in the left gutter) — DuoWidget's `M48 91.2 Q64 106.8 48 122.4`.
                    let bow: CGFloat = 16
                    let g = point(train.scheduledDeparture)
                    let ctrl = horizontal
                        ? CGPoint(x: (g.x + centre.x) / 2, y: m.bandCentre - bow)
                        : CGPoint(x: m.bandCentre + bow, y: (g.y + centre.y) / 2)
                    var arc = Path()
                    arc.move(to: g); arc.addQuadCurve(to: centre, control: ctrl)
                    context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
                    fill(g, m.ghostRadius, .surface)
                    ring(g, m.ghostRadius, color, 1.3)
                    fill(centre, m.markerRadius, color)
                case .unknown:
                    fill(centre, m.markerRadius, .caution)
                case .onTime:
                    if i == nextIndex {
                        fill(centre, m.nextMarkerRadius, .amber)
                        ring(centre, m.nextMarkerRadius, .ink, 2)
                    } else {
                        fill(centre, m.markerRadius, .ink)
                    }
                }
            }

            // No separate "now" flag: the window starts at now, and the next-train marker is the one amber
            // mark every mockup draws — a flag on top of it read as a doubled dot.
            for hour in layout.hours {
                let label = context.resolve(Text(Self.hourShort.string(from: hour))
                    .font(.mono(m.labelSize, weight: .medium)).foregroundStyle(Color.inkSecondary))
                let a = along(hour)
                if horizontal {
                    // Centred on its sleeper, but pulled in so the last hour's label is never clipped.
                    let half = label.measure(in: size).width / 2
                    context.draw(label, at: CGPoint(x: min(a, size.width - half), y: m.labelAcross), anchor: .center)
                } else {
                    context.draw(label, at: CGPoint(x: m.labelAcross, y: a), anchor: .leading)
                }
            }
        }
        .frame(width: horizontal ? length : m.acrossExtent, height: horizontal ? m.acrossExtent : length)
        // The rail is the one view of the next trains on the big screens, so VoiceOver gets it as a single
        // sentence rather than nothing.
        .accessibilityElement()
        .accessibilityLabel(spokenSummary(until: layout.end))
    }

    /// "Next trains: 17:42, 18:12 plus 12, 18:42 cancelled".
    private func spokenSummary(until end: Date) -> String {
        let parts = trains.filter { $0.expectedDeparture <= end }.map { train -> String in
            let time = Self.hourLabel.string(from: train.scheduledDeparture)
            switch train.status {
            case .cancelled: return "\(time) cancelled"
            case .delayed, .severelyDelayed: return "\(time) plus \(train.delayMinutes ?? 0)"
            case .unknown: return "\(time) delayed"
            case .onTime: return time
            }
        }
        return parts.isEmpty ? "No trains in the next hours" : "Next trains: " + parts.joined(separator: ", ")
    }
}

/// The status badge on a row: text in the status colour, on the status fill. The caller passes the
/// words ("+12", "CANCELLED", "delay ?") because those are already decided where the row is built.
public struct StatusPill: View {
    let text: String
    let status: DepartureStatus

    public init(_ text: String, status: DepartureStatus) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        Text(text)
            .font(.mono(status == .cancelled ? 11.5 : 13, weight: .bold))
            .tracking(status == .cancelled ? 0.8 : 0)
            .foregroundStyle(status.tableauInk)
            .padding(.horizontal, 9)
            .padding(.vertical, status == .cancelled ? 6 : 5)
            .background(status.tableauFill, in: RoundedRectangle(cornerRadius: 9))
            .fixedSize()
    }
}

/// The outlined service chip ("TER", "TGV"): a 1px ink outline, mono small caps.
public struct ModeChip: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.mono(10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.ink.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.ink.opacity(0.2), lineWidth: 1))
            .fixedSize()
    }
}

/// Diagonal hazard stripes on the ground. `band` is the full-strength app band; `widget` dims to a
/// radial fade so the titles painted on top of it stay readable in a small panel.
public struct HazardBackground: View {
    public enum Variant { case band, widget }

    var variant: Variant
    var stripe: Color
    var bandWidth: CGFloat

    public init(variant: Variant = .band, stripe: Color = .amber, bandWidth: CGFloat = 22) {
        self.variant = variant
        self.stripe = stripe
        self.bandWidth = bandWidth
    }

    public var body: some View {
        ZStack {
            Color.ground
            stripes
                .mask(mask)
        }
    }

    private var stripes: some View {
        Canvas { context, size in
            // -45° bands: start to the left of the canvas by its height so the slanted edges still
            // cover the top-left corner.
            let w = bandWidth
            var x = -size.height
            while x < size.width {
                var band = Path()
                band.move(to: CGPoint(x: x, y: size.height))
                band.addLine(to: CGPoint(x: x + w, y: size.height))
                band.addLine(to: CGPoint(x: x + w + size.height, y: 0))
                band.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.fill(band, with: .color(stripe))
                x += w * 2
            }
        }
    }

    @ViewBuilder private var mask: some View {
        switch variant {
        case .band:
            Color.black
        case .widget:
            // Full in the centre, ~20% of that at the edges, so titles over the middle stay legible.
            RadialGradient(colors: [.black.opacity(0.34), .black.opacity(0.07)],
                           center: .center, startRadius: 0, endRadius: 180)
        }
    }
}
