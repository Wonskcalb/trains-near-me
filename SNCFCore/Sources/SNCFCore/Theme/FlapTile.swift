import SwiftUI

/// One tile of a `FlapTime`. At rest it draws exactly the static tile; only when `digit` changes while
/// on screen does it split into two halves and flip, the way a station board does.
struct FlapTile: View {
    let digit: Character
    /// The stagger before this tile starts, so 17:59 → 18:00 ripples left to right like a real board.
    let delay: Duration
    let digitColor: Color
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let tileColor: Color
    let seamColor: Color
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Seeded from the first digit, so the first appearance (and every widget render or `ImageRenderer`
    // snapshot, which never run tasks) shows the static tile with nothing in flight.
    @State private var displayed: Character
    /// Non-nil only during a flip: the digit being revealed.
    @State private var incoming: Character?
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 90

    // Old top folds down with an ease-in, new bottom falls into place with an ease-out: 0.40 s a tile.
    private static let foldDown = 0.18
    private static let fallIn = 0.22

    init(digit: Character, delay: Duration, digitColor: Color, tileWidth: CGFloat, tileHeight: CGFloat,
         tileColor: Color, seamColor: Color, cornerRadius: CGFloat) {
        self.digit = digit
        self.delay = delay
        self.digitColor = digitColor
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tileColor = tileColor
        self.seamColor = seamColor
        self.cornerRadius = cornerRadius
        _displayed = State(initialValue: digit)
    }

    var body: some View {
        ZStack {
            if let incoming {
                VStack(spacing: 0) {
                    ZStack {
                        half(incoming, top: true)
                        half(displayed, top: true).flap(angle: topAngle, anchor: .bottom)
                    }
                    ZStack {
                        half(displayed, top: false)
                        half(incoming, top: false).flap(angle: bottomAngle, anchor: .top)
                    }
                }
            } else {
                face(displayed)
            }
            // The 1px seam that makes a tile read as two flaps meeting.
            seamColor.frame(height: 1)
        }
        .frame(width: tileWidth, height: tileHeight)
        // `.task(id:)` rather than `onChange` + a stored `Task`: same trigger, but SwiftUI cancels the
        // previous flip on the next change and on disappear. Between changes nothing is scheduled, so
        // an idle board costs no frames — the lesson of the `TimelineView` that spun the app at 100 %.
        .task(id: digit) { await flip(to: digit) }
    }

    private func flip(to new: Character) async {
        // A flip cut short by a newer change (or by going off screen) snaps to the digit it was revealing.
        if let pending = incoming { displayed = pending; incoming = nil }
        guard new != displayed else { return }
        guard !reduceMotion else { displayed = new; return }

        topAngle = 0
        bottomAngle = 90
        incoming = new
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: Self.foldDown)) { topAngle = -90 }
        try? await Task.sleep(for: .seconds(Self.foldDown))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: Self.fallIn)) { bottomAngle = 0 }
        try? await Task.sleep(for: .seconds(Self.fallIn))
        guard !Task.isCancelled else { return }
        displayed = new
        incoming = nil
    }

    private func face(_ d: Character) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(tileColor)
            Text(String(d))
                .font(.monoFixed(tileHeight * 0.65, weight: .bold))
                .foregroundStyle(digitColor)
        }
        .frame(width: tileWidth, height: tileHeight)
    }

    /// The whole face clipped to one half, so the corners and the glyph cut at exactly the seam.
    private func half(_ d: Character, top: Bool) -> some View {
        face(d)
            .frame(height: tileHeight / 2, alignment: top ? .top : .bottom)
            .clipped()
    }
}

private extension View {
    /// A half turning on the seam. It darkens as it goes edge-on, which is what sells the 3D on a flat
    /// tile; the overlay rides the same animated angle, so it costs no extra state.
    func flap(angle: Double, anchor: UnitPoint) -> some View {
        overlay(Color.black.opacity(abs(angle) / 90 * 0.4))
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: anchor, perspective: 0.5)
    }
}

#Preview("Flip") {
    @Previewable @State var flipped = false
    let before = Calendar.current.date(bySettingHour: 17, minute: 59, second: 0, of: .now) ?? .now
    FlapTime(date: flipped ? before.addingTimeInterval(60) : before)
        .padding(40)
        .background(Color.ground)
        .task {
            // 17:59 ↔ 18:00 every 2 s: every tile changes, so the stagger shows.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                flipped.toggle()
            }
        }
}
