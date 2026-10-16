#if os(iOS)
import CoreLocation
import SNCFCore
import SwiftUI

/// Every saved journey at once: one card each, its next departures sliding sideways inside it, and
/// an icon on its title as soon as something is wrong with it. The boards refresh themselves; the
/// button is there for when you do not want to wait for that. An Edit mode collapses the cards into a
/// plain list for deleting, reordering by hand, and editing a journey in place.
struct JourneysView: View {
    @State private var journeys = SharedSettings.favorites
    @State private var boards = JourneyBoards()
    @State private var now = Date.now
    @State private var adding = false
    @State private var editing = false
    @State private var editTarget: JourneyConfiguration?
    @State private var showingLanes = false
    @Environment(\.spansFold) private var spansFold

    var body: some View {
        Group {
            if journeys.isEmpty {
                ContentUnavailableView {
                    Label("No saved journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                } description: {
                    Text("Save one to see its next direct trains here, and to have its stations offered when you configure a Trip widget.")
                } actions: {
                    Button("Add a journey") { adding = true }
                }
            } else if editing {
                editList
            } else {
                cards
            }
        }
        .background(Color.ground.ignoresSafeArea())
        .navigationTitle("Journeys")
        // A value link, so the pushed journey is the stack's path, which the shared model keeps across a fold.
        .navigationDestination(for: JourneyConfiguration.self) { JourneyBoardScreen(journey: $0) }
        .navigationDestination(isPresented: $showingLanes) { LanesView() }
        .toolbar {
            // The toggle only earns its place once there is something to manage.
            if !journeys.isEmpty {
                Button(editing ? "Done" : "Edit") { editing.toggle() }
            }
            Button("Add a journey", systemImage: "plus") { adding = true }
            // On the Duo's inner display Lanes is already the detail column; elsewhere it is one push away.
            if !spansFold, !journeys.isEmpty {
                Button(BigScreenRoute.lanes.title, systemImage: BigScreenRoute.lanes.symbol) { showingLanes = true }
            }
        }
        .tint(.amber)
        .refreshable { await boards.load(journeys) }
        .sheet(isPresented: $adding) {
            EditJourneyView { journey in
                journeys.append(journey)
                SharedSettings.favorites = journeys
            }
        }
        // Editing a journey replaces it in place by its old identity, so its board simply reloads on
        // the next tick rather than needing the dict hand-patched.
        .sheet(item: $editTarget) { target in
            EditJourneyView(existing: target) { updated in
                if let i = journeys.firstIndex(of: target) { journeys[i] = updated }
                SharedSettings.favorites = journeys
            }
        }
        // One loop does all three jobs: the first load, the minute tick that drops the trains
        // which have left, and the refetch once the delays have gone stale.
        .task {
            while !Task.isCancelled {
                now = .now
                if boards.needsLoad(for: journeys, at: now) { await boards.load(journeys) }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                updatedAt
                ForEach(journeys, id: \.self) { journey in
                    JourneyCard(journey: journey, board: boards.boards[journey], now: now)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editTarget = journey }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(journey) }
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // A List buys swipe-to-delete for free; tapping a row edits it in place.
    private var editList: some View {
        List {
            ForEach(journeys, id: \.self) { journey in
                Button { editTarget = journey } label: {
                    CompactJourneyRow(journey: journey)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.surface)
            }
            .onDelete(perform: deleteAt)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var updatedAt: some View {
        HStack(spacing: 7) {
            if boards.loading {
                ProgressView().controlSize(.mini)
                Text("Updating…").font(.mono(12)).foregroundStyle(Color.inkSecondary)
            } else if let fetchedAt = boards.fetchedAt {
                let stale = RefreshPlanner.isStale(fetchedAt: fetchedAt, at: now)
                Circle().fill(stale ? Color.caution : Color.soon).frame(width: 7, height: 7)
                Text("\(stale ? "Delays last checked at" : "Updated at") \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.mono(12)).foregroundStyle(stale ? Color.caution : Color.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func delete(_ journey: JourneyConfiguration) {
        journeys.removeAll { $0 == journey }
        SharedSettings.favorites = journeys
        if journeys.isEmpty { editing = false }
    }

    private func deleteAt(_ offsets: IndexSet) {
        journeys.remove(atOffsets: offsets)
        SharedSettings.favorites = journeys
        if journeys.isEmpty { editing = false }
    }
}

/// A journey as a plain row, for the edit list: just where it goes and how it is read, no live board.
struct CompactJourneyRow: View {
    let journey: JourneyConfiguration

    var body: some View {
        HStack(spacing: 12) {
            RoutePins(destination: .ring(core: .ink, ring: .amber), originDiameter: 9, destinationDiameter: 12)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(journey.stationA.name).font(.system(size: 13)).foregroundStyle(Color.inkSecondary).lineLimit(1)
                Text(journey.stationB.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.ink).lineLimit(1)
            }
            Spacer(minLength: 8)
            DirectionRule(journey: journey)
        }
        .padding(.vertical, 6)
    }
}

/// One saved journey: where it goes, what is wrong with it, and its next departures as tiles.
struct JourneyCard: View {
    let journey: JourneyConfiguration
    let board: LoadedBoard?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: journey) {
                HStack(spacing: 12) {
                    RoutePins(destination: .ring(core: .ink, ring: .amber), originDiameter: 9, destinationDiameter: 12)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(origin).font(.system(size: 13)).foregroundStyle(Color.inkSecondary).lineLimit(1)
                        HStack(spacing: 7) {
                            Text(destination).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.ink).lineLimit(1)
                            if let trouble = board?.trouble(at: now) {
                                Image(systemName: trouble.symbol)
                                    .font(.footnote)
                                    .foregroundStyle(tableauTint(trouble.tint))
                                    .accessibilityLabel(trouble.label)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    DirectionRule(journey: journey)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary.opacity(0.7))
                }
                // SwiftUI only hit-tests what is drawn, so the gap between the title and the
                // chevron — most of the row — was not tappable. The tiles stay out of it: they
                // are a sibling of this link, not part of its label.
                .contentShape(.rect)
                // The card's own padding, taken by the link instead, so the target reaches the
                // card's edges rather than stopping short of them.
                .padding(16)
            }
            .buttonStyle(.plain)

            tiles
                .padding([.horizontal, .bottom], 16)
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }

    /// The leg actually being shown once it is known: an automatic journey past its switch time, or
    /// one that follows you, does not run in the order it was saved in.
    private var origin: String { board?.leg.from.name ?? journey.stationA.name }
    private var destination: String { board?.leg.to.name ?? journey.stationB.name }

    @ViewBuilder private var tiles: some View {
        switch board?.state {
        case nil:
            note("Looking for trains…")
        case .departures(let trains):
            let upcoming = trains.filter { $0.expectedDeparture > now }
            if upcoming.isEmpty {
                note("No more trains in what was fetched. Pull down to look again.")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(upcoming, id: \.self) { DepartureTile(train: $0, now: now) }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                // The tiles run to both edges of the card, which is what says they slide.
                .padding(.horizontal, -16)
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        case .noTrains:
            note("No departure found for now.")
        case .endOfService(let firstTrain):
            HStack {
                Text("End of service").font(.system(size: 14)).foregroundStyle(Color.ink.opacity(0.8))
                Spacer()
                Text("First train \(firstTrain.formatted(date: .omitted, time: .shortened))")
                    .font(.mono(13, weight: .semibold)).foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 14))
        case .noService:
            note("Every train of the day is cancelled.")
        case .unavailable(let error):
            note(error.appDescription)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    /// Trouble carries a system tint (orange/red/secondary); remap it to the Tableau palette so the
    /// icon reads the same as the rest of the app in both schemes.
    private func tableauTint(_ color: Color) -> Color {
        if color == .red { return .stop }
        if color == .orange { return .caution }
        return .inkSecondary
    }
}

/// How a journey is read, as a mono-caps rule: the direction, or that it follows you.
struct DirectionRule: View {
    let journey: JourneyConfiguration

    var body: some View {
        HStack(spacing: 5) {
            if journey.nearestStationAsDeparture {
                Image(systemName: "location.fill").font(.system(size: 9))
            }
            Text(text).font(.mono(10.5, weight: .semibold)).tracking(1)
        }
        .foregroundStyle(Color.inkSecondary)
    }

    private var text: String {
        if journey.nearestStationAsDeparture { return "FOLLOWS YOU" }
        switch journey.direction {
        case .forward: return "ALWAYS THIS WAY"
        case .reverse: return "ALWAYS REVERSED"
        case .automatic: return "REVERSES \(clock(journey.switchMinute))"
        }
    }
}

/// One departure, sized so that two and a bit of a third fit on an iPhone: enough to show that the
/// row slides without having to try it.
struct DepartureTile: View {
    let train: TrainDeparture
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(train.scheduledDeparture, format: .dateTime.hour().minute())
                    .font(.mono(20, weight: .bold))
                    .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.ink)
                    .strikethrough(train.isCancelled)
                if !train.isCancelled, let delay = train.delayMinutes, delay > 0 {
                    Text("+\(delay)").font(.mono(13, weight: .bold)).foregroundStyle(train.status.tableauInk)
                }
            }
            Text(caption)
                .font(.mono(11.5, weight: train.isCancelled ? .bold : .medium))
                .foregroundStyle(captionColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let mode = train.mode { ModeChip(mode) }
                if let duration = train.duration {
                    Text("\(Int(duration / 60)) min").font(.mono(11, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .frame(width: 112, height: 78, alignment: .topLeading)
        .padding(10)
        // The status fill is the tile's own colour: a delayed train is readable without a label.
        .background(train.status == .onTime ? Color.raised : train.status.tableauFill,
                    in: RoundedRectangle(cornerRadius: 14))
        .opacity(train.isCancelled ? 0.85 : 1)
    }

    /// The headline of the tile's second line: why it is worth looking at, or when it leaves.
    private var caption: String {
        switch train.status {
        case .cancelled: return "CANCELLED"
        case .unknown: return "Delay unknown"
        default:
            let minutes = Int(train.expectedDeparture.timeIntervalSince(now) / 60)
            return minutes < 1 ? "Leaving now" : "in \(relativeTime(train.expectedDeparture, from: now))"
        }
    }

    private var captionColor: Color {
        switch train.status {
        case .severelyDelayed, .cancelled: return .stop
        case .delayed, .unknown: return .caution
        case .onTime:
            let minutes = Int(train.expectedDeparture.timeIntervalSince(now) / 60)
            return minutes <= 5 ? .soon : .inkSecondary
        }
    }
}

/// What a journey's board turned out to be, kept next to the leg it was fetched for.
struct LoadedBoard {
    let leg: Leg
    let state: BoardState

    /// The one icon the card's title carries. Nothing worth an icon returns nil, which is the
    /// normal evening: trains, on time.
    func trouble(at now: Date) -> Trouble? {
        switch state {
        case .unavailable: return Trouble(symbol: "exclamationmark.triangle.fill", tint: .orange, label: "SNCF data unavailable")
        case .noService: return Trouble(symbol: "xmark.octagon.fill", tint: .red, label: "All trains cancelled")
        case .endOfService: return Trouble(symbol: "moon.zzz.fill", tint: .secondary, label: "End of service")
        case .noTrains: return Trouble(symbol: "questionmark.circle.fill", tint: .secondary, label: "No trains")
        case .departures(let trains):
            let upcoming = trains.filter { $0.expectedDeparture > now }
            if upcoming.contains(where: \.isCancelled) {
                return Trouble(symbol: "xmark.octagon.fill", tint: .red, label: "A train is cancelled")
            }
            if upcoming.contains(where: { $0.status == .severelyDelayed }) {
                return Trouble(symbol: "exclamationmark.triangle.fill", tint: .red, label: "A train is badly delayed")
            }
            if upcoming.contains(where: { [.delayed, .unknown].contains($0.status) }) {
                return Trouble(symbol: "exclamationmark.triangle.fill", tint: .orange, label: "A train is delayed")
            }
            return upcoming.isEmpty ? Trouble(symbol: "questionmark.circle.fill", tint: .secondary, label: "No more trains") : nil
        }
    }

    struct Trouble {
        let symbol: String
        let tint: Color
        let label: String
    }
}

/// The boards of every saved journey, fetched together so the screen has one age, not one per card.
@MainActor
@Observable
final class JourneyBoards {
    private(set) var boards: [JourneyConfiguration: LoadedBoard] = [:]
    private(set) var fetchedAt: Date?
    private(set) var loading = false

    /// On the first pass, once the delays are stale, and whenever a journey has just been added.
    func needsLoad(for journeys: [JourneyConfiguration], at now: Date) -> Bool {
        guard let fetchedAt else { return !journeys.isEmpty }
        return RefreshPlanner.isStale(fetchedAt: fetchedAt, at: now) || journeys.contains { boards[$0] == nil }
    }

    /// SwiftUI cancels the task behind `refreshable` the moment its control goes away, and a
    /// cancelled request comes back out of the client as "the SNCF API is not responding" — a
    /// pull-to-refresh looked broken while the same work from a button succeeded. An unstructured
    /// task does not inherit that cancellation, so every caller gets the same fetch.
    func load(_ journeys: [JourneyConfiguration]) async {
        await Task { await fetch(journeys) }.value
    }

    private func fetch(_ journeys: [JourneyConfiguration]) async {
        guard !loading, !journeys.isEmpty else { return }
        loading = true
        defer { loading = false }

        let now = Date.now
        var location: CLLocation?
        if journeys.contains(where: { $0.nearestStationAsDeparture }) {
            // The tab that needs a position is the one that asks for it; the settings are elsewhere now.
            if LocationFix.shared.status == .notDetermined { LocationFix.shared.requestAuthorization() }
            // One fix for the whole screen: every journey that follows you compares the same position.
            location = await LocationFix.shared.current()
        }

        // One journey at a time, each card filling in as its answer lands. A handful of rows is a
        // handful of requests and the free tier is 5 000 a day, so there is nothing to win by
        // firing them all at once.
        let client = SNCFClient(token: SharedSettings.token)
        for journey in journeys {
            let leg = JourneySelector.leg(for: journey, at: now, location: journey.nearestStationAsDeparture ? location : nil)
            do {
                let trains = try await client.departures(from: leg.from, to: leg.to, at: now)
                boards[journey] = LoadedBoard(leg: leg, state: .from(trains, now: now))
            } catch {
                boards[journey] = LoadedBoard(leg: leg, state: .unavailable(error))
            }
        }
        boards = boards.filter { journeys.contains($0.key) }
        fetchedAt = now
    }
}
#endif
