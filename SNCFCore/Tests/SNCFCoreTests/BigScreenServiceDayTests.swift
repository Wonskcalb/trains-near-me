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
