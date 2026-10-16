import SwiftUI

/// One split-flap tile. At rest it draws exactly the static tile; only when `digit` changes while on
/// screen does it split into two halves and flip, the way a station board does. `FlapTime` is four of
/// these around a colon; anything else that counts on flaps (the Wall's leave-by minutes) uses the tile
/// directly, so every flap on screen turns the same way instead of a lookalike that never moves.
public struct FlapTile: View {
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
    // A multi-step change (switching journeys, 4 → 2) runs through every character in between, the way
    // a Solari board spins to its next value; each step is quick so a full turn stays around a second.
    private static let fastFold = 0.045
    private static let fastFall = 0.055

    /// The order a flap's drum holds its characters. A real board only turns forward, so going from 4 to 2
    /// passes 5…9, the blank and 0, 1.
    static let drum = Array("-0123456789")

    /// The characters shown on the way from one value to another, ending on `to`. A character the drum
    /// doesn't hold just swaps in one step.
    static func path(from: Character, to: Character) -> [Character] {
        guard from != to else { return [] }
        guard let start = drum.firstIndex(of: from), let end = drum.firstIndex(of: to) else { return [to] }
        var steps: [Character] = []
        var index = start
        repeat {
            index = (index + 1) % drum.count
            steps.append(drum[index])
        } while index != end
        return steps
    }

    public init(digit: Character, delay: Duration = .zero, digitColor: Color = .amber, tileWidth: CGFloat = 36,
                tileHeight: CGFloat = 52, tileColor: Color = .flapTile, seamColor: Color = .ground,
                cornerRadius: CGFloat = 7) {
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

    public var body: some View {
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
        // A flip cut short by a newer change (or by going off screen) snaps to the character it was
        // revealing, and the drum carries on from there.
        if let pending = incoming { displayed = pending; incoming = nil }
        guard new != displayed else { return }
        guard !reduceMotion else { displayed = new; return }

        let steps = Self.path(from: displayed, to: new)
        let fast = steps.count > 1
        let fold = fast ? Self.fastFold : Self.foldDown
        let fall = fast ? Self.fastFall : Self.fallIn
        try? await Task.sleep(for: delay)
        for step in steps {
            guard !Task.isCancelled else { return }
            topAngle = 0
            bottomAngle = 90
            incoming = step
            withAnimation(.easeIn(duration: fold)) { topAngle = -90 }
            try? await Task.sleep(for: .seconds(fold))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: fall)) { bottomAngle = 0 }
            try? await Task.sleep(for: .seconds(fall))
            guard !Task.isCancelled else { return }
            displayed = step
            incoming = nil
        }
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
