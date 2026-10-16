import SNCFCore
import SwiftUI

/// The one place that asks whether the window spans a fold (iPhone Duo's inner display), and where its
/// two columns should meet. Apple's Duo guidance rules out `userInterfaceIdiom` and the interface
/// orientation for layout: the fold is reported as a `.division` reserved region instead, and only where
/// it crosses the view. So the folded outer display, an iPad, a Mac and every other iPhone all read nil,
/// as does anything before iOS 27.1, where the API does not exist.
///
/// Everything here is read from geometry, never from `onHingeChange`'s angle: Apple warns that layout
/// following every degree of the hinge flickers, while the region only changes when the posture does.
enum Fold {
    /// The `.division` region in a view's coordinate space: the system's, or one injected with
    /// `\.previewFold` for previews and headless renders, which have no reserved regions.
    struct Region: Equatable {
        var frame: CGRect
        var margins = EdgeInsets()
        /// False opened flat: the region is zero-width and reserves nothing.
        var isActive = false

        /// Runs top to bottom: the inner display in landscape (book). Across it is portrait (tabletop).
        var isVertical: Bool { frame.height > frame.width }

        /// Where the region before the fold ends and the one after it starts, along the axis it crosses.
        var gap: FoldGap {
            isVertical
                ? .around(lower: frame.minX, upper: frame.maxX, marginBefore: margins.leading,
                          marginAfter: margins.trailing, isActive: isActive)
                : .around(lower: frame.minY, upper: frame.maxY, marginBefore: margins.top,
                          marginAfter: margins.bottom, isActive: isActive)
        }

        /// Partially open with the fold across the screen: the Duo stood like a desk clock.
        var isTabletop: Bool { isActive && !isVertical }
    }

    static func region(in proxy: GeometryProxy, preview: Region? = nil) -> Region? {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            // `.includeInactive`: opened flat, the fold is inactive and zero-width, yet it is still the line
            // two columns should share; without the option the flat inner display would read as no fold.
            if let region = proxy.reservedRegions(kind: .division, options: .includeInactive).first {
                return Region(frame: region.frame, margins: region.margins, isActive: region.isActive)
            }
        }
        #endif
        return preview
    }

    /// The fold's frame in `proxy`'s coordinate space, nil where no fold crosses it.
    static func division(in proxy: GeometryProxy) -> CGRect? {
        region(in: proxy)?.frame
    }

    /// True when the device stands in tabletop posture. For the posture-driven choices (the Wall's desk
    /// clock, picking the Wall by itself): a region, so it holds still while the hinge moves.
    static func isTabletop(in proxy: GeometryProxy) -> Bool {
        region(in: proxy)?.isTabletop ?? false
    }

    /// A `NavigationSplitView` laid over the fold: the columns meet at its centre, so the divider sits in
    /// the crease, and each column's content is pushed off the band by `leadingPadding` / `detailPadding`.
    struct Split: Equatable {
        var leadingWidth: CGFloat
        /// The leading column's trailing padding.
        var leadingPadding: CGFloat = 0
        /// The detail column's leading padding.
        var detailPadding: CGFloat = 0
    }

    static func split(width: CGFloat, region: Region?) -> Split {
        guard let region, region.isVertical else { return Split(leadingWidth: width / 2) }
        let line = region.frame.midX
        // Flat, the columns' own content margins already make the gutter (they meet at the line, as on
        // the foundation); only an active band has extent to clear.
        guard region.isActive else { return Split(leadingWidth: line) }
        let gap = region.gap
        return Split(leadingWidth: line, leadingPadding: max(0, line - gap.end), detailPadding: max(0, gap.start - line))
    }

    /// The foundation's call, kept for splits that only pin the width; `split` adds the band's padding.
    static func leadingWidth(in proxy: GeometryProxy) -> CGFloat {
        split(width: proxy.size.width, region: region(in: proxy)).leadingWidth
    }
}

extension EnvironmentValues {
    /// Set by `BigScreenRoot` from `Fold.division`: true on the Duo's inner display, where a journey opens
    /// into board | train and Journeys gets Lanes as its detail.
    @Entry var spansFold = false
    /// A fake fold for previews and headless renders; the device's own region always wins over it.
    @Entry var previewFold: Fold.Region?
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
