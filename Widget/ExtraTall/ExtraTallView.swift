import SNCFCore
import SwiftUI

/// Extra-tall widget — large width, twice the height, with the time track turned vertical (DuoWidget.dc.html).
/// Not yet registered in the bundle: `.systemExtraLargePortrait` is the fitting family but is OS-27-only
/// (see the report). Phase 1 owner fills this and wires its data through the timeline entry.
// Phase 1 owner fills this.
struct ExtraTallView: View {
    // Reads the big-screen data from the environment (defaults to `.fake`), same key the app injects.
    @Environment(\.bigScreenData) private var data

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "ruler")
                .font(.system(size: 28))
                .foregroundStyle(Color.inkSecondary)
            Text("Extra tall").font(.headline).foregroundStyle(Color.ink)
            Text("Phase 1 owner fills this").font(.caption2).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ground)
    }
}
