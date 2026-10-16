#if os(iOS)
import SNCFCore
import SwiftUI

/// Where the Near me tab stands. Held by `RootView` rather than the tab, so folding a Duo, which swaps the
/// tab between a plain stack and the list | map split, keeps the station, the picked row and what is pushed.
struct NearMeState {
    /// The station the radar last found: the line map's station.
    var station: Station?
    /// The row picked in the split's list; on a plain iPhone a tap opens the trip instead.
    var selected: TrainDeparture?
    /// The folded stack: Lines, then a journey a terminus opened. Unfolded the map is the detail column's
    /// root, so that column only shows what comes after `.lines`.
    var path: [NearMeRoute] = []

    /// The journey station → terminus a lane of the map asked for, pushed over the map.
    mutating func open(_ leg: Leg) {
        path = [.lines, .journey(JourneyConfiguration(stationA: leg.from, stationB: leg.to))]
    }
}

enum NearMeRoute: Hashable {
    case lines
    /// Unsaved: its board offers "Add to my journeys".
    case journey(JourneyConfiguration)
}

/// What a Near me route opens, in the folded stack and in the split's detail column alike. Takes the
/// binding rather than the station: a `navigationDestination` closure is not re-run when a value it reads
/// changes, so a station passed in there stayed the nil it was at launch.
struct NearMeDestination: View {
    let route: NearMeRoute
    @Binding var nearMe: NearMeState

    var body: some View {
        switch route {
        case .lines: if let station = nearMe.station { NearMeMap(station: station) }
        case .journey(let journey): BoardView(journey: journey)
        }
    }
}

/// The station's line map with its Refresh as a titled toolbar item, so the Duo stands it in the strip.
private struct NearMeMap: View {
    @Environment(BigScreenModel.self) private var model
    let station: Station

    var body: some View {
        StationBoardView(station: station)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                }
            }
    }
}

/// The Near me tab on the Duo's inner display: the radar list up to the fold, the nearest station's line
/// map beyond it. A `NavigationSplitView` for the same reason as `JourneysSplit`: only a split's detail
/// column gets its bar stood up in the system strip, while "Find me!" stays in the list's horizontal bar.
struct NearMeSplit: View {
    @Binding var nearMe: NearMeState

    var body: some View {
        GeometryReader { proxy in
            NavigationSplitView(columnVisibility: .constant(.all)) {
                BoardView(journey: nil, nearMe: $nearMe)
                    .navigationSplitViewColumnWidth(Fold.leadingWidth(in: proxy))
            } detail: {
                NavigationStack(path: detailPath) {
                    Group {
                        if nearMe.station != nil {
                            NearMeDestination(route: .lines, nearMe: $nearMe)
                        } else {
                            ContentUnavailableView("Looking for the nearest station",
                                                   systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .navigationDestination(for: NearMeRoute.self) { NearMeDestination(route: $0, nearMe: $nearMe) }
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    /// The folded path minus Lines, which this column always shows. Popping back to the map here leaves
    /// Lines pushed, so folding then lands on the map you were reading.
    private var detailPath: Binding<[NearMeRoute]> {
        Binding(get: { nearMe.path.filter { $0 != .lines } },
                set: { nearMe.path = [.lines] + $0 })
    }
}
#endif
