import SNCFCore
import SwiftUI

/// One station's departure board in the detail column — what a "Go to station" pick or the NEAR ME row
/// opens — with the one action that belongs to a station rather than a journey: pinning it for Wall mode.
/// The Board (dark) palette like the station hall, so its amber times never sit on paper.
struct StationBoardView: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model
    let station: Station

    @State private var board: BoardState?
    @State private var pinned: Station?
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
            }
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 24)
        }
        .background(Color.ground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        // The board is only fetched on open, ⌘R and every five minutes: a station board is one request
        // from the free tier's 5 000, and the countdowns are recomputed from `now` in between.
        .task(id: "\(station.id)-\(model.refreshTick)") {
            while !Task.isCancelled {
                now = Date()
                board = await data.stationBoard.board(for: station, at: now)
                pinned = await data.leaveBy.pinnedStation()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEPARTURES · EVERY DIRECTION").font(.mono(11, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Color.inkSecondary)
                Text(station.name).font(.system(size: 38, weight: .bold)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                Task {
                    let target: Station? = isPinned ? nil : station
                    await data.leaveBy.pin(target)
                    pinned = target
                }
            } label: {
                Label(isPinned ? "Pinned for Wall mode" : "Pin for Wall mode", systemImage: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.raised, in: Capsule())
                    .overlay(Capsule().stroke(Color.ink.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityValue(isPinned ? "Pinned" : "Not pinned")
        }
    }

    private var isPinned: Bool { pinned?.id == station.id }

    @ViewBuilder private var content: some View {
        switch board {
        case nil:
            HStack { Spacer(); ProgressView().tint(.amber); Spacer() }.frame(height: 120)
        case .departures(let trains):
            let next = BoardReading.nextUpcoming(board, after: now)
            VStack(spacing: 0) {
                ForEach(Array(trains.enumerated()), id: \.offset) { index, train in
                    StationBoardRow(train: train, now: now, isNext: train == next)
                    if index < trains.count - 1 { Divider().overlay(Color.ink.opacity(0.07)) }
                }
            }
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.ink.opacity(0.05), lineWidth: 1))
        case .endOfService(let first):
            note("End of service", "First train at \(HallFormat.hm(first)).")
        case .noService:
            note("No service", "Every remaining train is cancelled.")
        case .noTrains:
            note("No departures", "Nothing leaves this station right now.")
        case .unavailable(let error):
            note("Board unavailable", error.appDescription)
        }
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Color.ink)
            Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct StationBoardRow: View {
    let train: TrainDeparture
    let now: Date
    let isNext: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(HallFormat.hm(train.scheduledDeparture))
                .font(.mono(22, weight: .bold))
                .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.amber)
                .strikethrough(train.isCancelled)
            VStack(alignment: .leading, spacing: 3) {
                Text(train.direction ?? "—").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(1)
                HStack(spacing: 7) {
                    if let mode = train.mode { ModeChip(mode) }
                    if let number = train.trainNumber { Text("N° \(number)").font(.mono(12.5)).foregroundStyle(Color.inkSecondary) }
                }
            }
            .opacity(train.isCancelled ? 0.6 : 1)
            Spacer(minLength: 8)
            status
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(isNext ? Color.amber.opacity(0.07) : .clear)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch train.status {
        case .onTime:
            Text(HallFormat.relative(train.expectedDeparture, from: now))
                .font(.mono(13, weight: isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? Color.soon : Color.inkSecondary)
        case .delayed, .severelyDelayed:
            VStack(alignment: .trailing, spacing: 3) {
                StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
                Text("leaves \(HallFormat.hm(train.expectedDeparture))").font(.mono(11.5)).foregroundStyle(train.status.tableauInk)
            }
        case .cancelled:
            StatusPill("CANCELLED", status: .cancelled)
        case .unknown:
            StatusPill("delay ?", status: .unknown)
        }
    }
}

#Preview("Station board") {
    StationBoardView(station: BigScreenFixtures.voiron)
        .environment(BigScreenModel())
        .frame(width: 1000, height: 800)
}
