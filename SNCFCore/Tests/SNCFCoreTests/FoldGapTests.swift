import Testing
@testable import SNCFCore

/// The iPhone Duo's columns either side of the fold, flat (inactive, zero-width) and half open (active).
@Suite struct FoldColumns {
    @Test func aFlatFoldKeepsOurGutter() {
        let gap = FoldGap.around(lower: 475.5, upper: 475.5, marginBefore: 0, marginAfter: 0, isActive: false)
        #expect(gap == FoldGap(end: 463.5, start: 487.5))
    }

    @Test func halfOpenTheColumnsClearTheBandAndItsMargins() {
        let gap = FoldGap.around(lower: 460, upper: 490, marginBefore: 8, marginAfter: 10, isActive: true)
        #expect(gap == FoldGap(end: 452, start: 500))
    }

    @Test func aNarrowActiveBandStillGetsTheGutter() {
        let gap = FoldGap.around(lower: 470, upper: 480, marginBefore: 0, marginAfter: 0, isActive: true)
        #expect(gap == FoldGap(end: 463, start: 487))
    }
}
