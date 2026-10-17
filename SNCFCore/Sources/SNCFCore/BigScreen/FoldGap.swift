import CoreGraphics

/// Where two regions either side of a fold end and start, along the axis the fold crosses. Pure so the
/// iPhone Duo's column math is tested without a device: the app feeds it a `.division` reserved region.
public struct FoldGap: Equatable, Sendable {
    /// Where the region before the fold (leading, or top) ends.
    public var end: CGFloat
    /// Where the region after the fold (trailing, or bottom) starts.
    public var start: CGFloat

    public init(end: CGFloat, start: CGFloat) {
        self.end = end
        self.start = start
    }

    /// Our own gutter around a flat fold: zero-width and inactive, it still must not have text across it,
    /// so a partial opening never lands the crease on a word.
    public static let minimumGutter: CGFloat = 24

    /// Half open, the fold is an active region with a real extent and margins, and Apple excludes all of
    /// it from layout: the first region stops at `lower - marginBefore`, the second starts at
    /// `upper + marginAfter`. Flat (inactive), only the gutter applies, which also stays the floor when the
    /// active band is narrower than it.
    public static func around(lower: CGFloat, upper: CGFloat, marginBefore: CGFloat, marginAfter: CGFloat,
                              isActive: Bool) -> FoldGap {
        let mid = (lower + upper) / 2
        let half = minimumGutter / 2
        guard isActive else { return FoldGap(end: mid - half, start: mid + half) }
        return FoldGap(end: min(lower - marginBefore, mid - half), start: max(upper + marginAfter, mid + half))
    }
}
