import Foundation
import Testing
@testable import SNCFCore

/// Round-trip planning: the pure `RoundTripPlanner` tags and the `RoundTripLive` seam. Everything runs at
/// the big-screen anchor (Thu 15 Oct 2026, 17:40 Europe/Paris) with fixtures built in code — no live call.
@Suite struct BigScreenRoundTripPlanner {
    let now = BigScreenFixtures.now
    let calendar = BigScreenFixtures.calendar
    let voiron = BigScreenFixtures.voiron
    let grenoble = BigScreenFixtures.grenoble
    var outboundLeg: Leg { Leg(from: voiron, to: grenoble) }

    /// A way-back board: Voiron ⟶ Grenoble outbound means the returns run Grenoble ⟶ Voiron.
    private func train(_ dep: (Int, Int), _ arr: (Int, Int), _ number: String?,
                       delay: Int? = 0, cancelled: Bool = false) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: BigScreenFixtures.at(dep.0, dep.1),
                       scheduledArrival: BigScreenFixtures.at(arr.0, arr.1), mode: "TER",
                       delayMinutes: delay, isCancelled: cancelled, trainNumber: number,
                       vehicleJourneyID: number.map { "vehicle_journey:fake:\($0)" })
    }

    /// The anchor outbound board: 17:46 is the next upcoming train at 17:40, arriving 18:11.
    private var outbound: [TrainDeparture] {
        [train((17, 46), (18, 11), "17652"),
         train((18, 16), (18, 41), "17654", delay: 12),
         train((18, 46), (19, 11), "17656", cancelled: true),
         train((19, 16), (19, 41), "17658"),
         train((19, 46), (20, 11), "17660")]
    }

    /// The Duo mockup's returns: one too early, first that fits, two later, last train. Threshold with the
    /// 17:46 arrival (18:11) and a 2 h 30 stay is 20:41.
    private var returns: [TrainDeparture] {
        [train((20, 6), (20, 31), nil),
         train((20, 42), (21, 7), "17663"),
         train((21, 12), (21, 37), "17665"),
         train((21, 42), (22, 7), "17667"),
         train((22, 42), (23, 7), "17669")]
    }

    private func plan(_ outbound: [TrainDeparture], _ returns: [TrainDeparture],
                      pick: TrainIdentity? = nil, stay: TimeInterval = 150 * 60) -> RoundTripPlan {
        RoundTripPlanner.plan(outbound: outboundLeg, outboundOptions: outbound, returnOptions: returns,
                              pick: pick, stay: stay, at: now, calendar: calendar)
    }

    private func ranks(_ plan: RoundTripPlan) -> [Int] {
        plan.returnOptions.map {
            switch $0.fit { case .tooEarly: 0; case .firstThatFits: 1; case .laterBy: 2; case .lastTrain: 3 }
        }
    }

    // MARK: - Tags and ordering invariants

    @Test func eachTagInOrder() {
        let p = plan(outbound, returns)
        #expect(p.returnOptions.map(\.fit) == [.tooEarly, .firstThatFits, .laterBy(minutes: 30), .laterBy(minutes: 60), .lastTrain])
        #expect(p.returnLeg == Leg(from: grenoble, to: voiron))
    }

    @Test func fitsAreMonotonic() {
        let r = ranks(plan(outbound, returns))
        #expect(r == r.sorted())
    }

    @Test func exactlyOneFirstThatFits() {
        #expect(plan(outbound, returns).returnOptions.filter { $0.fit == .firstThatFits }.count == 1)
    }

    @Test func laterByMinutesAreNonDecreasing() {
        let later = plan(outbound, returns).returnOptions.compactMap {
            if case .laterBy(let m) = $0.fit { m } else { nil }
        }
        #expect(later == [30, 60])
        #expect(later == later.sorted())
    }

    @Test func tooEarlyOnlyBeforeTheThreshold() {
        let p = plan(outbound, returns)
        let threshold = p.selectedOutbound!.expectedArrival! + p.minimumStay   // 18:11 + 2 h 30 = 20:41
        for option in p.returnOptions where option.fit == .tooEarly {
            #expect(option.train.expectedDeparture < threshold)
        }
    }

    @Test func lastTrainIsOnTheFinalRow() {
        let options = plan(outbound, returns).returnOptions
        #expect(options.last?.fit == .lastTrain)
        #expect(options.dropLast().allSatisfy { $0.fit != .lastTrain })
    }

    @Test func pairedArrivalAndReturn() {
        let p = plan(outbound, returns)
        #expect(p.pairedArrival == BigScreenFixtures.at(18, 11))      // the 17:46's arrival
        #expect(p.pairedReturn?.trainNumber == "17663")              // 20:42, the first that fits
    }

    // MARK: - Choosing the outbound

    @Test func nilPickTakesTheNextUpcomingNonCancelled() {
        // An already-departed train and a cancelled one are both skipped; 17:46 is the next real departure.
        let board = [train((17, 30), (17, 55), "17650"),             // left before 17:40
                     train((17, 46), (18, 11), "17652")] + outbound.dropFirst()
        let p = plan(board, returns)
        #expect(p.selectedOutbound?.trainNumber == "17652")
    }

    @Test func pickByIdentitySelectsThatTrain() {
        let pick = TrainIdentity(outbound[3], calendar: calendar)!   // 19:16 → 19:41
        let p = plan(outbound, returns, pick: pick)
        #expect(p.selectedOutbound?.trainNumber == "17658")
        #expect(p.pairedArrival == BigScreenFixtures.at(19, 41))
    }

    @Test func pickFallsBackToTheDefaultWhenNotOnTheBoard() {
        let stray = TrainIdentity.vehicleJourney("vehicle_journey:fake:not-here")
        #expect(plan(outbound, returns, pick: stray).selectedOutbound?.trainNumber == "17652")
    }

    @Test func pickHonoursAnExplicitlyCancelledChoice() {
        let pick = TrainIdentity(outbound[2], calendar: calendar)!   // 18:46, cancelled
        // An explicit pick wins even when cancelled; its (nil-delay) scheduled arrival still anchors the stay.
        #expect(plan(outbound, returns, pick: pick).selectedOutbound?.trainNumber == "17656")
    }

    // MARK: - Re-plan

    @Test func cancelledFirstFitIsSkippedAndNeverFirstThatFits() {
        // 20:42 would be the first that fits, but it is cancelled: 21:12 becomes the paired return instead.
        let board = returns
        let withCancelledFit = [board[0],
                                train((20, 42), (21, 7), "17663", cancelled: true),
                                board[2], board[3], board[4]]
        let p = plan(outbound, withCancelledFit)
        #expect(p.pairedReturn?.trainNumber == "17665")             // 21:12, the next that fits
        #expect(p.returnOptions.allSatisfy { !($0.fit == .firstThatFits && $0.train.isCancelled) })
        // The cancelled would-be-first sits before the one you catch, so it reads as dimmed / TOO EARLY.
        let cancelled = p.returnOptions.first { $0.train.trainNumber == "17663" }!
        #expect(cancelled.fit == .tooEarly)
    }

    @Test func aDelayPushingAReturnPastALaterTrainReplans() {
        // 20:42 is the earliest by schedule but +40 pushes it to 21:22, behind the on-time 21:00. The first
        // one you can actually catch is 21:00, and the list comes back in that expected-departure order.
        let board = [train((20, 6), (20, 31), nil),
                     train((20, 42), (21, 22), "17663", delay: 40),
                     train((21, 0), (21, 25), "17800"),
                     train((22, 42), (23, 7), "17669")]
        let p = plan(outbound, board)
        #expect(p.pairedReturn?.trainNumber == "17800")             // 21:00, now the first that fits
        #expect(p.returnOptions.map(\.train.expectedDeparture) == p.returnOptions.map(\.train.expectedDeparture).sorted())
    }

    // MARK: - Degenerate days

    @Test func nothingRunsBack() {
        let p = plan(outbound, [])
        #expect(p.returnOptions.isEmpty)
        #expect(p.pairedReturn == nil)
        #expect(p.pairedArrival == BigScreenFixtures.at(18, 11))    // the outbound still runs
    }

    @Test func nothingRunsOut() {
        // No outbound: nothing to pair against. Returns are dimmed but the last row stays the last train back.
        let p = plan([], returns)
        #expect(p.selectedOutbound == nil)
        #expect(p.pairedArrival == nil)
        #expect(p.pairedReturn == nil)
        #expect(p.returnOptions.last?.fit == .lastTrain)
        #expect(p.returnOptions.dropLast().allSatisfy { $0.fit == .tooEarly })
    }

    @Test func lastTrainWinsWhenTheSoleFitIsAlsoTheFinalRow() {
        // A 3 h stay (threshold 21:11) leaves only 22:42 fitting, and it is the final row: LAST TRAIN wins
        // over FIRST THAT FITS there, so there is no first-that-fits and no paired return.
        let twoReturns = [train((20, 6), (20, 31), "17663"), train((22, 42), (23, 7), "17669")]
        let p = plan(outbound, twoReturns, stay: 180 * 60)
        #expect(p.returnOptions.map(\.fit) == [.tooEarly, .lastTrain])
        #expect(p.returnOptions.contains { $0.fit == .firstThatFits } == false)
        #expect(p.pairedReturn == nil)
    }

    @Test func allReturnsTooEarlyLeaveNoLastTrain() {
        // Every return leaves before the threshold (21:11): none is catchable, so there is no last train to
        // highlight — every row is TOO EARLY.
        let early = [train((19, 0), (19, 25), "17601"), train((20, 0), (20, 25), "17603")]
        let p = plan(outbound, early, stay: 180 * 60)
        #expect(p.returnOptions.allSatisfy { $0.fit == .tooEarly })
    }
}

/// The live provider's own logic — reverse leg, arrival window, re-plan — read through its fixture seam.
@Suite struct BigScreenRoundTripLive {
    let now = BigScreenFixtures.now
    let voiron = BigScreenFixtures.voiron
    let grenoble = BigScreenFixtures.grenoble

    private func train(_ dep: (Int, Int), _ arr: (Int, Int), _ number: String,
                       delay: Int? = 0, cancelled: Bool = false) -> TrainDeparture {
        TrainDeparture(scheduledDeparture: BigScreenFixtures.at(dep.0, dep.1),
                       scheduledArrival: BigScreenFixtures.at(arr.0, arr.1), mode: "TER",
                       delayMinutes: delay, isCancelled: cancelled, trainNumber: number,
                       vehicleJourneyID: "vehicle_journey:fake:\(number)")
    }

    /// Records every (leg, datetime) the provider fetches, so the test can assert the reverse leg and the
    /// arrival-anchored return window.
    actor FetchLog {
        private(set) var calls: [(leg: Leg, at: Date)] = []
        func record(_ leg: Leg, _ date: Date) { calls.append((leg, date)) }
    }

    @Test func fetchesOutboundThenTheReverseLegFromTheArrival() async {
        let outboundLeg = Leg(from: voiron, to: grenoble)
        let returnLeg = Leg(from: grenoble, to: voiron)
        let outbound = [train((17, 46), (18, 11), "17652"), train((18, 16), (18, 41), "17654")]
        let returns = [train((20, 6), (20, 31), "17663"),       // too early
                       train((20, 42), (21, 7), "17665"),       // first that fits (threshold 20:41)
                       train((22, 42), (23, 7), "17669")]       // last train
        let log = FetchLog()
        let live = RoundTripLive(calendar: BigScreenFixtures.calendar) { leg, date in
            await log.record(leg, date)
            return leg == outboundLeg ? outbound : returns
        }

        let p = await live.roundTrip(outbound: outboundLeg, pick: nil, stay: 150 * 60, at: now)

        #expect(p.returnLeg == returnLeg)
        #expect(p.selectedOutbound?.trainNumber == "17652")
        #expect(p.pairedReturn?.trainNumber == "17665")

        let calls = await log.calls
        #expect(calls.count == 2)
        #expect(calls[0].leg == outboundLeg && calls[0].at == now)
        #expect(calls[1].leg == returnLeg && calls[1].at == BigScreenFixtures.at(18, 11))   // the 17:46 arrival
    }

    @Test func emptyBoardsReadAsNothingRuns() async {
        let outboundLeg = Leg(from: voiron, to: grenoble)
        let live = RoundTripLive(calendar: BigScreenFixtures.calendar) { _, _ in [] }
        let p = await live.roundTrip(outbound: outboundLeg, pick: nil, stay: 150 * 60, at: now)
        #expect(p.selectedOutbound == nil)
        #expect(p.returnOptions.isEmpty)
        #expect(p.pairedReturn == nil)
    }
}
