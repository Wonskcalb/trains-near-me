#if os(iOS)
import CoreLocation
import SNCFCore
import SwiftUI

/// One station board inside the app: the next direct trains of a saved journey, or everything
/// leaving the station closest to you. The widget's provider makes the same two or three calls, but
/// it has to answer with a WidgetKit timeline entry and cache it per widget, so the fetch is
/// repeated here rather than shared.
struct BoardView: View {
    /// nil is the radar, which finds its own station.
    let journey: JourneyConfiguration?

    @State private var origin: Station?
    /// nil on the radar, which has no destination.
    @State private var destination: Station?
    @State private var state: BoardState?
    @State private var fetchedAt = Date.distantPast
    @State private var loading = false

    /// A fresh fix is only ever worth asking for where the position decides what is shown.
    private var followsYou: Bool { journey?.nearestStationAsDeparture ?? true }

    var body: some View {
        // Trains that have left have to drop off the list on their own: unlike a widget, a screen
        // can sit open for an hour, and the fetch is good for the whole evening.
        TimelineView(.everyMinute) { context in
            List {
                if journey == nil { radarTitle }
                Section {
                    content(now: context.date)
                } header: {
                    header
                } footer: {
                    if state != nil { footer(now: context.date) }
                }
            }
        }
        // The navigation bar is empty on the radar — the title is drawn in the list — so the
        // list's own top margin would stack on top of a bar's worth of nothing.
        .contentMargins(.top, journey == nil ? 0 : nil, for: .scrollContent)
        .refreshable { await load() }
        .task {
            // Also on coming back to a screen whose delays have gone stale; pull down for the rest.
            if state == nil || RefreshPlanner.isStale(fetchedAt: fetchedAt, at: .now) { await load() }
        }
        .navigationTitle(journey == nil ? "" : origin?.name ?? "Journey")
        .navigationBarTitleDisplayMode(journey == nil ? .inline : .large)
        .toolbar {
            if followsYou {
                // `current()` hands back the system's cached fix while it is under 15 min old,
                // which is right for a board that reloads on its own and wrong for someone who
                // has just got off a train. This asks for a live one.
                // Named rather than an arrow: it is the one control that does something pulling
                // down does not, and a toolbar renders a `Label` icon-only whatever its label style.
                Button("Find me!") { Task { await load(freshLocation: true) } }
                    .disabled(loading)
            }
        }
    }

    /// The radar's own title, drawn rather than handed to the navigation bar: a large title is
    /// rendered from a plain string, so an interpolated symbol is dropped on the way in. Drawing it
    /// also buys the one thing a title cannot do — the dish sweeps while a position is being found.
    private var radarTitle: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: loading)
            Text("Near me").font(.largeTitle.bold())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 10, trailing: 0))
    }

    @ViewBuilder private var header: some View {
        if let origin {
            if let destination {
                Text("\(origin.name) → \(destination.name)")
            } else {
                Text("Departures from \(origin.name)")
            }
        } else {
            Text(journey == nil ? "Nearest station" : "Journey")
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        switch state {
        case nil:
            HStack(spacing: 8) {
                ProgressView()
                Text("Looking for trains…").foregroundStyle(.secondary)
            }
        case .departures(let trains):
            let upcoming = trains.filter { $0.expectedDeparture > now }
            if upcoming.isEmpty {
                message("No more trains", "Nothing left of the last fetch. Pull down to look again.")
            } else {
                ForEach(upcoming, id: \.self) { TrainRow(train: $0) }
            }
        case .noTrains:
            message("No trains", "No departure found for now.")
        case .endOfService(let firstTrain):
            message("End of service", "First train at \(firstTrain.formatted(date: .omitted, time: .shortened)).")
        case .noService:
            message("All trains cancelled", "Every departure of the day is cancelled.")
        case .unavailable(let error):
            message("SNCF data unavailable", error.appDescription)
        }
    }

    private func footer(now: Date) -> some View {
        Text(RefreshPlanner.isStale(fetchedAt: fetchedAt, at: now)
             ? "Delays last checked at \(fetchedAt.formatted(date: .omitted, time: .shortened)) — out of date"
             : "Updated at \(fetchedAt.formatted(date: .omitted, time: .shortened))")
            .foregroundStyle(RefreshPlanner.isStale(fetchedAt: fetchedAt, at: now) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// "Find me!" refuses the cache; everything else takes whatever the system already has.
    private func fix(fresh: Bool) async -> CLLocation? {
        await LocationFix.shared.current(cachedWithin: fresh ? 0 : 15 * 60)
    }

    /// SwiftUI cancels the task behind `refreshable` the moment its control goes away, and a
    /// cancelled request comes back out of the client as "the SNCF API is not responding" — a
    /// pull-to-refresh looked broken while the same work from a button succeeded. An unstructured
    /// task does not inherit that cancellation, so every caller gets the same fetch.
    private func load(freshLocation: Bool = false) async {
        await Task { await fetch(freshLocation: freshLocation) }.value
    }

    private func fetch(freshLocation: Bool) async {
        // The settings used to be the whole app and asked on launch; now they are a tab a reader
        // may never open, so the screen that needs a position is the one that asks for it.
        if followsYou, LocationFix.shared.status == .notDetermined { LocationFix.shared.requestAuthorization() }
        loading = true
        defer { loading = false }
        let now = Date.now
        let client = SNCFClient(token: SharedSettings.token)
        if let journey {
            // Nearest-station mode needs a fix; without one the configured order applies, as in the widget.
            let location = journey.nearestStationAsDeparture ? await fix(fresh: freshLocation) : nil
            let leg = JourneySelector.leg(for: journey, at: now, location: location)
            origin = leg.from
            destination = leg.to
            do {
                state = .from(try await client.departures(from: leg.from, to: leg.to, at: now), now: now)
            } catch {
                state = .unavailable(error)
            }
        } else {
            guard let location = await fix(fresh: freshLocation) else {
                state = .unavailable(.noLocation)
                fetchedAt = now
                return
            }
            do {
                guard let station = try await client.nearestStation(latitude: location.coordinate.latitude,
                                                                    longitude: location.coordinate.longitude) else {
                    state = .unavailable(.noStationNearby)
                    fetchedAt = now
                    return
                }
                origin = station
                destination = nil
                state = .from(try await client.departures(from: station, at: now), now: now)
            } catch {
                state = .unavailable(error)
            }
        }
        fetchedAt = now
    }
}

extension TrainServiceError {
    /// `missingToken`'s own wording tells you to open the app, which is where a reader of this
    /// screen already is; everything else reads the same here as in a widget.
    var appDescription: String {
        self == .missingToken ? "Add your SNCF API token in the Settings tab." : localizedDescription
    }
}

/// A row of the app's board. The widget has its own, shaped for a panel a few centimetres wide;
/// this one has a whole screen and says more.
struct TrainRow: View {
    let train: TrainDeparture

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(train.scheduledDeparture, format: .dateTime.hour().minute())
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .strikethrough(train.isCancelled)
                if !train.isCancelled, let delay = train.delayMinutes, delay > 0 {
                    Text(train.expectedDeparture, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                // A journey knows how long it takes; a station board knows where the train goes.
                if let direction = train.direction {
                    Text(direction).lineLimit(1)
                } else if let duration = train.duration {
                    Text("\(Int(duration / 60)) min")
                }
                HStack(spacing: 6) {
                    if let mode = train.mode {
                        Text(mode)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let number = train.trainNumber {
                        Text(number).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)
            badge
        }
        .opacity(train.isCancelled ? 0.75 : 1)
    }

    @ViewBuilder private var badge: some View {
        switch train.status {
        case .onTime:
            if let delay = train.delayMinutes, delay > 0 { label("+\(delay)", .secondary) }
        case .delayed, .severelyDelayed:
            label("+\(train.delayMinutes ?? 0)", tint)
        case .cancelled:
            label("CANCELLED", tint)
        case .unknown:
            label("delay ?", tint)
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .fixedSize()
    }

    private var tint: Color {
        switch train.status {
        case .onTime: .secondary
        case .delayed, .unknown: .orange
        case .severelyDelayed, .cancelled: .red
        }
    }
}
#endif
