import Foundation
import Testing
@testable import SNCFCore

/// `ETAComposer` is pure, so the whole surface is exact-string assertions against the fixtures' anchor
/// (Thu 15 Oct 2026, Europe/Paris). The first test pins the exact example from the design handoff.
@Suite struct BigScreenETA {
    let eta = ETAComposer()
    let grenobleVoiron = Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron)

    @Test func exactExampleForADelayedJourneyTrain() {
        // 17655: TER, 18:12 → 18:36 base, +12, so arrives 18:48.
        let text = eta.shareText(for: BigScreenFixtures.grenobleVoironTrains[1], leg: grenobleVoiron)
        #expect(text == "On the 18:12 (TER 17655), arriving Voiron 18:48, running 12 min late")
    }

    @Test func onTime() {
        // 17653: TER, 17:42 → 18:07, no delay.
        let text = eta.shareText(for: BigScreenFixtures.grenobleVoironTrains[0], leg: grenobleVoiron)
        #expect(text == "On the 17:42 (TER 17653), arriving Voiron 18:07, on time")
    }

    @Test func cancelled() {
        // 17657: TER, 18:42, cancelled — a sentence of its own, no invented arrival.
        let text = eta.shareText(for: BigScreenFixtures.grenobleVoironTrains[2], leg: grenobleVoiron)
        #expect(text == "The 18:42 (TER 17657) to Voiron is cancelled")
    }

    @Test func missingArrivalFromAStationBoard() {
        // A station-board row has no scheduledArrival: name the destination instead of a time.
        let row = TrainDeparture(scheduledDeparture: BigScreenFixtures.at(17, 46), scheduledArrival: nil,
                                 direction: "Grenoble", mode: "TER", delayMinutes: 0, isCancelled: false,
                                 trainNumber: "17652", vehicleJourneyID: "vehicle_journey:fake:17652")
        let text = eta.shareText(for: row, leg: Leg(from: BigScreenFixtures.voiron, to: BigScreenFixtures.grenoble))
        #expect(text == "On the 17:46 (TER 17652), to Grenoble, on time")
    }
}

/// Every train time is Paris wall-clock whatever zone the process runs in, so the helpers are checked
/// against an instant whose New York and UTC readings differ from the Paris one.
@Suite struct SNCFTimeFormatting {
    let departure = BigScreenFixtures.at(17, 42)   // 15:42 UTC, 11:42 in New York

    @Test func hhmmIsParisAnd24Hour() {
        #expect(SNCFTime.hhmm(departure) == "17:42")
        #expect(SNCFTime.hhmmFormatter.timeZone == TimeZone(identifier: "Europe/Paris"))
    }

    @Test func theLocaleStylesCarryParis() {
        var style = SNCFTime.hourMinute
        style.locale = Locale(identifier: "fr_FR")
        #expect(departure.formatted(style) == "17:42")
        #expect(SNCFTime.shortTime.timeZone == TimeZone(identifier: "Europe/Paris"))
    }

    @Test func durationWords() {
        #expect(SNCFTime.duration(minutes: 0) == "0 min")
        #expect(SNCFTime.duration(minutes: 59) == "59 min")
        #expect(SNCFTime.duration(minutes: 65) == "1 h 05")
    }
}
