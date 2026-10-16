import SNCFCore
import SwiftUI
import WidgetKit

// The saved-journey editor, shared by the iPhone Journeys tab, the big-screen sidebar and the Settings
// pane on every platform. Station lookups go through `data.stationSearch`, never `SNCFClient`, so the
// editor also runs on the mockup data in previews.

// `.sheet(item:)` needs Identifiable; a journey is already its own identity (Hashable).
extension JourneyConfiguration: @retroactive Identifiable {
    public var id: Self { self }
}

extension TrainServiceError {
    /// `missingToken`'s own wording tells you to open the app, which is where a reader of this
    /// screen already is; everything else reads the same here as in a widget.
    var appDescription: String {
        self == .missingToken ? "Add your SNCF API token in Settings." : localizedDescription
    }
}

/// The one write path for the saved journeys outside the iPhone tab: persist, forget the memoised
/// boards so every screen refetches, and reload the widgets — whose station picker suggests these
/// journeys. A reload is fine here: it is a user's edit, not a refresh loop on the WidgetKit budget.
@MainActor enum SavedJourneys {
    static func save(_ journeys: [JourneyConfiguration], data: BigScreenData, model: BigScreenModel?) {
        SharedSettings.favorites = journeys
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await data.journeyBoards.invalidate()
            model?.refresh()
        }
    }
}

/// Two stations and how to read them — the same choices the Trip widget offers in its own
/// settings, because a saved journey is meant to end up in one. Serves both creating a journey and
/// editing one in place: `existing` pre-fills the fields, and `save` either appends or replaces.
struct EditJourneyView: View {
    let existing: JourneyConfiguration?
    let save: (JourneyConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stationA: Station?
    @State private var stationB: Station?
    @State private var direction: DirectionMode
    @State private var switchTime: Date
    @State private var nearestStation: Bool

    init(existing: JourneyConfiguration? = nil, save: @escaping (JourneyConfiguration) -> Void) {
        self.existing = existing
        self.save = save
        _stationA = State(initialValue: existing?.stationA)
        _stationB = State(initialValue: existing?.stationB)
        _direction = State(initialValue: existing?.direction ?? .forward)
        let minute = existing?.switchMinute ?? 13 * 60
        _switchTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: minute / 60, minute: minute % 60)) ?? .now)
        _nearestStation = State(initialValue: existing?.nearestStationAsDeparture ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    stationField("Departure", selection: $stationA)
                    stationField("Arrival", selection: $stationB)
                }
                Section {
                    Picker("Direction", selection: $direction) {
                        Text("Departure → Arrival").tag(DirectionMode.forward)
                        Text("Arrival → Departure").tag(DirectionMode.reverse)
                        Text("Automatic").tag(DirectionMode.automatic)
                    }
                    if direction == .automatic {
                        DatePicker("Switch time", selection: $switchTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Depart from nearest station", isOn: $nearestStation)
                } footer: {
                    Text("Automatic shows the trains back after the switch time. Nearest station compares the two on the device and overrides the direction.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "New journey" : "Edit journey")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }.disabled(stationA == nil || stationB == nil)
                }
            }
        }
        #if os(macOS)
        // A Mac sheet sizes to its content, and a grouped Form has none to speak of until it is laid out.
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func stationField(_ title: String, selection: Binding<Station?>) -> some View {
        NavigationLink {
            StationSearch(selection: selection)
        } label: {
            LabeledContent(title) {
                Text(selection.wrappedValue?.name ?? "Choose").foregroundStyle(selection.wrappedValue == nil ? .secondary : .primary)
            }
        }
    }

    private func commit() {
        guard let stationA, let stationB else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: switchTime)
        save(JourneyConfiguration(stationA: stationA, stationB: stationB, direction: direction,
                                  switchMinute: (parts.hour ?? 13) * 60 + (parts.minute ?? 0),
                                  nearestStationAsDeparture: nearestStation))
        dismiss()
    }
}

/// Station search against the SNCF places endpoint — the same one the widget's configuration uses —
/// through `data.stationSearch`.
struct StationSearch: View {
    @Binding var selection: Station?

    @Environment(\.bigScreenData) private var data
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Station] = []
    @State private var failure: String?

    var body: some View {
        list
            .overlay {
                if let failure {
                    ContentUnavailableView("Search unavailable", systemImage: "wifi.exclamationmark", description: Text(failure))
                } else if results.isEmpty, query.count >= 2 {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Station")
            // One request per pause in the typing, not per keystroke: the free tier is 5 000 a day,
            // and `task(id:)` cancels the sleep as soon as the next character arrives.
            .task(id: query) { await search() }
    }

    @ViewBuilder private var list: some View {
        #if os(iOS)
        rows.searchable(text: $query, prompt: "Station name")
        #else
        // A pushed view inside a Mac sheet has no toolbar to host `.searchable`, so the field is inline.
        VStack(spacing: 0) {
            TextField("Station name", text: $query).textFieldStyle(.roundedBorder).padding(10)
            rows
        }
        #endif
    }

    private var rows: some View {
        List(results, id: \.id) { station in
            Button(station.name) {
                selection = station
                dismiss()
            }
            .foregroundStyle(.primary)
        }
    }

    private func search() async {
        failure = nil
        guard query.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            results = try await data.stationSearch.search(query)
        } catch {
            results = []
            failure = error.appDescription
        }
    }
}

/// The saved journeys as an editable list, in the Tableau card style: one row each with Edit / Delete /
/// reorder, and an "Add a journey" row. Lives in the Settings pane on the big screen and on the Mac.
struct SavedJourneysCard: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model: BigScreenModel?
    @State private var journeys = SharedSettings.favorites
    @State private var adding = false
    @State private var editTarget: JourneyConfiguration?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(journeys.enumerated()), id: \.element) { index, journey in
                HStack(spacing: 10) {
                    RoutePins(destination: .ring(core: .ink, ring: .amber), originDiameter: 8, destinationDiameter: 10)
                        .frame(width: 12, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(journey.stationA.name).font(.system(size: 13)).foregroundStyle(Color.inkSecondary).lineLimit(1)
                        Text(journey.stationB.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        journeyActions(journey, index: index)
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Color.inkSecondary)
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Actions for \(journey.stationA.name) to \(journey.stationB.name)")
                }
                .padding(.vertical, 8)
                .contextMenu { journeyActions(journey, index: index) }
                Divider().overlay(Color.ink.opacity(0.07))
            }
            Button { adding = true } label: {
                Label("Add a journey", systemImage: "plus").foregroundStyle(Color.ink)
            }
            .buttonStyle(.borderless)
            .padding(.top, 10)
        }
        .sheet(isPresented: $adding) {
            EditJourneyView { commit(journeys + [$0]) }
        }
        .sheet(item: $editTarget) { target in
            EditJourneyView(existing: target) { updated in
                commit(journeys.map { $0 == target ? updated : $0 })
            }
        }
        // Another screen (the sidebar) may have changed them meanwhile.
        .onAppear { journeys = SharedSettings.favorites }
        .onChange(of: model?.refreshTick) { journeys = SharedSettings.favorites }
    }

    @ViewBuilder private func journeyActions(_ journey: JourneyConfiguration, index: Int) -> some View {
        JourneyActions(journey: journey, index: index, count: journeys.count,
                       edit: { editTarget = journey }, apply: commit, journeys: journeys)
    }

    private func commit(_ updated: [JourneyConfiguration]) {
        journeys = updated
        SavedJourneys.save(updated, data: data, model: model)
    }
}

/// Edit / move / delete for one saved journey, shared by the sidebar's context menu and the Settings card.
struct JourneyActions: View {
    let journey: JourneyConfiguration
    let index: Int
    let count: Int
    let edit: () -> Void
    let apply: ([JourneyConfiguration]) -> Void
    let journeys: [JourneyConfiguration]

    var body: some View {
        Button("Edit", systemImage: "pencil", action: edit)
        if index > 0 {
            Button("Move up", systemImage: "arrow.up") { apply(moved(by: -1)) }
        }
        if index < count - 1 {
            Button("Move down", systemImage: "arrow.down") { apply(moved(by: 1)) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { apply(journeys.filter { $0 != journey }) }
    }

    private func moved(by delta: Int) -> [JourneyConfiguration] {
        var list = journeys
        guard list.indices.contains(index), list.indices.contains(index + delta) else { return list }
        list.swapAt(index, index + delta)
        return list
    }
}
