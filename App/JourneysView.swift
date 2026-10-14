#if os(iOS)
import CoreLocation
import SNCFCore
import SwiftUI

/// Every saved journey at once: one card each, its next departures sliding sideways inside it, and
/// an icon on its title as soon as something is wrong with it. The boards refresh themselves; the
/// button is there for when you do not want to wait for that.
struct JourneysView: View {
    @State private var journeys = SharedSettings.favorites
    @State private var boards = JourneyBoards()
    @State private var now = Date.now
    @State private var adding = false

    var body: some View {
        Group {
            if journeys.isEmpty {
                ContentUnavailableView {
                    Label("No saved journey", systemImage: "star")
                } description: {
                    Text("Save one to see its next direct trains here, and to have its stations offered when you configure a Trip widget.")
                } actions: {
                    Button("Add a journey") { adding = true }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        updatedAt
                        ForEach(journeys, id: \.self) { journey in
                            JourneyCard(journey: journey, board: boards.boards[journey], now: now)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(journey) }
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Journeys")
        .toolbar {
            Button("Add a journey", systemImage: "plus") { adding = true }
        }
        .refreshable { await boards.load(journeys) }
        .sheet(isPresented: $adding) {
            EditJourneyView { journey in
                journeys.append(journey)
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

    @ViewBuilder private var updatedAt: some View {
        HStack(spacing: 5) {
            if boards.loading {
                ProgressView().controlSize(.mini)
                Text("Updating…")
            } else if let fetchedAt = boards.fetchedAt {
                let stale = RefreshPlanner.isStale(fetchedAt: fetchedAt, at: now)
                if stale { Image(systemName: "clock.badge.exclamationmark") }
                Text("\(stale ? "Delays last checked at" : "Updated at") \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func delete(_ journey: JourneyConfiguration) {
        journeys.removeAll { $0 == journey }
        SharedSettings.favorites = journeys
    }
}

/// One saved journey: where it goes, what is wrong with it, and its next departures as tiles.
struct JourneyCard: View {
    let journey: JourneyConfiguration
    let board: LoadedBoard?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                BoardView(journey: journey)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(title).font(.headline).lineLimit(1)
                            if let trouble = board?.trouble(at: now) {
                                Image(systemName: trouble.symbol)
                                    .font(.footnote)
                                    .foregroundStyle(trouble.tint)
                                    .accessibilityLabel(trouble.label)
                            }
                        }
                        Text(rule).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                // SwiftUI only hit-tests what is drawn, so the gap between the title and the
                // chevron — most of the row — was not tappable. The tiles stay out of it: they
                // are a sibling of this link, not part of its label.
                .contentShape(.rect)
                // The card's own padding, taken by the link instead, so the target reaches the
                // card's edges rather than stopping 14 points short of them.
                .padding(14)
            }
            .buttonStyle(.plain)

            tiles
                .padding([.horizontal, .bottom], 14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// The leg actually being shown once it is known: an automatic journey past its switch time, or
    /// one that follows you, does not run in the order it was saved in.
    private var title: String {
        let leg = board.map { ($0.leg.from.name, $0.leg.to.name) } ?? (journey.stationA.name, journey.stationB.name)
        return "\(leg.0) → \(leg.1)"
    }

    private var rule: String {
        // Following you means the journey has no fixed departure, so naming one would be a lie:
        // the pair with a two-way arrow says what the title alone cannot.
        if journey.nearestStationAsDeparture { return "\(journey.stationA.name) ↔ \(journey.stationB.name)" }
        switch journey.direction {
        case .forward: return "Always in this direction"
        case .reverse: return "Always the other way round"
        case .automatic: return "Reverses at \(String(format: "%02d:%02d", journey.switchMinute / 60, journey.switchMinute % 60))"
        }
    }

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
                .padding(.horizontal, -14)
                .contentMargins(.horizontal, 14, for: .scrollContent)
            }
        case .noTrains:
            note("No departure found for now.")
        case .endOfService(let firstTrain):
            note("End of service. First train at \(firstTrain.formatted(date: .omitted, time: .shortened)).")
        case .noService:
            note("Every train of the day is cancelled.")
        case .unavailable(let error):
            note(error.appDescription)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
}

/// One departure, sized so that two and a bit of a third fit on an iPhone: enough to show that the
/// row slides without having to try it.
struct DepartureTile: View {
    let train: TrainDeparture
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(train.scheduledDeparture, format: .dateTime.hour().minute())
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .strikethrough(train.isCancelled)
                if !train.isCancelled, let delay = train.delayMinutes, delay > 0 {
                    Text("+\(delay)").font(.footnote.weight(.bold).monospacedDigit()).foregroundStyle(tint)
                }
            }
            Text(caption)
                .font(.caption2.weight(train.isCancelled ? .bold : .regular))
                .foregroundStyle(train.isCancelled ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let mode = train.mode {
                    Text(mode)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
                if let duration = train.duration {
                    Text("\(Int(duration / 60)) min").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 112, height: 78, alignment: .topLeading)
        .padding(10)
        // The tint sits on the tile's own grey, so a delayed train is readable without a label.
        .background(tint.opacity(train.status == .onTime ? 0 : 0.18), in: RoundedRectangle(cornerRadius: 12))
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .opacity(train.isCancelled ? 0.8 : 1)
    }

    /// The headline of the tile's second line: why it is worth looking at, or when it leaves.
    private var caption: String {
        switch train.status {
        case .cancelled: return "CANCELLED"
        case .unknown: return "Delay unknown"
        default:
            let minutes = Int(train.expectedDeparture.timeIntervalSince(now) / 60)
            return minutes < 1 ? "Leaving now" : "in \(minutes) min"
        }
    }

    private var tint: Color {
        switch train.status {
        case .onTime: .secondary
        case .delayed, .unknown: .orange
        case .severelyDelayed, .cancelled: .red
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
