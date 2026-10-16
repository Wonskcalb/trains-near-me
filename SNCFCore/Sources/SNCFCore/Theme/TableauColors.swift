import SwiftUI

public extension SharedSettings.Appearance {
    /// What to hand `.preferredColorScheme`: nil for system, which lets the device decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The Tableau palette, resolved from the asset catalog shipped inside this package so the app and
/// the widget read one source. Every token has an Any (Timetable, light) and a Dark (Board) variant,
/// so the whole UI follows one colour scheme at a time — the two palettes are never mixed on screen.
public extension Color {
    private static func tableau(_ name: String) -> Color { Color(name, bundle: .module) }

    /// Page background.
    static var ground: Color { tableau("Ground") }
    /// Card / panel background on the ground.
    static var surface: Color { tableau("Surface") }
    /// A flap tile, a chip fill, a horizontal tile — the raised level above a surface.
    static var raised: Color { tableau("Raised") }
    /// Primary text.
    static var ink: Color { tableau("Ink") }
    /// Secondary text (labels, captions).
    static var inkSecondary: Color { tableau("InkSecondary") }
    /// The one accent. Amber is a fill on light and a text colour on dark, never text on light.
    static var amber: Color { tableau("Amber") }
    /// "Leaving soon" / clear to go. Named `soon` rather than `clear` so it never shadows the
    /// system's transparent `Color.clear`, which the widgets rely on for an untinted row.
    static var soon: Color { tableau("Clear") }
    /// Delay 11–19 min, or an announced delay of unknown length. Text colour.
    static var caution: Color { tableau("Caution") }
    /// The fill behind `caution` text.
    static var cautionBg: Color { tableau("CautionBg") }
    /// Delay ≥20 min, or cancelled. Text colour.
    static var stop: Color { tableau("Stop") }
    /// The fill behind `stop` text.
    static var stopBg: Color { tableau("StopBg") }
    /// The two rails of a track rule.
    static var rail: Color { tableau("Rail") }
    /// The sleepers of a track rule.
    static var sleeper: Color { tableau("Sleeper") }
    /// Text on an amber fill (a NEXT tag, a FIRST THAT FITS pill, the leave-by card). Fixed near-black in
    /// both schemes: amber stays amber, so no adaptive token spans it — `ground` turns to paper on light.
    static let onAmber = Color(red: 0.055, green: 0.059, blue: 0.067)
}

/// How a departure's status paints in Tableau: a text colour and the fill it sits on. Kept next to
/// the palette so the app board, the journey tiles and the widget rows all read a delay the same way.
public extension DepartureStatus {
    /// The colour for the time, the delay badge, or a pill's text.
    var tableauInk: Color {
        switch self {
        case .onTime: .inkSecondary
        case .delayed, .unknown: .caution
        case .severelyDelayed, .cancelled: .stop
        }
    }

    /// The fill behind the row/tile — transparent when nothing is wrong, so an on-time train has no tint.
    var tableauFill: Color {
        switch self {
        case .onTime: .clear
        case .delayed, .unknown: .cautionBg
        case .severelyDelayed, .cancelled: .stopBg
        }
    }
}
