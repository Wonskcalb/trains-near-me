#if os(iOS)
import SNCFCore
import SwiftUI

/// The app proper on iPhone and iPad: the radar, the saved journeys, and the settings that used to
/// be the whole app. On macOS the widgets are still the product, so there it stays one window.
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { BoardView(journey: nil) }
                .tabItem { Label("Near me", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { JourneysView() }
                .tabItem { Label("Journeys", systemImage: "star") }
            NavigationStack { SettingsView().navigationTitle("Settings") }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Two stations and how to read them — the same choices the Trip widget offers in its own
/// settings, because a saved journey is meant to end up in one.
struct EditJourneyView: View {
    let save: (JourneyConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stationA: Station?
    @State private var stationB: Station?
    @State private var direction = DirectionMode.forward
    @State private var switchTime = Calendar.current.date(from: DateComponents(hour: 13, minute: 0)) ?? .now
    @State private var nearestStation = false

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
            .navigationTitle("New journey")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }.disabled(stationA == nil || stationB == nil)
                }
            }
        }
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

/// Station search against the SNCF places endpoint — the same one the widget's configuration uses.
struct StationSearch: View {
    @Binding var selection: Station?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Station] = []
    @State private var failure: String?

    var body: some View {
        List(results, id: \.id) { station in
            Button(station.name) {
                selection = station
                dismiss()
            }
            .foregroundStyle(.primary)
        }
        .searchable(text: $query, prompt: "Station name")
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

    private func search() async {
        failure = nil
        guard query.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            results = try await SNCFClient(token: SharedSettings.token).searchStations(query)
        } catch {
            results = []
            failure = error.appDescription
        }
    }
}
#endif
