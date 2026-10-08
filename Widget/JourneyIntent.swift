import AppIntents
import SNCFCore

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

    func suggestedEntities() async throws -> [StationEntity] { [] }
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

    var journey: JourneyConfiguration? {
        guard let a = departure?.station, let b = arrival?.station else { return nil }
        let switchMinute = (switchTime?.hour ?? 13) * 60 + (switchTime?.minute ?? 0)
        return JourneyConfiguration(stationA: a, stationB: b, direction: direction.mode, switchMinute: switchMinute, nearestStationAsDeparture: nearestStation)
    }
}
