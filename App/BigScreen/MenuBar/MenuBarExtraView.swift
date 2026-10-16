import SNCFCore
import SwiftUI

/// The macOS menu-bar popover: journey switcher, next train, compact track, journey chips (MenuBar.dc.html).
// Phase 1 owner fills this.
struct MenuBarExtraView: View {
    @Environment(\.bigScreenData) private var data
    @State private var detail = "Loading…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trains near me").font(.headline).foregroundStyle(Color.ink)
            Text(detail).font(.mono(12)).foregroundStyle(Color.inkSecondary)
            Text("Phase 1 owner fills this").font(.caption).foregroundStyle(Color.inkSecondary.opacity(0.7))
        }
        .padding(16)
        .frame(width: 372, alignment: .leading)
        .background(Color.ground)
        .task {
            let boards = await data.journeyBoards.boards(at: .now)
            if let first = boards.first, case .departures(let trains) = first.state, let next = trains.first {
                detail = "\(first.leg.to.name) · next \(next.scheduledDeparture.formatted(date: .omitted, time: .shortened))"
            } else {
                detail = "\(boards.count) journeys"
            }
        }
    }
}
