import Foundation

public extension BigScreenData {
    /// The live providers, wired from the shared token/session/calendar — the one swap that turns every
    /// big-screen screen from the mockup `.fake` onto real trains. Injected at the app's scene roots;
    /// `.fake` stays the environment default so previews, the screenshot build and the tests keep the
    /// mockup. Each provider resolves what it needs on its own (location via `LocationFix.shared`,
    /// favourites and the pinned station via `SharedSettings`), so there is nothing to pass but these.
    static func live(token: String? = SharedSettings.token,
                     session: URLSession = .shared,
                     calendar: Calendar = .current) -> BigScreenData {
        BigScreenData(
            journeyBoards: LiveJourneyBoards(token: token, session: session, calendar: calendar),
            stationBoard: LiveStationBoard(token: token, session: session, calendar: calendar),
            trainStops: LiveTrainStops(token: token, session: session),
            serviceDay: LiveServiceDay(token: token, session: session, calendar: calendar),
            roundTrip: RoundTripLive(token: token, session: session, calendar: calendar),
            leaveBy: LiveLeaveBy(client: SNCFClient(token: token, session: session), calendar: calendar),
            watching: TrainWatcher(),
            eta: ETAComposer())
    }
}
