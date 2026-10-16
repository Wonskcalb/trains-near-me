import SNCFCore
import SwiftUI
import WidgetKit

/// Extra-tall widget — large width, twice the height (DuoWidget.dc.html). A trip header, the next time on
/// a split-flap, then the Tableau time track turned vertical with a written label beside every marker,
/// and a freshness footer. Renders from the timeline `entry`, like `DeparturesView`; `now` is `entry.date`.
///
/// The widget sits on `surface` (not `ground`): the taller panel reads as a card, as the mockup draws it.
struct ExtraTallView: View {
    let entry: DeparturesEntry

    // The flap tile and the on-time time colour flip between two non-adjacent tokens (raised↔ink,
    // amber↔ink), which no single adaptive token spans, so they are chosen from the scheme by hand.
    @Environment(\.colorScheme) private var scheme

    private var trains: [TrainDeparture] { entry.upcoming }
    /// The soonest train you can actually take: a leading cancelled row is skipped so the flap and the
    /// NEXT marker name the first one that runs.
    private var nextIndex: Int? { trains.firstIndex { !$0.isCancelled } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let flap = nextIndex.map({ trains[$0] }) ?? trains.first {
                flapRow(flap)
            }
            track
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color.surface }
        .foregroundStyle(Color.ink)
    }

    // MARK: Header — route and refresh

    @ViewBuilder private var header: some View {
        HStack(alignment: .top) {
            switch entry.board {
            case .trip(let leg):
                HStack(alignment: .top, spacing: 10) {
                    RoutePins(lineColor: .inkSecondary, destination: .solid(.amber),
                              originDiameter: 8, destinationDiameter: 11, lineWidth: 2, lineLength: 18)
                        .padding(.top, 4)
                    stationTitles(leg.from.name, leg.to.name)
                }
            case .radar(let station):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16)).foregroundStyle(Color.inkSecondary)
                        .padding(.top, 2).accessibilityHidden(true)
                    stationTitles("Nearest station", station?.name ?? "Looking around…")
                }
            case nil:
                stationTitles("Trains near me", "Choose stations")
            }
            Spacer(minLength: 8)
            RefreshButton(compact: false, kind: entry.kind, signature: entry.signature)
        }
    }

    private func stationTitles(_ top: String, _ bottom: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Station names stay SF Pro; only times and numbers are monospaced.
            Text(top).font(.system(size: 13)).foregroundStyle(Color.inkSecondary)
            Text(bottom).font(.system(size: 21, weight: .bold))
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(top), \(bottom)")
    }

    // MARK: Flap — the next time, large

    private func flapRow(_ train: TrainDeparture) -> some View {
        HStack(spacing: 14) {
            // Light flips to an ink tile with amber digits (the Phase 0 tileColor/seamColor knobs); the seam
            // is the panel colour showing through the split.
            FlapTime(date: train.expectedDeparture, digitColor: .amber, tileWidth: 34, tileHeight: 50,
                     tileColor: scheme == .dark ? .raised : .ink, seamColor: .surface, cornerRadius: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text("in \(countdown(to: train.expectedDeparture))")
                    .font(.mono(15, weight: .bold)).foregroundStyle(Color.soon)
                if let service = service(train) {
                    Text(service).font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
                if let arrival = expectedArrival(train) {
                    Text("arr. \(hhmm(arrival))").font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    // MARK: Vertical time track with a label beside each marker

    private var track: some View {
        // The window is now-anchored (17:40 → 21:00 at ~2.6 pt/min). The Canvas is decorative and
        // accessibility-hidden; the readable content is the labels, placed with the same pure layout.
        let layout = TimeTrackLayout(start: entry.date, minutesSpan: minutesSpan)
        let m = TimeTrackMetrics.vertical
        return GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .topLeading) {
                TimeTrack(trains: trains, now: entry.date, axis: .vertical,
                          minutesSpan: minutesSpan, length: height, metrics: m)
                ForEach(Array(trains.enumerated()), id: \.element) { index, train in
                    let marker = markerTime(train)
                    if marker <= layout.end {
                        markerLabel(train, isNext: index == nextIndex)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, m.acrossExtent + 8)
                            // Centre the fixed-height row on the marker the Canvas drew for this train.
                            .offset(y: along(marker, in: height, layout: layout, metrics: m) - labelHeight / 2)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private let minutesSpan = 200
    private let labelHeight: CGFloat = 40

    private func along(_ date: Date, in length: CGFloat, layout: TimeTrackLayout, metrics m: TimeTrackMetrics) -> CGFloat {
        m.startInset + CGFloat(layout.fraction(of: date)) * (length - m.startInset - m.endInset)
    }

    @ViewBuilder private func markerLabel(_ train: TrainDeparture, isNext: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hhmm(markerTime(train)))
                        .font(.mono(17, weight: .bold))
                        .foregroundStyle(timeColor(train))
                        .strikethrough(train.isCancelled)
                    if train.isCancelled, let service = service(train) {
                        Text(service).font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    } else if let arrival = expectedArrival(train) {
                        Text("→ \(hhmm(arrival))").font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    } else if let direction = train.direction {
                        Text(direction).font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                }
                // A delay slides the time; the scheduled one survives as "was 18:12 · TER 17655".
                if isDelayed(train) {
                    Text("was \(hhmm(train.scheduledDeparture))\(service(train).map { " · \($0)" } ?? "")")
                        .font(.mono(10.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 6)
            trailing(train, isNext: isNext).padding(.top, 1)
        }
        .padding(.horizontal, 10)
        .frame(height: labelHeight)
        // The soonest departure carries an amber-tinted plate, as the mockup highlights it.
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 10).fill(Color.amber.opacity(scheme == .dark ? 0.08 : 0.22))
            }
        }
    }

    @ViewBuilder private func trailing(_ train: TrainDeparture, isNext: Bool) -> some View {
        if isNext {
            Text("NEXT")
                .font(.mono(9.5, weight: .bold)).tracking(1.2)
                .foregroundStyle(onAmber)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 4))
        } else {
            switch train.status {
            case .onTime:
                // An on-time row has no trouble pill, so it shows how far off the departure is instead.
                Text(countdown(to: train.expectedDeparture))
                    .font(.mono(12, weight: .medium)).foregroundStyle(Color.inkSecondary)
            case .delayed, .severelyDelayed:
                StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
            case .cancelled:
                StatusPill("CANCELLED", status: .cancelled)
            case .unknown:
                StatusPill("delay ?", status: .unknown)
            }
        }
    }

    // MARK: Footer — last train and freshness

    private var footer: some View {
        HStack {
            // "LAST" is the last train we were handed, not the service day's final one: a service-day
            // summary (BoardState's 03:00 day) is not on the entry yet. ponytail: last known ≈ good enough.
            Text("LAST \(trains.last.map { hhmm($0.expectedDeparture) } ?? "--:--") · Data © SNCF")
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Circle().fill(entry.isStale ? Color.caution : Color.soon).frame(width: 6, height: 6)
                Text(hhmm(entry.fetchedAt))
            }
            .foregroundStyle(entry.isStale ? Color.caution : Color.inkSecondary)
        }
        .font(.mono(10.5, weight: .medium))
        .foregroundStyle(Color.inkSecondary)
    }

    // MARK: Per-train values

    /// The Canvas places a cancelled train at its scheduled slot (nothing amended it) and every other at
    /// the amended time; the labels follow so each sits on its marker.
    private func markerTime(_ train: TrainDeparture) -> Date {
        train.isCancelled ? train.scheduledDeparture : train.expectedDeparture
    }

    private func isDelayed(_ train: TrainDeparture) -> Bool {
        train.status == .delayed || train.status == .severelyDelayed
    }

    private func timeColor(_ train: TrainDeparture) -> Color {
        switch train.status {
        case .cancelled: .inkSecondary
        case .delayed, .unknown: .caution
        case .severelyDelayed: .stop
        case .onTime: scheme == .dark ? .amber : .ink   // the mockup's timeInk: amber on dark, ink on light
        }
    }

    private func expectedArrival(_ train: TrainDeparture) -> Date? {
        train.scheduledArrival.map { $0.addingTimeInterval(TimeInterval((train.delayMinutes ?? 0) * 60)) }
    }

    private func service(_ train: TrainDeparture) -> String? {
        switch (train.mode, train.trainNumber) {
        case let (mode?, number?): "\(mode) \(number)"
        case let (mode?, nil): mode
        case let (nil, number?): number
        case (nil, nil): nil
        }
    }

    /// "2 min", "1 h 32" — minutes until a departure, as the mockup writes the right-hand countdown.
    private func countdown(to date: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(entry.date) / 60).rounded(.up)))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    private func hhmm(_ date: Date) -> String { Self.hhmmFormatter.string(from: date) }

    private static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    // Dark ink on amber in either scheme: amber is always amber, so text on it is always near-black.
    // (No token spans this — ground would turn to paper on light.)
    private let onAmber = Color(red: 0.055, green: 0.059, blue: 0.067)
}

#Preview {
    // containerBackground draws nothing outside WidgetKit, so the preview paints the surface itself.
    ExtraTallView(entry: .tripPreview)
        .frame(width: 364, height: 800)
        .background(Color.surface)
}
