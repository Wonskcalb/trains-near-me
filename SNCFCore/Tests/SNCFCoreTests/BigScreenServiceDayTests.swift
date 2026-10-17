import Foundation
import Testing
@testable import SNCFCore

/// The live service-day summary: the 24-hour histogram, the delayed/severe count, and the 03:00 boundary
/// between tonight's last train and tomorrow's first — all from the pure `summarise`, plus the App-Group
/// cache that fetches a day once. Uses `BigScreenFixtures`' Europe/Paris calendar and dated `at` helper.
@Suite struct BigScreenServiceDay {
    let cal = BigScreenFixtures.calendar

    private func train(_ date: Date, delay: Int = 0, cancelled: Bool = false) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: date, scheduledArrival: date.addingTimeInterval(1800),
                       delayMinutes: delay, isCancelled: cancelled, trainNumber: nil)
    }

    private func dayStart(_ now: Date) -> Date { BoardState.serviceDay(of: now, calendar: cal) }

    @Test func bucketsSumToTheDayAndCountDelaysApartFromCancellations() {
        let now = BigScreenFixtures.at(18, 0, day: 15)
        let trains = [
            train(BigScreenFixtures.at(3, 30, day: 15)),                 // bucket 0  (03:00–04:00)
            train(BigScreenFixtures.at(18, 0, day: 15)),                 // bucket 15, on time
            train(BigScreenFixtures.at(18, 12, day: 15), delay: 12),     // bucket 15, delayed
            train(BigScreenFixtures.at(19, 0, day: 15), delay: 25),      // bucket 16, severely delayed
            train(BigScreenFixtures.at(20, 0, day: 15), cancelled: true), // bucket 17, cancelled (still a slot)
            train(BigScreenFixtures.at(1, 30, day: 16)),                 // bucket 22, still tonight (before 03:00)
            train(BigScreenFixtures.at(5, 42, day: 16)),                 // tomorrow, excluded from the histogram
        ]

        let summary = LiveServiceDay.summarise(trains, dayStart: dayStart(now), calendar: cal)!

        #expect(summary.trainsPerHour.count == ServiceDaySummary.hourBucketCount)
        #expect(summary.trainsPerHour.reduce(0, +) == 6)   // every tonight train, tomorrow's not counted
        #expect(summary.trainsPerHour[0] == 1)
        #expect(summary.trainsPerHour[15] == 2)
        #expect(summary.trainsPerHour[16] == 1)
        #expect(summary.trainsPerHour[17] == 1)
        #expect(summary.trainsPerHour[22] == 1)

        #expect(summary.lastTonight == BigScreenFixtures.at(1, 30, day: 16))
        #expect(summary.firstTomorrow == BigScreenFixtures.at(5, 42, day: 16))
    }

    @Test func aWholeDayFetchedFrom0300SummarisesEveryTrain() async throws {
        // journeys_full_day.json: Grenoble → Voiron every 30 min from 05:42 to 22:42 (35 trains), the 23:42
        // cancelled, and the next morning's 05:42 — what the 24 h window plus tomorrow's first answer.
        let trains = try NavitiaParser.departures(from: fixture("journeys_full_day"), origin: grenoble, destination: voiron)
        #expect(trains.count == 37)
        let asked = Box()
        let provider = LiveServiceDay(calendar: cal, cacheSuite: nil) { _, start in
            await asked.set(start)
            return trains
        }

        let summary = try #require(await provider.summary(for: Leg(from: grenoble, to: voiron), at: BigScreenFixtures.at(17, 40)))

        #expect(await asked.value == BigScreenFixtures.at(3, 0))   // the service day opens at 03:00, not midnight
        #expect(summary.lastTonight == BigScreenFixtures.at(22, 42))   // the cancelled 23:42 is skipped
        #expect(summary.firstTomorrow == BigScreenFixtures.at(5, 42, day: 16))
        #expect(summary.trainsPerHour.reduce(0, +) == 36)   // every slot tonight, the cancelled one included
        #expect(summary.trainsPerHour[2] == 1)              // 05:00–06:00: 05:42 only
        #expect(summary.trainsPerHour[3...19].allSatisfy { $0 == 2 })   // 06:00 → 22:59, :12 and :42
        #expect(summary.trainsPerHour[20] == 1)             // 23:42
    }

    @Test func writingADayDropsTheOlderDaysKeys() async {
        let suite = "bigscreen-serviceday-test-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let leg = Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron)
        let provider = LiveServiceDay(calendar: cal, cacheSuite: suite) { _, start in
            let date = start.addingTimeInterval(12 * 3600)
            return [TrainDeparture(scheduledDeparture: date, delayMinutes: 0, isCancelled: false, trainNumber: nil)]
        }
        _ = await provider.summary(for: leg, at: BigScreenFixtures.at(18, 0, day: 15))
        _ = await provider.summary(for: leg, at: BigScreenFixtures.at(18, 0, day: 16))
        let keys = LiveServiceDay.cachedKeys(in: suite)
        #expect(keys.count == 1)
        #expect(keys.first?.hasSuffix("@\(Int(dayStart(BigScreenFixtures.at(18, 0, day: 16)).timeIntervalSince1970))") == true)
    }

    @Test func the0300BoundarySplitsTonightFromTomorrow() {
        let now = BigScreenFixtures.at(18, 0, day: 15)
        let lastTonight = train(BigScreenFixtures.at(2, 59, day: 16))   // 02:59 → last of tonight
        let firstTomorrow = train(BigScreenFixtures.at(3, 0, day: 16))  // 03:00 → first of tomorrow

        let summary = LiveServiceDay.summarise([firstTomorrow, lastTonight], dayStart: dayStart(now), calendar: cal)!

        #expect(summary.lastTonight == BigScreenFixtures.at(2, 59, day: 16))
        #expect(summary.firstTomorrow == BigScreenFixtures.at(3, 0, day: 16))
        #expect(summary.trainsPerHour.reduce(0, +) == 1)   // only the tonight train is bucketed
        #expect(summary.trainsPerHour[23] == 1)            // 02:00–03:00
    }

    @Test func lastTonightSkipsACancelledFinalTrain() {
        let now = BigScreenFixtures.at(18, 0, day: 15)
        let trains = [
            train(BigScreenFixtures.at(22, 0, day: 15)),
            train(BigScreenFixtures.at(22, 42, day: 15), cancelled: true),   // last by clock, but cancelled
        ]
        let summary = LiveServiceDay.summarise(trains, dayStart: dayStart(now), calendar: cal)!
        #expect(summary.lastTonight == BigScreenFixtures.at(22, 0, day: 15))
    }

    @Test func emptyOrTomorrowOnlyFetchesSummariseToNil() {
        let now = BigScreenFixtures.at(18, 0, day: 15)
        #expect(LiveServiceDay.summarise([], dayStart: dayStart(now), calendar: cal) == nil)
        // All trains belong to a later service day: nothing to summarise for tonight.
        #expect(LiveServiceDay.summarise([train(BigScreenFixtures.at(10, 0, day: 16))],
                                         dayStart: dayStart(now), calendar: cal) == nil)
    }

    @Test func aDayIsFetchedOnceThenServedFromTheAppGroupCache() async {
        let suite = "bigscreen-serviceday-test-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let calls = Counter()
        let leg = Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron)
        let provider = LiveServiceDay(calendar: cal, cacheSuite: suite) { _, start in
            await calls.bump()
            let date = start.addingTimeInterval(16 * 3600)   // 16:00-ish that service day
            return [TrainDeparture(scheduledDeparture: date, scheduledArrival: date.addingTimeInterval(1800),
                                   delayMinutes: 0, isCancelled: false, trainNumber: nil)]
        }

        let day15 = BigScreenFixtures.at(18, 0, day: 15)
        let first = await provider.summary(for: leg, at: day15)
        let second = await provider.summary(for: leg, at: day15)
        #expect(first != nil)
        #expect(second == first)
        #expect(await calls.count == 1)   // the second read hit the cache

        // A different service day is a different key, so it fetches again.
        _ = await provider.summary(for: leg, at: BigScreenFixtures.at(18, 0, day: 16))
        #expect(await calls.count == 2)
    }
}

/// Counts fetch-seam calls across concurrency boundaries in a test.
private actor Counter {
    private var value = 0
    func bump() { value += 1 }
    var count: Int { value }
}

/// Records the start date the provider asked the fetch seam for.
private actor Box {
    private(set) var value: Date?
    func set(_ date: Date) { value = date }
}

/// The 03:00 boundary on the two DST mornings of 2026, Europe/Paris: 29 March skips 02:00–03:00, 25 October
/// runs 02:00–03:00 twice. Three hours of absolute time is then two or four on the clock, so the boundary
/// is read off the wall clock, and every helper must land on the same 03:00.
@Suite struct ServiceDayAcrossDST {
    let cal = SNCFTime.calendar

    private func paris(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func midnight(_ month: Int, _ day: Int) -> Date { cal.startOfDay(for: paris(month, day, 12)) }

    @Test func springForward() {
        #expect(BoardState.serviceDay(of: paris(3, 29, 1, 30), calendar: cal) == midnight(3, 28))
        #expect(BoardState.serviceDay(of: paris(3, 29, 3, 0), calendar: cal) == midnight(3, 29))
        #expect(BoardState.serviceDay(of: paris(3, 29, 3, 30), calendar: cal) == midnight(3, 29))
        #expect(BoardState.serviceDayStart(of: paris(3, 29, 10), calendar: cal) == paris(3, 29, 3))
        #expect(BoardState.nextServiceDayStart(after: paris(3, 28, 22), calendar: cal) == paris(3, 29, 3))
        // 22:00 to 03:00 that night is four hours, not five.
        #expect(BoardState.restOfServiceDay(after: paris(3, 28, 22), atLeast: 0, calendar: cal) == 4 * 3600)
    }

    @Test func fallBack() {
        // The second 02:30 (CET, an hour after the first) is still the 24th's night.
        let firstHalfPast2 = paris(10, 25, 2, 30)
        let secondHalfPast2 = firstHalfPast2.addingTimeInterval(3600)
        #expect(cal.component(.hour, from: secondHalfPast2) == 2)
        #expect(BoardState.serviceDay(of: firstHalfPast2, calendar: cal) == midnight(10, 24))
        #expect(BoardState.serviceDay(of: secondHalfPast2, calendar: cal) == midnight(10, 24))
        #expect(BoardState.serviceDay(of: paris(10, 25, 3, 15), calendar: cal) == midnight(10, 25))
        #expect(BoardState.serviceDayStart(of: paris(10, 25, 10), calendar: cal) == paris(10, 25, 3))
        #expect(BoardState.nextServiceDayStart(after: paris(10, 24, 22), calendar: cal) == paris(10, 25, 3))
        // 22:00 to 03:00 that night is six hours.
        #expect(BoardState.restOfServiceDay(after: paris(10, 24, 22), atLeast: 0, calendar: cal) == 6 * 3600)
    }

    @Test func theSummaryAgreesWithTheBoundary() {
        // A train at the second 02:30 is tonight's last; the 03:15 one is tomorrow's first.
        let late = paris(10, 25, 2, 30).addingTimeInterval(3600)
        let trains = [late, paris(10, 25, 3, 15)].map {
            TrainDeparture(scheduledDeparture: $0, delayMinutes: 0, isCancelled: false, trainNumber: nil)
        }
        let summary = LiveServiceDay.summarise(trains, dayStart: midnight(10, 24), calendar: cal)
        #expect(summary?.lastTonight == late)
        #expect(summary?.firstTomorrow == paris(10, 25, 3, 15))
        #expect(summary?.trainsPerHour[23] == 1)
    }
}
