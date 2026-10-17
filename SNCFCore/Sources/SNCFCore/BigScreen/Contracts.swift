import Foundation

// The frozen data contracts for the "big screen" build (iPad / Mac / Duo / Wall / menu bar / extra-tall
// widget). Every screen codes against these; the shapes reuse the existing models (`Station`, `Leg`,
// `TrainDeparture`, `BoardState`, `TripStop`, `JourneyConfiguration`) rather than inventing parallel ones.
// The protocols are `Sendable` and async because each one is a fetch in production; the Phase-0 `.fake`
// answers them from canned mockup data so screens, previews, screenshots and tests all run offline.

// MARK: - Value types

/// One saved journey resolved to a board: the configuration, the direction it currently reads as, the
/// board that direction produced, and when it was fetched. `JourneyBoardsProviding` returns these for
/// every saved journey at once (the sidebar, Lanes and Wall all list every journey).
public struct JourneyBoard: Equatable, Sendable {
    public let journey: JourneyConfiguration
    public let leg: Leg
    public let state: BoardState
    public let fetchedAt: Date
    /// The first trains of the next service day, so a late-evening screen carries on past the
    /// end-of-service split instead of going empty. Empty until `BoardState.tonightIsNearlyDone` says
    /// tonight is almost over: it costs a request of its own, paid only then.
    public let tomorrow: [TrainDeparture]

    public init(journey: JourneyConfiguration, leg: Leg, state: BoardState, fetchedAt: Date, tomorrow: [TrainDeparture] = []) {
        self.journey = journey
        self.leg = leg
        self.state = state
        self.fetchedAt = fetchedAt
        self.tomorrow = tomorrow
    }
}

/// The 03:00-to-03:00 service day in one glance: when the last train leaves tonight, when the first
/// leaves tomorrow, and the trains-per-hour histogram the Lanes minimap draws. `trainsPerHour` always
/// has 24 entries, indexed from the 03:00 service-day start (index 0 = 03:00–04:00, index 23 =
/// 02:00–03:00). Only timetable facts live here, because the summary is cached for the whole day; how
/// many trains run late is real time and is read off the live board instead.
public struct ServiceDaySummary: Equatable, Sendable {
    public let lastTonight: Date?
    public let firstTomorrow: Date?
    public let trainsPerHour: [Int]

    public init(lastTonight: Date?, firstTomorrow: Date?, trainsPerHour: [Int]) {
        self.lastTonight = lastTonight
        self.firstTomorrow = firstTomorrow
        self.trainsPerHour = trainsPerHour
    }

    public static let hourBucketCount = 24
}

/// How a return train sits against a chosen outbound arrival plus the minimum stay, for the round-trip
/// pane. Ordered by increasing departure the fit never goes backwards: `tooEarly`* then `firstThatFits`
/// then `laterBy` with non-decreasing minutes, then `lastTrain`.
public enum ReturnFit: Equatable, Sendable {
    /// Leaves before the outbound arrival plus the minimum stay — dimmed, "TOO EARLY".
    case tooEarly
    /// The soonest return you can actually make.
    case firstThatFits
    /// A later return, with how many minutes longer you would stay than `firstThatFits`.
    case laterBy(minutes: Int)
    /// The last train of the service day back.
    case lastTrain
}

public struct ReturnOption: Equatable, Sendable {
    public let train: TrainDeparture
    public let fit: ReturnFit

    public init(train: TrainDeparture, fit: ReturnFit) {
        self.train = train
        self.fit = fit
    }
}

/// An outbound journey paired with its way back: the outbound board, the picked outbound train (its
/// arrival anchors the returns), and the return options tagged by `ReturnFit`.
public struct RoundTripPlan: Equatable, Sendable {
    public let outbound: Leg
    public let returnLeg: Leg
    public let minimumStay: TimeInterval
    public let outboundOptions: [TrainDeparture]
    /// The chosen outbound; nil when nothing runs out. Its arrival is the left side of the hinge pill.
    public let selectedOutbound: TrainDeparture?
    public let returnOptions: [ReturnOption]
    /// The way back as fetched, from the earliest possible arrival on: what `replanned` re-tags when the
    /// pick or the stay changes, so neither needs a request.
    public let returnBoard: [TrainDeparture]
    /// Whether `returnBoard` runs to the 03:00 close, which is what makes its last train tonight LAST TRAIN.
    public let returnsCoverServiceDay: Bool

    public init(outbound: Leg, returnLeg: Leg, minimumStay: TimeInterval,
                outboundOptions: [TrainDeparture], selectedOutbound: TrainDeparture?,
                returnOptions: [ReturnOption], returnBoard: [TrainDeparture]? = nil,
                returnsCoverServiceDay: Bool = false) {
        self.outbound = outbound
        self.returnLeg = returnLeg
        self.minimumStay = minimumStay
        self.outboundOptions = outboundOptions
        self.selectedOutbound = selectedOutbound
        self.returnOptions = returnOptions
        self.returnBoard = returnBoard ?? returnOptions.map(\.train)
        self.returnsCoverServiceDay = returnsCoverServiceDay
    }

    /// The arrival shown on the left of the hinge pill (18:11 ··· 20:42 in the mockup).
    public var pairedArrival: Date? { selectedOutbound?.expectedArrival }

    /// The return shown on the right of the hinge pill: the first one that fits.
    public var pairedReturn: TrainDeparture? { returnOptions.first { $0.fit == .firstThatFits }?.train }
}

/// When to walk out of the door to catch a train, and the walk it is based on. `leaveAt` is the train's
/// expected departure minus the walk; the view turns it into the "LEAVE HOME IN" countdown.
public struct LeaveBy: Equatable, Sendable {
    public let train: TrainDeparture
    public let walkMinutes: Int
    public let leaveAt: Date

    public init(train: TrainDeparture, walkMinutes: Int, leaveAt: Date) {
        self.train = train
        self.walkMinutes = walkMinutes
        self.leaveAt = leaveAt
    }
}

/// A stable handle on a train across reloads, so a watch survives the delay and cancellation changes
/// that rewrite a `TrainDeparture`. The vehicle-journey id when SNCF gives one, otherwise the train
/// number pinned to its 03:00 service day (the same number recurs every day).
public enum TrainIdentity: Hashable, Codable, Sendable {
    case vehicleJourney(String)
    case numbered(String, serviceDay: Date)

    /// nil when a row carries neither a vehicle-journey id nor a train number (a bare preview row):
    /// there is then nothing stable to watch.
    public init?(_ train: TrainDeparture, calendar: Calendar = SNCFTime.calendar) {
        if let id = train.vehicleJourneyID, !id.isEmpty {
            self = .vehicleJourney(id)
        } else if let number = train.trainNumber, !number.isEmpty {
            self = .numbered(number, serviceDay: BoardState.serviceDay(of: train.scheduledDeparture, calendar: calendar))
        } else {
            return nil
        }
    }
}

public extension TrainDeparture {
    /// The amended arrival: the scheduled one pushed by the delay. nil on a station board, which has no
    /// arrival. Mirrors `expectedDeparture` for the arrival side; used by the round-trip pairing.
    var expectedArrival: Date? {
        scheduledArrival?.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60))
    }

    /// Running but late (delayed or severely delayed) — the "N DISRUPTED TONIGHT" chip counts these, and
    /// leaves cancellations to their own CANCELLED rows.
    var isRunningLate: Bool { status == .delayed || status == .severelyDelayed }
}

/// The station closest to the device, and how far it is in metres when the position is known.
public struct NearbyStation: Equatable, Sendable {
    public let station: Station
    public let distance: Double?

    public init(station: Station, distance: Double?) {
        self.station = station
        self.distance = distance
    }
}

// MARK: - Protocols

/// Every saved journey's board, fetched together (the sidebar, Lanes and Wall all need the whole set).
public protocol JourneyBoardsProviding: Sendable {
    func boards(at now: Date) async -> [JourneyBoard]
    /// One leg's board on demand, unsaved and not memoised: a journey a station-map lane opens, or the
    /// menu-bar label's one journey. The same full-service-day window as the saved boards, in one request.
    func board(for leg: Leg, at now: Date) async -> JourneyBoard
    /// The next service day's first trains on one leg, memoised per morning: Lanes' TOMORROW AM before
    /// the boards carry them on their own (`JourneyBoard.tomorrow`, filled only late in the evening).
    func morning(for leg: Leg, at now: Date) async -> [TrainDeparture]
    /// Forget any memoised boards, so the next `boards(at:)` fetches. ⌘R and a journey edit call it.
    func invalidate() async
}

public extension JourneyBoardsProviding {
    func invalidate() async {}
}

/// A station's service day for the big screen: tonight's board and, once tonight is nearly done, the
/// first trains of the next service day, the station counterpart of `JourneyBoard.tomorrow`.
public struct StationDayBoard: Equatable, Sendable {
    public let state: BoardState
    /// Empty until tonight is nearly done (`BoardState.tonightIsNearlyDone(at:)`), then the morning's
    /// first trains in timetable order, each with its terminus so they join tonight's lanes.
    public let tomorrow: [TrainDeparture]

    public init(state: BoardState, tomorrow: [TrainDeparture] = []) {
        self.state = state
        self.tomorrow = tomorrow
    }
}

/// One station's departure board, plus the short "via …" list for a row — looked up by the row's
/// `vehicleJourneyID`, since the station board itself does not carry the stopping pattern.
public protocol StationBoardProviding: Sendable {
    func board(for station: Station, at now: Date) async -> BoardState
    /// The rest of the service day (at least 2 h) with each train's terminus — the big-screen star — and
    /// late in the evening the next morning. The plain `board(for:at:)` stays a fixed count, which is what
    /// the radar and the sidebar want.
    func serviceDayBoard(for station: Station, at now: Date) async -> StationDayBoard
    func via(forVehicleJourneyID id: String) async -> [String]
}

/// The full stopping pattern of one train, wrapping `SNCFClient.trip(vehicleJourneyID:)`.
public protocol TrainStopsProviding: Sendable {
    func stops(forVehicleJourneyID id: String) async throws(TrainServiceError) -> [TripStop]
}

/// The 03:00 service-day summary for one direction (the Lanes minimap, the station-hall footer, the
/// extra-tall widget's "LAST 22:42"). nil when the day could not be summarised.
public protocol ServiceDayProviding: Sendable {
    func summary(for leg: Leg, at now: Date) async -> ServiceDaySummary?
}

/// The round-trip planner: fetch the outbound board and the way back, pick an outbound (by identity, or
/// the next one when nil), and tag the returns against the minimum stay.
public protocol RoundTripPlanning: Sendable {
    func roundTrip(outbound: Leg, pick: TrainIdentity?, stay minimumStay: TimeInterval, at now: Date) async -> RoundTripPlan
}

/// The single "pinned" station the Wall's Station board shows, and the walk behind LEAVE HOME IN. The
/// countdown itself is `LiveLeaveBy.firstCatchable(in:walk:now:)` over a board the screen already holds.
public protocol LeaveByProviding: Sendable {
    func pinnedStation() async -> Station?
    func pin(_ station: Station?) async
    /// Minutes on foot to the station: the user's own figure when set, otherwise an estimate.
    func walkMinutes(to station: Station) async -> Int
}

/// Watching a train (a reminder before it leaves, an alert if the delay or cancellation changes).
public protocol TrainWatching: Sendable {
    func isWatched(_ identity: TrainIdentity) async -> Bool
    func watch(_ identity: TrainIdentity) async
    /// Watch a train the UI holds: unlike the identity-only call this records the train's status, so the
    /// first band change is measured from now, and schedules the departure reminder. `leg` names the
    /// destination in the notification text.
    func watch(_ train: TrainDeparture, to leg: Leg?) async
    func unwatch(_ identity: TrainIdentity) async
    func watched() async -> Set<TrainIdentity>
}

/// Finding stations: the "Go to station" search and the journey editor's pickers (any SNCF station,
/// fuzzy — Navitia's `places` does the matching), and the NEAR ME station from the device's position.
public protocol StationSearching: Sendable {
    func search(_ query: String) async throws(TrainServiceError) -> [Station]
    /// `.noLocation` without a fix, `.noStationNearby` when nothing is within the search radius.
    func nearest() async throws(TrainServiceError) -> NearbyStation
}

/// Pure: the share text for a selected train on a leg (`ShareLink` in the inspector). No fetch.
public protocol ETAComposing: Sendable {
    func shareText(for train: TrainDeparture, leg: Leg) -> String
}

// MARK: - The bundle

/// One existential of each provider, handed to the screens through the SwiftUI environment. `Sendable`
/// because every protocol is; `.fake` is the Phase-0 implementation drawn straight from the mockups.
public struct BigScreenData: Sendable {
    public let journeyBoards: any JourneyBoardsProviding
    public let stationBoard: any StationBoardProviding
    public let trainStops: any TrainStopsProviding
    public let serviceDay: any ServiceDayProviding
    public let roundTrip: any RoundTripPlanning
    public let leaveBy: any LeaveByProviding
    public let watching: any TrainWatching
    public let eta: any ETAComposing
    public let stationSearch: any StationSearching

    public init(journeyBoards: any JourneyBoardsProviding,
                stationBoard: any StationBoardProviding,
                trainStops: any TrainStopsProviding,
                serviceDay: any ServiceDayProviding,
                roundTrip: any RoundTripPlanning,
                leaveBy: any LeaveByProviding,
                watching: any TrainWatching,
                eta: any ETAComposing,
                stationSearch: any StationSearching) {
        self.journeyBoards = journeyBoards
        self.stationBoard = stationBoard
        self.trainStops = trainStops
        self.serviceDay = serviceDay
        self.roundTrip = roundTrip
        self.leaveBy = leaveBy
        self.watching = watching
        self.eta = eta
        self.stationSearch = stationSearch
    }

    /// The mockup data, shared by previews, the screenshot build and the tests.
    public static let fake: BigScreenData = makeFake()
}
