import SwiftUI

/// The one place that asks whether the window spans a fold (iPhone Duo's inner display), and where its
/// two columns should meet. Apple's Duo guidance rules out `userInterfaceIdiom` and the interface
/// orientation for layout: the fold is reported as a `.division` reserved region instead, and only where
/// it crosses the view. So the folded outer display, an iPad, a Mac and every other iPhone all read nil,
/// as does anything before iOS 27.1, where the API does not exist.
enum Fold {
    /// The fold's frame in `proxy`'s coordinate space, nil where no fold crosses it.
    static func division(in proxy: GeometryProxy) -> CGRect? {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            // `.includeInactive`: opened flat, the fold is inactive and zero-width, yet it is still the line
            // two columns should share; without the option the flat inner display would read as no fold.
            return proxy.reservedRegions(kind: .division, options: .includeInactive).first?.frame
        }
        #endif
        return nil
    }

    /// The leading column of a two-column split: up to the fold when it runs top to bottom (landscape), half
    /// the width when it runs across (portrait) or there is none, so the columns are always even.
    static func leadingWidth(in proxy: GeometryProxy) -> CGFloat {
        if let fold = division(in: proxy), fold.height > fold.width { return fold.midX }
        return proxy.size.width / 2
    }
}

extension EnvironmentValues {
    /// Set by `BigScreenRoot` from `Fold.division`: true on the Duo's inner display, where a journey opens
    /// into board | train and Journeys gets Lanes as its detail.
    @Entry var spansFold = false
}

extension View {
    /// The primary toolbar action's Liquid Glass style, which only exists from iOS 26 / macOS 26.
    @ViewBuilder func prominentToolbarButton() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
