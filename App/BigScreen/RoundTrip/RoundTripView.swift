import SNCFCore
import SwiftUI

/// Round trip — outbound and the way back side by side, with the stay stepper (Duo.dc.html).
// Phase 1 owner fills this.
struct RoundTripView: View {
    @Environment(\.bigScreenData) private var data
    @State private var detail = "Loading…"

    var body: some View {
        BigScreenPlaceholder(route: .roundTrip, detail: detail)
            .task {
                let boards = await data.journeyBoards.boards(at: .now)
                guard let leg = boards.first?.leg else {
                    detail = "No journey"
                    return
                }
                let plan = await data.roundTrip.roundTrip(
                    outbound: Leg(from: leg.to, to: leg.from), pick: nil, stay: 150 * 60, at: .now)
                detail = "\(plan.outboundOptions.count) out · \(plan.returnOptions.count) back"
            }
    }
}
