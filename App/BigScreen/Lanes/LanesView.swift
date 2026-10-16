import SNCFCore
import SwiftUI

/// Lanes — every saved journey on one time axis, with the service-day minimap (Lanes.dc.html).
// Phase 1 owner fills this.
struct LanesView: View {
    @Environment(\.bigScreenData) private var data
    @State private var detail = "Loading…"

    var body: some View {
        BigScreenPlaceholder(route: .lanes, detail: detail)
            .task {
                let boards = await data.journeyBoards.boards(at: .now)
                if let first = boards.first, let summary = await data.serviceDay.summary(for: first.leg, at: .now) {
                    detail = "\(summary.trainsPerHour.reduce(0, +)) trains over the service day"
                } else {
                    detail = "\(boards.count) journeys"
                }
            }
    }
}
