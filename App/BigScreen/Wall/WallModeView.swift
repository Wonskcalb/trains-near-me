import SNCFCore
import SwiftUI

/// Wall mode — a full-screen departure board for the pinned station, kept awake (Wall.dc.html).
// Phase 1 owner fills this.
struct WallModeView: View {
    @Environment(\.bigScreenData) private var data
    @State private var detail = "Loading…"

    var body: some View {
        BigScreenPlaceholder(route: .wall, detail: detail)
            .task {
                guard let station = await data.leaveBy.pinnedStation() else {
                    detail = "No pinned station"
                    return
                }
                let count: Int
                if case .departures(let trains) = await data.stationBoard.board(for: station, at: .now) {
                    count = trains.count
                } else {
                    count = 0
                }
                detail = "\(station.name) · \(count) departures"
            }
    }
}
