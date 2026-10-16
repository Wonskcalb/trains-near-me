#if os(iOS)
import SNCFCore
import SwiftUI

/// What a saved journey opens into. On the Duo's inner display it is the station hall's board as the
/// leading column, its picked train going to the detail column; everywhere else, the iPhone board.
struct JourneyBoardScreen: View {
    let journey: JourneyConfiguration
    @Environment(\.spansFold) private var spansFold

    var body: some View {
        if spansFold {
            StationHallView(journey: journey)
        } else {
            BoardView(journey: journey)
        }
    }
}

/// The Journeys tab on the Duo's inner display: the list (and the board it pushes) up to the fold, then
/// the picked train, or Lanes while no journey is open. A `NavigationSplitView` rather than two stacks
/// side by side, because only a split's detail column gets its bar stood up in the system strip.
struct JourneysSplit: View {
    @Environment(BigScreenModel.self) private var model
    @Environment(\.previewFold) private var previewFold

    var body: some View {
        @Bindable var model = model
        // Re-read on every geometry pass: the region is a geometry value, so opening or closing the hinge
        // moves the columns' edges here and nothing else (the hinge angle is never read).
        GeometryReader { proxy in
            let split = Fold.split(width: proxy.size.width, region: Fold.region(in: proxy, preview: previewFold))
            NavigationSplitView(columnVisibility: .constant(.all)) {
                NavigationStack(path: $model.journeyPath) { JourneysView() }
                    .padding(.trailing, split.leadingPadding)
                    // All three bounds: a lone width is still clamped to the split's own sidebar maximum,
                    // which on a 951 pt screen falls well short of the fold.
                    .navigationSplitViewColumnWidth(min: split.leadingWidth, ideal: split.leadingWidth,
                                                    max: split.leadingWidth)
            } detail: {
                Group {
                    if let picked = model.detailTrain, !model.journeyPath.isEmpty {
                        TrainDetail(picked: picked)
                    } else {
                        LanesView()
                    }
                }
                .padding(.leading, split.detailPadding)
            }
            .navigationSplitViewStyle(.balanced)
        }
    }
}

/// The detail column's train: the inspector with its Watch and Share moved into the column's toolbar,
/// which the Duo stands up in the strip. Fetches its own stops, the board column having no inspector.
private struct TrainDetail: View {
    @Environment(\.bigScreenData) private var data
    let picked: PickedTrain
    @State private var stops: [TripStop] = []

    var body: some View {
        TimelineView(.everyMinute) { context in
            TrainInspector(train: picked.train, leg: picked.leg, stops: stops, now: context.date,
                           actionsInToolbar: true, onClose: {})
        }
        .task(id: picked.train) {
            guard let id = picked.train.vehicleJourneyID else { stops = []; return }
            stops = (try? await data.trainStops.stops(forVehicleJourneyID: id)) ?? []
        }
    }
}

extension BigScreenRoute: Identifiable {
    var id: Self { self }
}

/// A journey board's toolbar on iPhone: Round trip (the prominent action), Swap and Wall. Labels with
/// symbols, so the Duo stacks them in its strip and a plain iPhone keeps them in the top bar. Round trip
/// and Wall have no tab of their own, so they cover the screen and close back onto the board.
struct JourneyToolbar: ViewModifier {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model
    /// False on the Near me radar, which shares `BoardView` but has no journey to act on.
    var isEnabled = true
    /// nil disables Swap: the hall board can only swap to a saved reverse journey.
    let swap: (() -> Void)?
    @State private var cover: BigScreenRoute?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isEnabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(BigScreenRoute.roundTrip.title, systemImage: BigScreenRoute.roundTrip.symbol) { cover = .roundTrip }
                            .prominentToolbarButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Swap direction", systemImage: "arrow.up.arrow.down") { swap?() }
                            .disabled(swap == nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(BigScreenRoute.wall.title, systemImage: BigScreenRoute.wall.symbol) { cover = .wall }
                    }
                }
            }
            .fullScreenCover(item: $cover) { route in
                NavigationStack {
                    if route == .wall {
                        // The wall places its own Close: in the bottom bar with its other controls on the
                        // desk clock, at the top otherwise.
                        WallModeView(onClose: { cover = nil })
                    } else {
                        RoundTripView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close", systemImage: "xmark") { cover = nil }
                                }
                            }
                    }
                }
                // Re-injected: the cover is its own presentation, and the live data must not fall back to
                // the environment's fake default.
                .environment(\.bigScreenData, data)
                .environment(model)
            }
            #if DEBUG
            .onAppear { if isEnabled, ScreenshotSupport.openWall { cover = .wall } }
            #endif
    }
}
#endif
