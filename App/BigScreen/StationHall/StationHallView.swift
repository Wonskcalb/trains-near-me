import SNCFCore
import SwiftUI

/// Station hall — sidebar / journey board / train inspector (Main.dc.html).
// Phase 1 owner fills this.
struct StationHallView: View {
    @Environment(\.bigScreenData) private var data
    @State private var detail = "Loading…"

    var body: some View {
        BigScreenPlaceholder(route: .stationHall, detail: detail)
            .task { detail = "\(await data.journeyBoards.boards(at: .now).count) saved journeys" }
    }
}
