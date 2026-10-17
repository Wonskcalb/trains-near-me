import Foundation
import Testing
@testable import SNCFCore

/// The big-screen fake must be internally consistent: boards sorted, delays reflected in the expected
/// times, the service-day histogram adding up, and the round-trip tags never going backwards. Everything
/// is read through the frozen provider protocols at the fixtures' anchor (Thu 15 Oct 2026, 17:40 Paris).
@Suite struct BigScreenFake {
    let data = BigScreenData.fake
    let now = BigScreenFixtures.now

    private func departures(_ state: BoardState) -> [TrainDeparture] {
        if case .departures(let trains) = state { return trains }
        return []
    }

    @Test func lateEveningBoardsCarryTomorrowsMorning() async {
        let now = BigScreenFixtures.lateNow
        let late = await BigScreenData.fakeLateEvening.journeyBoards.boards(at: now)
        #expect(late.map(\.leg) == (await data.journeyBoards.boards(at: now)).map(\.leg))   // same journeys
        for board in late {
            #expect(board.state.tonightIsNearlyDone(at: now))
            #expect(!board.tomorrow.isEmpty)
            #expect(board.tomorrow.allSatisfy { BoardState.isLaterServiceDay($0.scheduledDeparture, than: now) })
            let times = board.tomorrow.map(\.scheduledDeparture)
            #expect(times == times.sorted())
        }
        // Grenoble → Voiron: its 22:42 still to go, then the 05:42 the service-day summary names.
        #expect(departures(late[0].state).map(\.trainNumber) == ["17669"])
        #expect(departures(late[0].state).last?.scheduledDeparture == BigScreenFixtures.serviceDaySummary.lastTonight)
        #expect(late[0].tomorrow.first?.scheduledDeparture == BigScreenFixtures.serviceDaySummary.firstTomorrow)
        #expect(late[1].state == .endOfService(firstTrain: BigScreenFixtures.at(6, 17, day: 16)))
        // The 17:40 world is far from its end of service, so it carries no morning.
        #expect(await data.journeyBoards.boards(at: self.now).allSatisfy(\.tomorrow.isEmpty))
    }

    @Test func journeyBoardsMatchTheMockup() async {
        let boards = await data.journeyBoards.boards(at: now)
        #expect(boards.count == 4)
        let primary = boards[0]
        #expect(primary.leg == Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron))
        #expect(departures(primary.state).map(\.trainNumber) == ["17653", "17655", "17657", "17659", "17661", "17663"])
        #expect(boards[2].state == .noService)   // Grenoble → Chambéry
    }

    @Test func everyBoardIsSortedByDeparture() async {
        let boards = await data.journeyBoards.boards(at: now)
        for board in boards {
            let times = departures(board.state).map(\.scheduledDeparture)
            #expect(times == times.sorted())
        }
        let station = departures(await data.stationBoard.board(for: BigScreenFixtures.voiron, at: now))
        #expect(station.map(\.scheduledDeparture) == station.map(\.scheduledDeparture).sorted())
    }

    @Test func expectedDeparturesMatchTheStatedDelays() async {
        let trains = departures(await data.journeyBoards.boards(at: now)[0].state)
        let t55 = trains.first { $0.trainNumber == "17655" }!
        let t61 = trains.first { $0.trainNumber == "17661" }!
        #expect(t55.expectedDeparture == BigScreenFixtures.at(18, 24))   // +12, "leaves 18:24"
        #expect(t61.expectedDeparture == BigScreenFixtures.at(20, 6))    // +24, "leaves 20:06"
        #expect(trains.first { $0.trainNumber == "17657" }!.status == .cancelled)
    }

    @Test func stationBoardCarriesViaLists() async {
        #expect(await data.stationBoard.via(forVehicleJourneyID: "vehicle_journey:fake:17652")
                == ["Moirans", "Saint-Égrève–St-Robert"])
        #expect(await data.stationBoard.via(forVehicleJourneyID: "vehicle_journey:fake:6926").isEmpty)   // direct
    }

    @Test func stoppingPatternOf17655() async throws {
        let stops = try await data.trainStops.stops(forVehicleJourneyID: "vehicle_journey:fake:17655")
        #expect(stops.count == 8)
        #expect(stops.first?.name == "Grenoble")
        #expect(stops.first?.time == "18:12")
        #expect(stops.last?.name == "Lyon Part-Dieu")
        #expect(stops.allSatisfy { !$0.isSkipped })
    }

    @Test func serviceDayBucketsSumToTheListedTrains() async throws {
        let leg = Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron)
        let summary = try #require(await data.serviceDay.summary(for: leg, at: now))
        #expect(summary.trainsPerHour.count == ServiceDaySummary.hourBucketCount)
        #expect(summary.trainsPerHour.reduce(0, +) == 32)   // the Lanes minimap total
        #expect(summary.lastTonight == BigScreenFixtures.at(22, 42))
        #expect(summary.firstTomorrow == BigScreenFixtures.at(5, 42, day: 16))
        // The "2 DISRUPTED TONIGHT" chip is read off the live board (17655 +12, 17661 +24), not the summary.
        #expect(departures(await data.journeyBoards.boards(at: now)[0].state).filter(\.isRunningLate).count == 2)
    }

    @Test func stationSearchIgnoresCaseAndAccents() async throws {
        #expect(try await data.stationSearch.search("chambery").map(\.name) == ["Chambéry"])
        #expect(try await data.stationSearch.search("SAINT-EGREVE").map(\.name) == ["Saint-Égrève–St-Robert"])
        #expect(try await data.stationSearch.search("gre").map(\.name) == ["Grenoble", "Saint-Égrève–St-Robert"])
        #expect(try await data.stationSearch.search("g").isEmpty)   // one letter is not a search
        #expect(try await data.stationSearch.nearest().station == BigScreenFixtures.voiron)
    }

    @Test func roundTripTagsAreMonotonic() async {
        let plan = await data.roundTrip.roundTrip(
            outbound: Leg(from: BigScreenFixtures.voiron, to: BigScreenFixtures.grenoble),
            pick: nil, stay: 150 * 60, at: now)

        let departures = plan.returnOptions.map(\.train.scheduledDeparture)
        #expect(departures == departures.sorted())
        #expect(plan.returnOptions.filter { $0.fit == .firstThatFits }.count == 1)
        #expect(plan.pairedArrival == BigScreenFixtures.at(18, 11))
        #expect(plan.pairedReturn?.scheduledDeparture == BigScreenFixtures.at(20, 42))

        func rank(_ fit: ReturnFit) -> Int {
            switch fit { case .tooEarly: 0; case .firstThatFits: 1; case .laterBy: 2; case .lastTrain: 3 }
        }
        let ranks = plan.returnOptions.map { rank($0.fit) }
        #expect(ranks == ranks.sorted())
        let later = plan.returnOptions.compactMap { if case .laterBy(let minutes) = $0.fit { minutes } else { nil } }
        #expect(later == [30, 60])
    }

    @Test func leaveByIsTheDepartureMinusTheWalk() async throws {
        let walk = await data.leaveBy.walkMinutes(to: BigScreenFixtures.voiron)
        #expect(walk == 6)
        let leaveBy = try #require(LiveLeaveBy.firstCatchable(in: BigScreenFixtures.roundTripOutbound, walk: walk, now: now))
        #expect(leaveBy.train.scheduledDeparture == BigScreenFixtures.at(17, 46))
        #expect(leaveBy.leaveAt == leaveBy.train.expectedDeparture.addingTimeInterval(-Double(walk) * 60))
        #expect(await data.leaveBy.pinnedStation() == BigScreenFixtures.voiron)
    }

    @Test func watchingTogglesByIdentity() async {
        let data = BigScreenData.makeFake()   // fresh, to not share state with the other tests
        let identity = TrainIdentity(BigScreenFixtures.grenobleVoironTrains[1], calendar: BigScreenFixtures.calendar)!
        #expect(identity == .vehicleJourney("vehicle_journey:fake:17655"))
        #expect(await data.watching.isWatched(identity) == false)
        await data.watching.watch(identity)
        #expect(await data.watching.isWatched(identity))
        #expect(await data.watching.watched() == [identity])
        await data.watching.unwatch(identity)
        #expect(await data.watching.isWatched(identity) == false)
        // The train-based watch the screens call lands on the same identity.
        await data.watching.watch(BigScreenFixtures.grenobleVoironTrains[1], to: nil)
        #expect(await data.watching.isWatched(identity))
    }

    @Test func shareTextNamesTheTrainTheLegAndTheTime() {
        let text = data.eta.shareText(for: BigScreenFixtures.grenobleVoironTrains[1],
                                      leg: Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron))
        #expect(text.contains("17655"))
        #expect(text.contains("Grenoble → Voiron"))
        #expect(text.contains("18:24"))
    }
}
