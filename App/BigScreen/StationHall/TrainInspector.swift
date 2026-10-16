import SNCFCore
import SwiftUI

/// The right-hand column of Main.dc.html: one selected train. Its number and headsign, three stat tiles,
/// and the stopping pattern with your leg drawn solid and the rest of the run dashed and dimmed. All of
/// it from already-fetched values — the stops are loaded by `StationHallView` and handed in.
struct TrainInspector: View {
    @Environment(\.bigScreenData) private var data
    let train: TrainDeparture
    let leg: Leg
    let stops: [TripStop]
    let now: Date
    var onClose: () -> Void

    @State private var watched = false

    private var delay: Int { train.delayMinutes ?? 0 }
    private var identity: TrainIdentity? { TrainIdentity(train, calendar: BigScreenFixtures.calendar) }
    /// The train's final destination, from the run; falls back to the headsign or the leg's end.
    private var headsign: String { stops.last?.name ?? train.direction ?? leg.to.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock
                    statTiles
                    TrackRule(label: "STOPS")
                    if stops.isEmpty {
                        Text("Full stops unavailable for this train.")
                            .font(.mono(12)).foregroundStyle(Color.inkSecondary).padding(.vertical, 8)
                    } else {
                        pattern
                    }
                }
            }
            actions
        }
        .padding(.horizontal, 22).padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ground)
        .task(id: identity) { if let identity { watched = await data.watching.isWatched(identity) } }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRAIN").font(.mono(11, weight: .semibold)).tracking(1.4).foregroundStyle(Color.inkSecondary)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.ink.opacity(0.7))
                        .frame(width: 32, height: 32).background(Color.raised, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close inspector")
            }
            HStack(spacing: 10) {
                Text(train.trainNumber.map { "N° \($0)" } ?? "Train").font(.mono(28, weight: .bold)).foregroundStyle(Color.ink)
                if let mode = train.mode { ModeChip(mode) }
            }
            Text("to \(headsign)").font(.system(size: 15)).foregroundStyle(Color.ink.opacity(0.7))
        }
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        HStack(spacing: 8) {
            tile("LEAVES", value: train.isCancelled ? "—" : HallFormat.hm(train.expectedDeparture), tint: valueTint)
            tile("YOU ARRIVE", value: train.isCancelled ? "—" : (train.expectedArrival.map(HallFormat.hm) ?? "—"), tint: valueTint)
            delayTile
        }
    }

    private var valueTint: Color { train.status == .onTime ? .ink : train.status.tableauInk }

    private func tile(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.mono(10, weight: .semibold)).tracking(1.2).foregroundStyle(Color.inkSecondary)
            Text(value).font(.mono(18, weight: .bold)).foregroundStyle(tint)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var delayTile: some View {
        let issue = train.status != .onTime
        return VStack(alignment: .leading, spacing: 3) {
            Text("DELAY").font(.mono(10, weight: .semibold)).tracking(1.2).foregroundStyle(issue ? train.status.tableauInk : Color.inkSecondary)
            Text(train.isCancelled ? "CANC." : (delay > 0 ? "+\(delay)" : "On time"))
                .font(.mono(18, weight: .bold)).foregroundStyle(issue ? train.status.tableauInk : Color.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(issue ? train.status.tableauFill : Color.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Stopping pattern

    /// Your leg (board → alight) is solid in ink; the rest of the run is dashed and at half strength.
    private var pattern: some View {
        let boardIdx = stops.firstIndex { $0.name == leg.from.name } ?? 0
        let alightIdx = stops.lastIndex { $0.name == leg.to.name } ?? (stops.count - 1)
        let onBoardMinutes = Int((train.duration ?? 0) / 60)
        return VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                StopRow(stop: stop, delay: delay, status: train.status,
                        role: role(index, board: boardIdx, alight: alightIdx),
                        aboveSolid: index > 0 ? segmentSolid(index - 1, board: boardIdx, alight: alightIdx) : nil,
                        belowSolid: index < stops.count - 1 ? segmentSolid(index, board: boardIdx, alight: alightIdx) : nil,
                        onBoardMinutes: onBoardMinutes)
            }
        }
    }

    private func role(_ index: Int, board: Int, alight: Int) -> StopRow.Role {
        if index == board { return .board }
        if index == alight { return .alight }
        if index > board && index < alight { return .onLeg }
        return .offLeg
    }

    /// The segment leaving stop `i` is solid when it stays inside the leg.
    private func segmentSolid(_ i: Int, board: Int, alight: Int) -> Bool { i >= board && i < alight }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    guard let identity else { return }
                    Task {
                        if watched { await data.watching.unwatch(identity) } else { await data.watching.watch(identity) }
                        watched = await data.watching.isWatched(identity)
                    }
                } label: {
                    actionLabel(watched ? "bell.fill" : "bell", watched ? "Watching" : "Watch train")
                }
                .buttonStyle(.plain).disabled(identity == nil)

                ShareLink(item: data.eta.shareText(for: train, leg: leg)) {
                    actionLabel("square.and.arrow.up", "Share ETA")
                }
                .buttonStyle(.plain)
            }
            Link(destination: URL(string: "https://www.sncf-connect.com")!) {
                HStack(spacing: 8) {
                    Text("Tickets & details in SNCF Connect").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.amber)
                }
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Color.raised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ink.opacity(0.08), lineWidth: 1))
            }
            Text("Not affiliated with SNCF. Train data © SNCF, via the SNCF open data API.")
                .font(.system(size: 11)).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func actionLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.amber)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity).frame(height: 46)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ink.opacity(0.08), lineWidth: 1))
    }
}

/// One stop in the inspector pattern: the time (amended, with the timetabled one struck under an
/// endpoint), the rail with its dot, and the name with a "YOU BOARD" / "YOU GET OFF" caption.
private struct StopRow: View {
    enum Role { case offLeg, board, onLeg, alight }

    let stop: TripStop
    let delay: Int
    let status: DepartureStatus
    let role: Role
    /// nil = no line above (first stop) / below (last stop); true = solid on-leg; false = dashed off-leg.
    let aboveSolid: Bool?
    let belowSolid: Bool?
    let onBoardMinutes: Int

    private var onLeg: Bool { role != .offLeg }
    private var amended: String { HallFormat.amend(stop.time, byMinutes: delay) }
    private var timeTint: Color { onLeg ? (delay > 0 ? status.tableauInk : .ink) : .inkSecondary }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timeColumn.frame(width: 54, alignment: .leading)
            RailCell(aboveSolid: aboveSolid, belowSolid: belowSolid, role: role).frame(width: 22)
            nameColumn
            Spacer(minLength: 0)
        }
        .frame(minHeight: role == .board || role == .alight ? 48 : (onLeg ? 38 : 32), alignment: .top)
        .opacity(onLeg ? 1 : 0.5)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(amended).font(.mono(role == .board || role == .alight ? 14 : 13, weight: role == .board || role == .alight ? .bold : .medium))
                .foregroundStyle(timeTint)
            if (role == .board || role == .alight), delay > 0 {
                Text(stop.time).font(.mono(11, weight: .medium)).foregroundStyle(Color.inkSecondary.opacity(0.7)).strikethrough()
            }
        }
        .padding(.top, 1)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stop.name).font(.system(size: role == .board || role == .alight ? 15 : 14, weight: role == .board || role == .alight ? .bold : .regular))
                .foregroundStyle(role == .offLeg ? Color.ink.opacity(0.85) : Color.ink)
                .strikethrough(stop.isSkipped)
            switch role {
            case .board:
                caption("YOU BOARD", Color.inkSecondary)
            case .alight:
                caption("YOU GET OFF · \(onBoardMinutes) MIN", Color.amber)
            default:
                EmptyView()
            }
        }
    }

    private func caption(_ text: String, _ color: Color) -> some View {
        Text(text).font(.mono(10, weight: .semibold)).tracking(1.2).foregroundStyle(color)
    }
}

/// The rail segment for one stop: a vertical line (solid in ink on the leg, dashed and dim off it) with
/// the stop's dot centred on it.
private struct RailCell: View {
    let aboveSolid: Bool?
    let belowSolid: Bool?
    let role: StopRow.Role

    var body: some View {
        Canvas { context, size in
            let x = size.width / 2
            let midY = dotCentreY(height: size.height)
            drawSegment(context, x: x, from: 0, to: midY, solid: aboveSolid)
            drawSegment(context, x: x, from: midY, to: size.height, solid: belowSolid)
            drawDot(context, at: CGPoint(x: x, y: midY))
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func dotCentreY(height: CGFloat) -> CGFloat {
        // The endpoints sit a touch below the top so the "YOU BOARD/OFF" row reads as the leg's end.
        role == .board || role == .alight ? 10 : 8
    }

    private func drawSegment(_ context: GraphicsContext, x: CGFloat, from: CGFloat, to: CGFloat, solid: Bool?) {
        guard let solid else { return }
        var path = Path()
        path.move(to: CGPoint(x: x, y: from))
        path.addLine(to: CGPoint(x: x, y: to))
        if solid {
            context.stroke(path, with: .color(.ink), style: StrokeStyle(lineWidth: 3))
        } else {
            context.stroke(path, with: .color(.inkSecondary.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
        }
    }

    private func drawDot(_ context: GraphicsContext, at centre: CGPoint) {
        func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)) }
        switch role {
        case .board:
            context.fill(circle(6.5), with: .color(.ground))
            context.stroke(circle(6.5), with: .color(.ink), lineWidth: 3)
        case .alight:
            context.fill(circle(8), with: .color(.amber))
        case .onLeg:
            context.fill(circle(4.5), with: .color(.ground))
            context.stroke(circle(4.5), with: .color(.ink), lineWidth: 2)
        case .offLeg:
            context.fill(circle(3.5), with: .color(.inkSecondary))
        }
    }
}

#Preview("Inspector — 17655") {
    TrainInspector(
        train: BigScreenFixtures.grenobleVoironTrains[1],
        leg: Leg(from: BigScreenFixtures.grenoble, to: BigScreenFixtures.voiron),
        stops: BigScreenFixtures.stops17655,
        now: BigScreenFixtures.now,
        onClose: {})
    .environment(\.bigScreenData, .fake)
    .frame(width: 360, height: 1000)
    .preferredColorScheme(.dark)
}
