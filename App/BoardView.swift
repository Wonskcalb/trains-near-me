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
    /// The radar's station, picked row and pushed screens, which outlive this view across a Duo fold.
    @Binding private var nearMe: NearMeState

    init(journey: JourneyConfiguration?, nearMe: Binding<NearMeState> = .constant(NearMeState())) {
        self.journey = journey
        _nearMe = nearMe
    }

    @Environment(\.spansFold) private var spansFold
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model
    @State private var origin: Station?
    /// nil on the radar, which has no destination.
    @State private var destination: Station?
    @State private var state: BoardState?
    @State private var fetchedAt = Date.distantPast
    @State private var loading = false
    /// The departure a tap opened the full-trip sheet for, nil when closed.
    @State private var trip: TripRequest?
    /// Swap shows the journey the other way round for this visit, without touching the saved one.
    @State private var swapped = false
    @State private var added = false

    /// A fresh fix is only ever worth asking for where the position decides what is shown.
    private var followsYou: Bool { journey?.nearestStationAsDeparture ?? true }
    /// The radar as the list column of the Duo's list | map split, where the map is always beside it.
    private var isColumn: Bool { spansFold && journey == nil }
    /// A journey a terminus of the line map opened, not among the saved ones until "Add to my journeys".
    private var isUnsaved: Bool {
        guard let journey, !added else { return false }
        return !SharedSettings.favorites.contains { $0.stationA.id == journey.stationA.id && $0.stationB.id == journey.stationB.id }
    }

    var body: some View {
        // Trains that have left have to drop off the list on their own: unlike a widget, a screen
        // can sit open for an hour, and the fetch is good for the whole evening.
        TimelineView(.everyMinute) { context in
            scroll(now: context.date)
        }
        .background(Color.ground.ignoresSafeArea())
        .refreshable { await load() }
        .task {
            // Also on coming back to a screen whose delays have gone stale; pull down for the rest.
            if state == nil || RefreshPlanner.isStale(fetchedAt: fetchedAt, at: .now) { await load() }
        }
        // The headers are drawn in the content — the radar's dish has to sweep, the journey has its
        // route glyph — so the bar carries only the back button a pushed board gets for free.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Every icon item is a titled Label so the Duo can stand it up in its strip; "Find me!" stays
        // text, which the system keeps horizontal at the top, as on a plain iPhone.
        .toolbar {
            if followsYou {
                // `current()` hands back the system's cached fix while it is under 15 min old,
                // which is right for a board that reloads on its own and wrong for someone who
                // has just got off a train. This asks for a live one.
                // Named rather than an arrow: it is the one control that does something pulling
                // down does not, and a toolbar renders a `Label` icon-only whatever its label style.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Find me!") { Task { await load(freshLocation: true) } }
                        .disabled(loading)
                }
            }
            if isUnsaved, let journey {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add to my journeys", systemImage: "star") {
                        SavedJourneys.save(SharedSettings.favorites + [journey], data: data, model: model)
                        added = true
                    }
                }
            }
        }
        // Round trip reads the saved journeys, so an unsaved one gets it once it is added.
        .modifier(JourneyToolbar(isEnabled: journey != nil && !isUnsaved,
                                 leg: origin.flatMap { from in destination.map { Leg(from: from, to: $0) } },
                                 swap: {
            swapped.toggle()
            Task { await load() }
        }))
        // The line map's Refresh lands here too, so the list beside it is never older than the map.
        .onChange(of: model.refreshTick) { Task { await load() } }
        .sheet(item: $trip) { request in
            TripSheet(train: request.train, boarding: request.boarding)
        }
    }

    /// Opens the full-trip sheet, but only for a row that carries a vehicle_journey id — a board cached
    /// by an older build has none, so a tap there does nothing rather than open an empty sheet.
    private func showTrip(_ train: TrainDeparture) {
        guard train.vehicleJourneyID != nil else { return }
        trip = TripRequest(train: train, boarding: origin?.name)
    }

    // No service gets a full-bleed hazard band that has to run under the navigation bar, so it is its
    // own layout rather than a card inside the padded column.
    @ViewBuilder private func scroll(now: Date) -> some View {
        if case .noService = state {
            noServiceScroll(now: now)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content(now: now)
                    if state != nil { footerView(now: now) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Headers

    /// The radar's own title, drawn rather than handed to the navigation bar: a large title is
    /// rendered from a plain string, so an interpolated symbol is dropped on the way in. Drawing it
    /// also buys the one thing a title cannot do — the dish sweeps while a position is being found.
    private var radarTitle: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.amber)
                .symbolEffect(.variableColor.iterative, isActive: loading)
            Text("Near me").font(.largeTitle.bold()).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var header: some View {
        if journey == nil {
            radarTitle
        } else {
            VStack(alignment: .leading, spacing: 14) {
                routeHeader
                chips
            }
        }
    }

    private var routeHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            RoutePins(destination: .solid(.amber), originDiameter: 10, destinationDiameter: 14)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(origin?.name ?? " ")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.7))
                Text(destination?.name ?? "Journey")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip("DIRECT ONLY")
            if let journey { chip(directionCaps(journey)) }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.mono(11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Color.ink.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    /// The journey's direction as a mono-caps chip, the counterpart of the Journeys tab's rule.
    private func directionCaps(_ journey: JourneyConfiguration) -> String {
        if journey.nearestStationAsDeparture { return "FOLLOWS YOU" }
        switch journey.direction {
        case .forward: return "ALWAYS THIS WAY"
        case .reverse: return "ALWAYS REVERSED"
        case .automatic: return "REVERSES AT \(clock(journey.switchMinute))"
        }
    }

    // MARK: Content

    @ViewBuilder private func content(now: Date) -> some View {
        switch state {
        case nil:
            loadingCard
        case .departures(let trains):
            if journey == nil { radarDepartures(trains, now: now) } else { journeyDepartures(trains, now: now) }
        case .noTrains:
            messageCard("No trains", "No departure found for now.")
        case .endOfService(let firstTrain):
            endOfServiceCard(firstTrain: firstTrain, now: now)
        case .noService:
            EmptyView() // Handled by `noServiceScroll`.
        case .unavailable(let error):
            messageCard("SNCF data unavailable", error.appDescription)
        }
    }

    @ViewBuilder private func radarDepartures(_ trains: [TrainDeparture], now: Date) -> some View {
        let upcoming = trains.filter { $0.expectedDeparture > now }
        if upcoming.isEmpty {
            messageCard("No more trains", "Nothing left of the last fetch. Pull down to look again.")
        } else {
            nearestCard(next: upcoming[0], now: now)
                .contentShape(Rectangle())
                .onTapGesture { showTrip(upcoming[0]) }
            if upcoming.count > 1 {
                TrackRule(label: "THEN")
                boardCard {
                    let rows = Array(upcoming.dropFirst().enumerated())
                    ForEach(rows, id: \.element) { idx, train in
                        RadarRow(train: train, now: now)
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .selectedRowBackground(isColumn && nearMe.selected == train)
                            .contentShape(Rectangle())
                            // Beside the map a tap picks the row; tapping the picked row again opens its trip.
                            .onTapGesture {
                                if isColumn, nearMe.selected != train { nearMe.selected = train } else { showTrip(train) }
                            }
                            .accessibilityAddTraits(isColumn && nearMe.selected == train ? .isSelected : [])
                        if idx < rows.count - 1 { rowDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder private func journeyDepartures(_ trains: [TrainDeparture], now: Date) -> some View {
        let upcoming = trains.filter { $0.expectedDeparture > now }
        if upcoming.isEmpty {
            messageCard("No more trains", "Nothing left of the last fetch. Pull down to look again.")
        } else {
            boardCard {
                let rows = Array(upcoming.enumerated())
                ForEach(rows, id: \.element) { idx, train in
                    JourneyRow(train: train, now: now, isFirst: idx == 0)
                        .padding(.horizontal, 16).padding(.vertical, 15)
                        .background(idx == 0 ? Color.amber.opacity(0.06) : Color.clear)
                    if idx < rows.count - 1 { rowDivider }
                }
            }
        }
    }

    /// The radar's hero: the nearest station, and its very next train on the split-flap.
    private func nearestCard(next: TrainDeparture, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEAREST STATION")
                        .font(.mono(11, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Color.inkSecondary)
                    Text(origin?.name ?? "Station")
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(Color.ink)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle().fill(Color.soon).frame(width: 7, height: 7)
                    Text(next.expectedDeparture.formatted(SNCFTime.hourMinute))
                        .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
            if isColumn {
                // Half a portrait Duo is 334 pt: the flaps shrink before the destination breaks mid-word.
                ViewThatFits(in: .horizontal) {
                    heroRow(next: next, now: now, tile: 36)
                    heroRow(next: next, now: now, tile: 26)
                }
            } else {
                heroRow(next: next, now: now, tile: 36)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func heroRow(next: TrainDeparture, now: Date, tile: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 16) {
            FlapTime(date: next.expectedDeparture, tileWidth: tile, tileHeight: tile * 52 / 36)
            VStack(alignment: .leading, spacing: 4) {
                if let direction = next.direction {
                    Text(direction).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                        .lineLimit(2).minimumScaleFactor(0.85)
                }
                HStack(spacing: 7) {
                    if let mode = next.mode { ModeChip(mode) }
                    if let number = next.trainNumber {
                        Text("N° \(number)").font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Text(leavesIn(next, now: now))
                    .font(.mono(13, weight: .semibold)).foregroundStyle(Color.soon)
            }
            // At 362 pt (an iPhone 17 Pro, the folded Duo) the flaps took their share first and the
            // destination truncated to "Grenob…"; the words are what the card is read for.
            .layoutPriority(1)
            Spacer(minLength: 0)
            if next.vehicleJourneyID != nil {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary.opacity(0.6))
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Looking for trains…").foregroundStyle(Color.inkSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func messageCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).foregroundStyle(Color.ink)
            Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// The day is over. Keep the widget's navy-and-moon direction; the first train in amber mono.
    private func endOfServiceCard(firstTrain: Date, now: Date) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 26)).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 3) {
                Text("End of service").font(.headline).foregroundStyle(.white)
                (Text("First train at ")
                    .foregroundColor(.white.opacity(0.75))
                 + Text(firstTrain.formatted(SNCFTime.hourMinute))
                    .font(.mono(15, weight: .semibold)).foregroundColor(.amber))
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.night, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: No service

    private func noServiceScroll(now: Date) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HazardBackground(variant: .band)
                    .frame(height: 240)
                    .overlay(alignment: .bottom) { noServicePlate.padding(.bottom, 30) }
                    .ignoresSafeArea(edges: .top)
                VStack(alignment: .leading, spacing: 16) {
                    header
                    messageCard("All trains cancelled", "Every departure of the day is cancelled.")
                    sncfConnect("Find another way in SNCF Connect", amber: true)
                    disclaimer(full: false)
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
            }
        }
    }

    private var noServicePlate: some View {
        VStack(spacing: 5) {
            Text("NO SERVICE").font(.mono(30, weight: .heavy)).tracking(3).foregroundStyle(Color.ink)
            Text("Every train of the day is cancelled").font(.subheadline).foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(Color.ground, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    @ViewBuilder private func footerView(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            updatedLine(now: now)
            // The ticket link and disclaimer belong to a saved journey; the radar stays a bare board.
            if journey != nil {
                sncfConnect("Tickets & details in SNCF Connect", amber: false)
                disclaimer(full: true)
            }
        }
    }

    private func updatedLine(now: Date) -> some View {
        let stale = RefreshPlanner.isStale(fetchedAt: fetchedAt, at: now)
        let time = fetchedAt.formatted(SNCFTime.shortTime)
        return HStack(spacing: 7) {
            Circle().fill(stale ? Color.caution : Color.soon).frame(width: 7, height: 7)
            Text(stale ? "Delays last checked at \(time) — out of date" : "Updated at \(time) · pull to refresh")
                .font(.mono(12)).foregroundStyle(stale ? Color.caution : Color.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private func sncfConnect(_ title: String, amber: Bool) -> some View {
        Link(destination: URL(string: "https://www.sncf-connect.com")!) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 16, weight: amber ? .bold : .semibold))
                    .foregroundStyle(amber ? Color.ground : Color.ink)
                Image(systemName: "arrow.up.right").font(.subheadline.weight(.bold))
                    .foregroundStyle(amber ? Color.ground : Color.amber)
            }
            .frame(maxWidth: .infinity).frame(height: amber ? 52 : 50)
            .background(amber ? AnyShapeStyle(Color.amber) : AnyShapeStyle(Color.raised),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                if !amber { RoundedRectangle(cornerRadius: 16).stroke(Color.ink.opacity(0.08), lineWidth: 1) }
            }
        }
    }

    private func disclaimer(full: Bool) -> some View {
        Text(full
             ? "Not affiliated with SNCF. Train data © SNCF, via the SNCF open data API. Check the station boards before you run."
             : "Not affiliated with SNCF. Train data © SNCF, via the SNCF open data API.")
            .font(.footnote).foregroundStyle(Color.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 12)
    }

    // MARK: Shared bits

    private var rowDivider: some View { Divider().overlay(Color.ink.opacity(0.07)) }

    @ViewBuilder private func boardCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.05), lineWidth: 1))
    }

    /// The widget's end-of-service navy, reused so the two surfaces read as one app.
    private static let night = LinearGradient(
        colors: [Color(red: 0.10, green: 0.13, blue: 0.28), Color(red: 0.04, green: 0.05, blue: 0.12)],
        startPoint: .top, endPoint: .bottom)

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
            var leg = JourneySelector.leg(for: journey, at: now, location: location)
            if swapped { leg = Leg(from: leg.to, to: leg.from) }
            origin = leg.from
            destination = leg.to
            do {
                let departures = try await client.departures(from: leg.from, to: leg.to, at: now)
                state = .from(departures, now: now)
                // Foreground re-evaluation of watched trains: raw departures so cancellations survive.
                await TrainWatcher.shared.reevaluate(against: departures, to: leg)
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
                nearMe.station = station
                destination = nil
                let departures = try await client.departures(from: station, at: now)
                state = .from(departures, now: now)
                await TrainWatcher.shared.reevaluate(against: departures)
            } catch {
                state = .unavailable(error)
            }
        }
        fetchedAt = now
    }
}

// MARK: - Rows

/// A radar row: a time, where the train goes, and either the minutes left or a status pill.
struct RadarRow: View {
    let train: TrainDeparture
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(train.scheduledDeparture.formatted(SNCFTime.hourMinute))
                    .font(.mono(19, weight: .semibold))
                    .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.amber)
                    .strikethrough(train.isCancelled)
                if !train.isCancelled, let delay = train.delayMinutes, delay > 0 {
                    Text(train.expectedDeparture.formatted(SNCFTime.hourMinute))
                        .font(.mono(12, weight: .semibold))
                        .foregroundStyle(train.status.tableauInk)
                }
            }
            .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if let direction = train.direction {
                    Text(direction).font(.system(size: 16, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1)
                } else if let duration = train.duration {
                    Text("\(Int(duration / 60)) min").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.ink)
                }
                HStack(spacing: 7) {
                    if let mode = train.mode { ModeChip(mode) }
                    if let number = train.trainNumber {
                        Text("N° \(number)").font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    }
                }
            }
            .opacity(train.isCancelled ? 0.6 : 1)

            Spacer(minLength: 4)
            trailing
            if train.vehicleJourneyID != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary.opacity(0.5))
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch train.status {
        case .onTime:
            Text(relativeTime(train.expectedDeparture, from: now))
                .font(.mono(13)).foregroundStyle(Color.inkSecondary).fixedSize()
        case .delayed, .severelyDelayed:
            StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
        case .cancelled:
            StatusPill("CANCELLED", status: .cancelled)
        case .unknown:
            StatusPill("delay ?", status: .unknown)
        }
    }
}

/// A journey row: departure → arrival with a dashed connector, the next one tagged, delays shown as
/// a pill with the amended departure under it.
struct JourneyRow: View {
    let train: TrainDeparture
    let now: Date
    let isFirst: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(train.scheduledDeparture.formatted(SNCFTime.hourMinute))
                        .font(.mono(24, weight: .bold))
                        .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.amber)
                        .strikethrough(train.isCancelled)
                    if train.scheduledArrival != nil {
                        DashConnector()
                        Text(train.scheduledArrival!.formatted(SNCFTime.hourMinute))
                            .font(.mono(16, weight: .medium))
                            .foregroundStyle(Color.ink.opacity(0.85))
                            .strikethrough(train.isCancelled)
                    }
                }
                HStack(spacing: 7) {
                    if let mode = train.mode { ModeChip(mode) }
                    // The number goes first when the column is short (the Duo's folded 362 pt): the
                    // trip sheet still has it, and the duration is what a row is read for.
                    ViewThatFits(in: .horizontal) {
                        Text(numberAndDuration)
                        Text(train.duration.map { "\(Int($0 / 60)) min" } ?? "")
                    }
                    .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
            .opacity(train.isCancelled ? 0.6 : 1)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                if isFirst { nextTag }
                trailing
            }
        }
    }

    private var nextTag: some View {
        Text("NEXT")
            .font(.mono(10, weight: .bold)).tracking(1.2).foregroundStyle(Color.ground)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.amber, in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private var trailing: some View {
        switch train.status {
        case .onTime:
            Text(isFirst ? "in \(relativeTime(train.expectedDeparture, from: now))" : relativeTime(train.expectedDeparture, from: now))
                .font(.mono(isFirst ? 14 : 13, weight: isFirst ? .semibold : .regular))
                .foregroundStyle(isFirst ? Color.soon : Color.inkSecondary)
                .fixedSize()
        case .delayed, .severelyDelayed:
            StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
            Text("leaves \(train.expectedDeparture.formatted(SNCFTime.shortTime))")
                .font(.mono(12)).foregroundStyle(train.status.tableauInk)
        case .cancelled:
            StatusPill("CANCELLED", status: .cancelled)
        case .unknown:
            StatusPill("delay ?", status: .unknown)
        }
    }

    private var numberAndDuration: String {
        var parts: [String] = []
        if let number = train.trainNumber { parts.append("N° \(number)") }
        if let duration = train.duration { parts.append("\(Int(duration / 60)) min") }
        return parts.joined(separator: " · ")
    }
}

/// The dashed segment between a departure and its arrival.
private struct DashConnector: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.inkSecondary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .frame(width: 22, height: 2)
    }
}

private extension View {
    /// The standard Tableau card: surface fill, hairline border, generous radius.
    func cardSurface() -> some View {
        background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.05), lineWidth: 1))
    }
}

/// Minutes-from-now as "2 min" / "1 h 18", the words shared by the radar and the journey rows.
func relativeTime(_ date: Date, from now: Date) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
}

/// "in 2 min" / "leaving now" for the flap card's single next train.
func leavesIn(_ train: TrainDeparture, now: Date) -> String {
    let minutes = max(0, Int(train.expectedDeparture.timeIntervalSince(now) / 60))
    return minutes < 1 ? "leaving now" : "in \(relativeTime(train.expectedDeparture, from: now))"
}

/// A minute-count as "HH:MM", for the automatic switch time.
func clock(_ minuteOfDay: Int) -> String {
    String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
}

// MARK: - Full trip

/// A tapped departure, carried into the full-trip sheet.
struct TripRequest: Identifiable {
    let id = UUID()
    let train: TrainDeparture
    /// The station you would board at, highlighted in the list. nil on the radar before a fix.
    let boarding: String?
}

/// Every stop of one train's run, fetched on demand from the vehicle_journey id the tapped row
/// carried. A calling-points list: a rail of dots, the boarding stop picked out in amber, stops the
/// train passes without serving struck through.
struct TripSheet: View {
    let train: TrainDeparture
    let boarding: String?
    @Environment(\.dismiss) private var dismiss
    @State private var stops: [TripStop]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let stops { stopList(stops) }
                else if failed { failure }
                else { loadingView }
            }
            .background(Color.ground.ignoresSafeArea())
            .navigationTitle("Full trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await loadTrip() }
        }
    }

    private func loadTrip() async {
        guard let id = train.vehicleJourneyID else { failed = true; return }
        let client = SNCFClient(token: SharedSettings.token)
        do { stops = try await client.trip(vehicleJourneyID: id) }
        catch { failed = true }
    }

    private func stopList(_ stops: [TripStop]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tripHeader
                ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                    stopRow(stop, first: idx == 0, last: idx == stops.count - 1)
                }
            }
            .padding(20)
        }
    }

    private var tripHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let direction = train.direction {
                Text(direction).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.ink).lineLimit(2)
            }
            HStack(spacing: 8) {
                if let mode = train.mode { ModeChip(mode) }
                if let number = train.trainNumber {
                    Text("N° \(number)").font(.mono(13, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func stopRow(_ stop: TripStop, first: Bool, last: Bool) -> some View {
        let here = boarding.map { stop.name.localizedCaseInsensitiveContains($0) } ?? false
        return HStack(alignment: .center, spacing: 14) {
            Text(stop.time)
                .font(.mono(15, weight: here ? .bold : .medium))
                .foregroundStyle(stop.isSkipped ? Color.inkSecondary : (here ? Color.amber : Color.ink))
                .strikethrough(stop.isSkipped)
                .frame(width: 52, alignment: .leading)
            rail(first: first, last: last, here: here, skipped: stop.isSkipped)
                .frame(width: 16)
            Text(stop.name)
                .font(.system(size: 16, weight: here ? .semibold : .regular))
                .foregroundStyle(stop.isSkipped ? Color.inkSecondary : Color.ink)
                .strikethrough(stop.isSkipped)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stop.name), \(stop.isSkipped ? "passed without stopping, " : "")\(stop.time)")
    }

    /// The vertical line with this stop's dot: no line above the first stop, none below the last,
    /// the boarding stop a filled amber dot and a skipped one hollow and faded.
    private func rail(first: Bool, last: Bool, here: Bool, skipped: Bool) -> some View {
        // A GeometryReader here collapsed to zero height inside the row's HStack, so the dot landed
        // off-screen. Two greedy half-height rectangles draw the line and split at the centre, where
        // the dot sits — the segment above the first stop and below the last is simply left clear.
        let lineColor = Color.inkSecondary.opacity(0.4)
        return ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(first ? Color.clear : lineColor)
                Rectangle().fill(last ? Color.clear : lineColor)
            }
            .frame(width: 2)
            Circle()
                .fill(here ? Color.amber : (skipped ? Color.ground : Color.surface))
                .overlay(Circle().stroke(here ? Color.amber : Color.inkSecondary.opacity(skipped ? 0.4 : 0.8), lineWidth: 2))
                .frame(width: here ? 14 : 10, height: here ? 14 : 10)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading the trip…").foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failure: some View {
        VStack(spacing: 8) {
            Text("Trip unavailable").font(.headline).foregroundStyle(Color.ink)
            Text("Could not load the stops. Close this and try again.")
                .font(.subheadline).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
