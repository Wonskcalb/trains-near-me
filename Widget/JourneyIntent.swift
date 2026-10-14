import AppIntents
import SNCFCore
import WidgetKit

struct StationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static let defaultQuery = StationQuery()

    let station: Station
    var id: String { station.entityIdentifier }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(station.name)") }
}

struct StationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        identifiers.compactMap(Station.init(entityIdentifier:)).map(StationEntity.init)
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        try await SNCFClient(token: SharedSettings.token).searchStations(string).map(StationEntity.init)
    }

    /// The stations of the journeys saved in the app, so a widget can be configured without typing
    /// — and without a request. Empty where there is no App Group to read them from.
    func suggestedEntities() async throws -> [StationEntity] {
        var seen = Set<String>()
        return SharedSettings.favorites
            .flatMap { [$0.stationA, $0.stationB] }
            .filter { seen.insert($0.id).inserted }
            .map(StationEntity.init)
    }
}

enum DirectionOption: String, AppEnum {
    case forward, reverse, automatic

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [DirectionOption: DisplayRepresentation] = [
        .forward: "Departure → Arrival",
        .reverse: "Arrival → Departure",
        .automatic: "Automatic (reverse after switch time)",
    ]

    var mode: DirectionMode { DirectionMode(rawValue: rawValue)! }
}

struct JourneyIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Journey"
    static let description = IntentDescription("Next direct trains between two stations.")

    @Parameter(title: "Departure")
    var departure: StationEntity?

    @Parameter(title: "Arrival")
    var arrival: StationEntity?

    @Parameter(title: "Direction", default: .forward)
    var direction: DirectionOption

    @Parameter(title: "Switch time", default: DateComponents(hour: 13, minute: 0), kind: .time)
    var switchTime: DateComponents?

    @Parameter(title: "Depart from nearest station", default: false)
    var nearestStation: Bool

    static var parameterSummary: some ParameterSummary {
        When(\JourneyIntent.$direction, .equalTo, .automatic) {
            Summary {
                \.$departure
                \.$arrival
                \.$direction
                \.$switchTime
                \.$nearestStation
            }
        } otherwise: {
            Summary {
                \.$departure
                \.$arrival
                \.$direction
                \.$nearestStation
            }
        }
    }

    /// Identifies this widget among several of the same kind. Built from the configured pair, not
    /// from the leg being shown, so reversing the direction keeps the same widget.
    var signature: String {
        [departure?.station.id, arrival?.station.id].compactMap { $0 }.joined(separator: "|")
    }

    var journey: JourneyConfiguration? {
        guard let a = departure?.station, let b = arrival?.station else { return nil }
        let switchMinute = (switchTime?.hour ?? 13) * 60 + (switchTime?.minute ?? 0)
        return JourneyConfiguration(stationA: a, stationB: b, direction: direction.mode, switchMinute: switchMinute, nearestStationAsDeparture: nearestStation)
    }
}

/// The radar has nothing to configure: it follows you. It stays an App Intent anyway so its
/// provider keeps WidgetKit's async API, which a StaticConfiguration does not offer.
struct RadarIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Radar"
    static let description = IntentDescription("Next departures from the station closest to you.")
}

/// The refresh button. The system decides when widgets reload on their own, and in Notification
/// Center that can be well over half an hour.
///
/// It reloads twice on purpose. A widget only ever draws what a timeline gave it, so the first
/// reload redraws the last known trains marked as updating — that is the click's feedback, since
/// WidgetKit offers none of its own — and the second one, after the flag is cleared, fetches for
/// real. Both are app-requested reloads, which the daily budget does not count.
struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh the trains"
    static let isDiscoverable = false

    /// Which widget was clicked: its kind, so only that kind reloads, and its configuration, so
    /// only that widget shows the updating state when several of the same kind sit side by side.
    @Parameter(title: "Widget kind") var kind: String
    @Parameter(title: "Widget") var signature: String

    init() {
        kind = ""
        signature = ""
    }

    init(kind: String, signature: String) {
        self.kind = kind
        self.signature = signature
    }

    func perform() async throws -> some IntentResult {
        SharedSettings.requestRefresh(kind: kind, signature: signature)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        try? await Task.sleep(for: .seconds(1))
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        return .result()
    }
}
