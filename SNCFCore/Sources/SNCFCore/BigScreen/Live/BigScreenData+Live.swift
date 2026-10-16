import Foundation

public extension BigScreenData {
    /// The live providers — the one swap that turns every big-screen screen from the mockup `.fake` onto
    /// real trains. Build it once per process (the app keeps it as a stored property): the boards memo,
    /// the via cache and the watcher live inside, and a rebuild would throw them away. `.fake` stays the
    /// environment default so previews, the screenshot build and the tests keep the mockup. Each provider
    /// reads the token per request and resolves what else it needs on its own (location via
    /// `LocationFix.shared`, favourites and the pinned station via `SharedSettings`).
    static func live(session: URLSession = .shared, calendar: Calendar = SNCFTime.calendar) -> BigScreenData {
        BigScreenData(
            journeyBoards: LiveJourneyBoards(session: session, calendar: calendar),
            stationBoard: LiveStationBoard(session: session, calendar: calendar),
            trainStops: LiveTrainStops(session: session),
            serviceDay: LiveServiceDay(session: session, calendar: calendar),
            roundTrip: RoundTripLive(session: session, calendar: calendar),
            leaveBy: LiveLeaveBy(session: session, calendar: calendar),
            watching: TrainWatcher.shared,
            eta: ETAComposer(),
            stationSearch: LiveStationSearch(session: session))
    }
}
