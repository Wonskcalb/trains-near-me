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

    public init(date: Date, digitColor: Color = .amber, tileWidth: CGFloat = 36, tileHeight: CGFloat = 52) {
        self.date = date
        self.digitColor = digitColor
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
    }

    /// Always two-and-two in 24-hour form whatever the device clock: the flap has four tiles, so a
    /// 12-hour "9:05" with its am/pm would not fit the geometry the tiles are drawn to.
    private var digits: [Character] {
        Array(Self.formatter.string(from: date))
    }

    public var body: some View {
        HStack(spacing: 4) {
            tile(digits[0])
            tile(digits[1])
            Text(":")
                .font(.monoFixed(tileHeight * 0.54, weight: .bold))
                .foregroundStyle(digitColor)
                .frame(width: 10)
            tile(digits[2])
            tile(digits[3])
        }
        .accessibilityElement()
        .accessibilityLabel(date.formatted(date: .omitted, time: .shortened))
    }

    private func tile(_ digit: Character) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color.raised)
            Text(String(digit))
                .font(.monoFixed(tileHeight * 0.65, weight: .bold))
                .foregroundStyle(digitColor)
            // The 1px seam that makes a tile read as two flaps meeting.
            Color.ground.frame(height: 1)
        }
        .frame(width: tileWidth, height: tileHeight)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HHmm"
        return f
    }()
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

    public init(times: [Date], calendar: Calendar = .current) {
        let sorted = times.sorted()
        let first = sorted.first ?? Date()
        let last = sorted.last ?? first
        start = first
        let lastHour = calendar.dateInterval(of: .hour, for: last)?.start ?? last
        let padded = calendar.date(byAdding: .hour, value: 1, to: lastHour) ?? last.addingTimeInterval(3600)
        end = max(padded, first.addingTimeInterval(600))   // never a zero-width window

        var marks: [Date] = []
        if let startHour = calendar.dateInterval(of: .hour, for: first)?.start,
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

/// The large widget's foot: the next departures as dots along a length of rail, each placed at the time
/// it leaves. The soonest on-time train is an amber dot; a delay slides the dot to the amended time and
/// leaves a hollow mark, joined by a dashed arc, at the scheduled one; a cancelled train is crossed out;
/// a disruption of unknown length is a caution dot. The dots are the same trains the rows above list, so
/// the track is decorative to VoiceOver. Sleepers fall every 10 minutes, taller and labelled on the hour.
public struct TimeTrack: View {
    var trains: [TrainDeparture]

    public init(trains: [TrainDeparture]) {
        self.trains = trains
    }

    private static let hourLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    public var body: some View {
        let layout = TimeTrackLayout(times: trains.map(\.expectedDeparture))
        let nextIndex = trains.firstIndex { !$0.isCancelled }
        let calendar = Calendar.current
        Canvas { context, size in
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
