import SNCFCore
import SwiftUI
import WidgetKit

@main
struct TrainsNearMeWidgets: WidgetBundle {
    var body: some Widget {
        TripWidget()
        RadarWidget()
    }
}

/// Desktop and Home Screen everywhere, plus the Lock Screen where there is one.
let widgetFamilies: [WidgetFamily] = {
    var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    #if os(iOS)
    families += [.accessoryRectangular, .accessoryCircular]
    #endif
    // The vertical extra-tall family only exists on iOS/macOS 27; offer it there (both widgets inherit this).
    if #available(iOS 27, macOS 27, *) { families.append(.systemExtraLargePortrait) }
    return families
}()

struct TripWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind is what macOS uses to find already-placed widgets, so it keeps its old name.
        AppIntentConfiguration(kind: TripProvider.kind, intent: JourneyIntent.self, provider: TripProvider()) { entry in
            DeparturesView(entry: entry)
        }
        .configurationDisplayName("Trip")
        .description("Next direct trains between two stations.")
        .supportedFamilies(widgetFamilies)
    }
}

struct RadarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: RadarProvider.kind, intent: RadarIntent.self, provider: RadarProvider()) { entry in
            DeparturesView(entry: entry)
        }
        .configurationDisplayName("Radar")
        .description("Next departures from the station closest to you, in every direction.")
        .supportedFamilies(widgetFamilies)
    }
}

struct DeparturesView: View {
    let entry: DeparturesEntry
    @Environment(\.widgetFamily) private var family

    private var compact: Bool { family == .systemSmall }

    private var rowLimit: Int {
        // The large widget lists more and closes with a track-rule footer; the others stay at three.
        let rows = family == .systemLarge ? 7 : 3
        // The location warning takes the height of one row.
        return entry.locationIssue == nil ? rows : rows - 1
    }

    private enum Backdrop { case standard, hazard, night }

    private var backdrop: Backdrop {
        if entry.isStale { return .standard }
        switch entry.state {
        case .noService: return .hazard
        case .endOfService: return .night
        default: return .standard
        }
    }

    /// The hazard and night backdrops are fixed dark whatever the system scheme, so text on them must
    /// stay permanently light. Only the standard backdrop uses the scheme-adapting tokens.
    private var onDark: Bool { backdrop != .standard }
    private var secondaryColor: Color { onDark ? Color.white.opacity(0.7) : .inkSecondary }

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular, .accessoryRectangular:
            // iOS 17+ refuses to render a widget that doesn't adopt containerBackground — without it
            // the Lock Screen shows "Please adopt containerBackground API" instead of the board.
            AccessoryBoard(entry: entry).containerBackground(.clear, for: .widget)
        #endif
        case .systemExtraLargePortrait:
            // The vertical-track extra-tall layout (OS 27 only; the case never matches below it). Falls
            // back to the panel when there is no board to draw — ExtraTallView assumes an upcoming train.
            if entry.upcoming.isEmpty { panel } else { ExtraTallView(entry: entry) }
        default:
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            if let board = entry.board {
                header(board)
                // Faded while the new trains are on their way, so the click visibly does something.
                content.opacity(entry.isRefreshing ? 0.35 : 1)
            } else {
                message("Choose stations", detail: "Edit the widget to pick departure and arrival.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            switch backdrop {
            case .standard: Color.ground
            case .hazard: HazardBackground(variant: .widget)
            case .night: LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.28), Color(red: 0.04, green: 0.05, blue: 0.12)], startPoint: .top, endPoint: .bottom)
            }
        }
        .foregroundStyle(backdrop == .standard ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.white))
    }

    @ViewBuilder private func header(_ board: Board) -> some View {
        HStack(alignment: .top, spacing: 7) {
            switch board {
            case .trip(let leg):
                // Fixed line length: the header is a fixed height, so the glyph doesn't stretch.
                RoutePins(lineColor: secondaryColor, destination: .solid(.amber),
                          originDiameter: 7, destinationDiameter: 9, lineWidth: 1.5,
                          lineLength: compact ? 9 : 10)
                    .padding(.top, 3)
                titles(leg.from.name, leg.to.name, label: "\(leg.from.name) to \(leg.to.name)")
            case .radar(let station):
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: compact ? 13 : 15))
                    .foregroundStyle(secondaryColor)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                titles("Nearest station", station?.name ?? "Looking around…", label: "Departures from \(station?.name ?? "the nearest station")")
            }
            Spacer(minLength: 4)
            if entry.isRefreshing {
                Text(compact ? "…" : "Updating…")
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            } else if !compact || entry.isStale {
                // How old the delays are. Shown once stale even on the small widget, where there
                // is otherwise no room for it. Stale turns it amber (via the caution text colour).
                HStack(spacing: 2) {
                    if entry.isStale { Image(systemName: "clock.badge.exclamationmark") }
                    Text(entry.fetchedAt, style: .time)
                }
                .font(.mono(10, weight: .medium))
                .foregroundStyle(entry.isStale ? AnyShapeStyle(Color.caution) : AnyShapeStyle(secondaryColor))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.isStale ? "Delays last checked at" : "Updated at") \(entry.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
            RefreshButton(compact: compact, kind: entry.kind, signature: entry.signature)
        }
        .padding(.bottom, 2)
        if let issue = entry.locationIssue {
            Text(issue == .notAuthorized ? "Location not allowed: open Trains near me" : "No location: click to refresh")
                .font(.caption2)
                .foregroundStyle(onDark ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.caution))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func titles(_ top: String, _ bottom: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Station names and titles stay SF Pro — only times and numbers are monospaced.
            Text(top)
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(secondaryColor)
            Text(bottom)
                .font(.system(size: compact ? 16 : 18, weight: .bold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var content: some View {
        switch entry.state {
        case .departures:
            let upcoming = entry.upcoming.prefix(rowLimit)
            if upcoming.isEmpty {
                // Nothing left of the last fetch: only then is old data worth a warning.
                message(entry.isStale ? "Data out of date" : "No more trains",
                        detail: entry.isStale ? "Waiting for the system to refresh the widget." : "Refreshing soon.")
            } else {
                ForEach(Array(upcoming), id: \.self) { DepartureRow(train: $0, compact: compact) }
                Spacer(minLength: 0)
                // The large widget has the height to carry the attribution the others cannot.
                if family == .systemLarge { largeFooter(trains: Array(upcoming)) }
            }
        case .noTrains:
            message("No trains", detail: "No departure found for now.")
        case .endOfService(let firstTrain):
            Spacer(minLength: 0)
            EndOfService(firstTrain: firstTrain, now: entry.date, compact: compact)
            Spacer(minLength: 0)
        case .noService:
            Spacer(minLength: 0)
            // The plate stays dark and its text light: the hazard backdrop is fixed dark either scheme.
            VStack(spacing: 2) {
                Text("NO SERVICE").font(.mono(compact ? 15 : 20, weight: .heavy)).tracking(compact ? 1.5 : 2).foregroundStyle(.white)
                Text("All trains cancelled").font(.caption).foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        case .unavailable(let error):
            message("SNCF data unavailable", detail: error.localizedDescription)
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(secondaryColor).lineLimit(3)
            Spacer(minLength: 0)
        }
    }

    /// The large widget's foot: the next trains as dots on a length of track, then the attribution the
    /// smaller sizes omit.
    private func largeFooter(trains: [TrainDeparture]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TimeTrack(trains: trains)
            Text("Data © SNCF · not affiliated")
                .font(.mono(9.5))
                .foregroundStyle(secondaryColor)
        }
        .padding(.horizontal, 6)
    }
}

/// The system decides on its own when a widget reloads, and in Notification Center that can be
/// well over half an hour. This asks for one now; app-requested reloads are served immediately.
struct RefreshButton: View {
    let compact: Bool
    let kind: String
    let signature: String

    var body: some View {
        Button(intent: RefreshIntent(kind: kind, signature: signature)) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(compact ? 3 : 4)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
    }
}

#if os(iOS)
/// Lock Screen and StandBy: one line of title, then as many departures as fit.
struct AccessoryBoard: View {
    let entry: DeparturesEntry
    @Environment(\.widgetFamily) private var family

    private var title: String {
        switch entry.board {
        case .trip(let leg): leg.to.name
        case .radar(let station): station?.name ?? "Radar"
        case nil: "Trains near me"
        }
    }

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "tram.fill").font(.system(size: 9))
                    if let next = entry.upcoming.first {
                        Text(next.expectedDeparture, format: .dateTime.hour().minute())
                    } else {
                        Text("--:--")
                    }
                }
                .font(.mono(13, weight: .semibold))
            }
            .accessibilityLabel(entry.upcoming.first.map { "Next train at \($0.expectedDeparture.formatted(date: .omitted, time: .shortened))" } ?? entry.shortStatus)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).fontWeight(.semibold).lineLimit(1).widgetAccentable()
                if entry.upcoming.isEmpty {
                    Text(entry.shortStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    ForEach(Array(entry.upcoming.prefix(2)), id: \.self) { AccessoryRow(train: $0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct AccessoryRow: View {
    let train: TrainDeparture

    var body: some View {
        HStack(spacing: 4) {
            Text(train.scheduledDeparture, format: .dateTime.hour().minute())
                .font(.mono(12, weight: .semibold))
                .strikethrough(train.isCancelled)
            switch train.status {
            case .cancelled: Text("canc.").font(.caption2)
            case .unknown: Text("+?").font(.mono(11))
            case .delayed, .severelyDelayed: Text("+\(train.delayMinutes ?? 0)").font(.mono(11))
            case .onTime: EmptyView()
            }
            if let direction = train.direction {
                Text(direction).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
#endif

struct EndOfService: View {
    let firstTrain: Date
    let now: Date
    let compact: Bool

    private var day: Text {
        Calendar.current.isDate(firstTrain, inSameDayAs: now.addingTimeInterval(86400))
            ? Text("tomorrow") : Text(firstTrain, format: .dateTime.weekday(.wide))
    }

    var body: some View {
        // Always on the fixed-dark night gradient, so text stays permanently light and the first
        // train time carries the amber accent.
        HStack(spacing: 10) {
            if !compact {
                Image(systemName: "moon.zzz.fill").font(.system(size: 26)).foregroundStyle(Color.white.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("End of service").font(.system(size: compact ? 14 : 15, weight: .semibold)).foregroundStyle(.white)
                (Text("First train ") + day + Text(" at ")
                    + Text(firstTrain, format: .dateTime.hour().minute())
                        .font(.mono(compact ? 12 : 13, weight: .bold))
                        .foregroundStyle(Color.amber))
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

struct DepartureRow: View {
    let train: TrainDeparture
    let compact: Bool

    var body: some View {
        // On the small widget a delay badge leaves little room, and "25 min" used to wrap
        // onto a second line, so the middle column shrinks rather than wraps.
        HStack(spacing: compact ? 4 : 6) {
            Text(train.scheduledDeparture, format: .dateTime.hour().minute())
                .font(.mono(compact ? 14 : 15, weight: .semibold))
                .foregroundStyle(train.isCancelled ? Color.inkSecondary : .ink)
                .strikethrough(train.isCancelled)
                .fixedSize()
            // Which service runs it: the same journey can be a TER one hour and a TGV the next.
            // Only where there is room for it; the small widget needs its width for the times.
            if !compact, let mode = train.mode {
                ModeChip(mode)
            }
            if !compact || !train.isCancelled {
                // A journey knows how long it takes; a station board knows where the train goes.
                // The duration is a number (mono); the direction is a station name (SF Pro).
                if let duration = train.duration {
                    Text("\(Int(duration / 60)) min")
                        .font(.mono(compact ? 11 : 12))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else if let direction = train.direction {
                    Text(direction)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 2)
            badge
        }
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 2 : 3)
        // The row fill encodes the status (transparent when on time); the badge repeats it as text.
        .background(train.status.tableauFill, in: RoundedRectangle(cornerRadius: 6))
        .opacity(train.isCancelled ? 0.75 : 1)
    }

    @ViewBuilder private var badge: some View {
        switch train.status {
        case .onTime:
            if let delay = train.delayMinutes, delay > 0 { label("+\(delay)", .inkSecondary) }
        case .delayed, .severelyDelayed:
            label("+\(train.delayMinutes ?? 0)", train.status.tableauInk)
        case .cancelled:
            label(compact ? "CANC." : "CANCELLED", train.status.tableauInk)
        case .unknown:
            label("delay ?", train.status.tableauInk)
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.mono(compact ? 11 : 12, weight: .bold))
            .tracking(text.count > 5 ? 0.6 : 0)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}
