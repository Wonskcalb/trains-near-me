import SwiftUI
import CoreText

/// JetBrains Mono, bundled with this package and registered with Core Text at first use. Registering
/// at runtime (rather than through each target's Info.plist) is the one path that works the same in
/// the app, the widget extension, and on both macOS and iOS, from a single resource in the package.
public enum TableauFont {
    /// The family name Core Text exposes once the faces are registered.
    public static let familyName = "JetBrains Mono"

    private static let faces = [
        "JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-SemiBold",
        "JetBrainsMono-Bold", "JetBrainsMono-ExtraBold",
    ]

    /// Runs once: `let` initialisers are evaluated lazily and exactly once, so repeated calls to
    /// `ensureRegistered()` register nothing twice (a second registration would log a duplicate).
    private static let register: Void = {
        let urls = faces.compactMap { Bundle.module.url(forResource: $0, withExtension: "ttf") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    public static func ensureRegistered() { _ = register }
}

public extension Font {
    /// Mono that scales with Dynamic Type, for times, train numbers, delays and small-caps labels.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        TableauFont.ensureRegistered()
        return .custom(TableauFont.familyName, size: size, relativeTo: textStyle).weight(weight)
    }

    /// Mono at a fixed point size, for the split-flap digits where the tile geometry is drawn to match.
    static func monoFixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        TableauFont.ensureRegistered()
        return .custom(TableauFont.familyName, fixedSize: size).weight(weight)
    }
}
