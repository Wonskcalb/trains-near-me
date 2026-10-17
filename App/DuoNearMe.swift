#if os(iOS)
import SNCFCore
import SwiftUI

/// Where the Near me tab stands. Held by `RootView` rather than the tab, so folding a Duo, which swaps the
/// tab between a plain stack and the list | map split, keeps the station, the picked row, the List | Lines
/// switch and what is pushed.
struct NearMeState {
    /// The station the radar last found: the line map's station.
    var station: Station?
    /// The row picked in the split's list; on a plain iPhone a tap opens the trip instead.
    var selected: TrainDeparture?
    /// The folded tab's List | Lines switch. Unfolded both are on screen and the switch is hidden.
    var showsLines = false
    /// Journeys a terminus of the map opened, pushed over the map: the folded stack's path and the split's
    /// detail column's alike, so folding keeps the board you had open.
    var path: [JourneyConfiguration] = []

    /// The journey station → terminus a lane of the map asked for, pushed over the map. Unsaved: its board
    /// offers "Add to my journeys".
    mutating func open(_ leg: Leg) {
        showsLines = true
        path = [JourneyConfiguration(stationA: leg.from, stationB: leg.to)]
    }
}

/// The radar station's line map, or a placeholder until there is one. Looks the station up itself when
/// Lines is picked before the radar has found it, which would otherwise leave the placeholder up for good.
struct NearMeLines: View {
    @Binding var nearMe: NearMeState
    @Environment(\.bigScreenData) private var data

    var body: some View {
        if let station = nearMe.station {
            NearMeMap(station: station, highlighted: nearMe.selected)
        } else {
            ContentUnavailableView("Looking for the nearest station", systemImage: "antenna.radiowaves.left.and.right")
                .task {
                    if let station = try? await data.stationSearch.nearest().station, nearMe.station == nil {
                        nearMe.station = station
                    }
                }
        }
    }
}

/// The station's line map with its Refresh as a titled toolbar item, so the Duo stands it in the strip.
private struct NearMeMap: View {
    @Environment(BigScreenModel.self) private var model
    let station: Station
    /// The row picked in the list beside it, ringed on the map.
    let highlighted: TrainDeparture?

    var body: some View {
        StationBoardView(station: station, highlighted: highlighted)
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
                NavigationStack(path: $nearMe.path) {
                    NearMeLines(nearMe: $nearMe)
                        .navigationDestination(for: JourneyConfiguration.self) { BoardView(journey: $0) }
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }
}

extension View {
    /// The folded tabs' top switch (Near me's List | Lines, Journeys' List | Lanes). In the content rather
    /// than the toolbar: the folded Duo stands its bar up in the trailing strip, where a segmented control
    /// has no place, while a bar in the safe area stays on top in every pose.
    @ViewBuilder func modeSwitch(_ selection: Binding<Bool>, _ off: String, _ on: String) -> some View {
        let picker = Picker("View", selection: selection) {
            Text(off).tag(false)
            Text(on).tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        if #available(iOS 26, *) {
            safeAreaBar(edge: .top) { picker }
        } else {
            safeAreaInset(edge: .top) { picker.background(Color.ground) }
        }
    }
}
#endif
