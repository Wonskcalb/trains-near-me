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
    return families
}()

struct TripWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind is what macOS uses to find already-placed widgets, so it keeps its old name.
        AppIntentConfiguration(kind: "DeparturesWidget", intent: JourneyIntent.self, provider: TripProvider()) { entry in
            DeparturesView(entry: entry)
        }
        .configurationDisplayName("Trip")
        .description("Next direct trains between two stations.")
        .supportedFamilies(widgetFamilies)
    }
}

struct RadarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RadarWidget", intent: RadarIntent.self, provider: RadarProvider()) { entry in
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
        let rows = family == .systemLarge ? 8 : 3
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

    var body: some View {
        #if os(iOS)
        switch family {
        case .accessoryCircular, .accessoryRectangular: AccessoryBoard(entry: entry)
        default: panel
        }
        #else
        panel
        #endif
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            if let board = entry.board {
                header(board)
                content
            } else {
                message("Choose stations", detail: "Edit the widget to pick departure and arrival.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            switch backdrop {
            case .standard: Rectangle().fill(.background)
            case .hazard: HazardStripes()
            case .night: LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.28), Color(red: 0.04, green: 0.05, blue: 0.12)], startPoint: .top, endPoint: .bottom)
            }
        }
        .foregroundStyle(backdrop == .standard ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
    }

    @ViewBuilder private func header(_ board: Board) -> some View {
        HStack(alignment: .top, spacing: 7) {
            switch board {
            case .trip(let leg):
                JourneyPins(compact: compact)
                titles(leg.from.name, leg.to.name, label: "\(leg.from.name) to \(leg.to.name)")
            case .radar(let station):
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: compact ? 13 : 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                titles("Nearest station", station?.name ?? "Looking around…", label: "Departures from \(station?.name ?? "the nearest station")")
            }
            Spacer(minLength: 4)
            // How old the delays are. Shown once stale even on the small widget, where there
            // is otherwise no room for it.
            if !compact || entry.isStale {
                HStack(spacing: 2) {
                    if entry.isStale { Image(systemName: "clock.badge.exclamationmark") }
                    Text(entry.fetchedAt, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(entry.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.isStale ? "Delays last checked at" : "Updated at") \(entry.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
            RefreshButton(compact: compact)
        }
        .padding(.bottom, 2)
        if let issue = entry.locationIssue {
            Text(issue == .notAuthorized ? "Location not allowed: open Trains near me" : "No location: click to refresh")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func titles(_ top: String, _ bottom: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(top)
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(.secondary)
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
            }
        case .noTrains:
            message("No trains", detail: "No departure found for now.")
        case .endOfService(let firstTrain):
            Spacer(minLength: 0)
            EndOfService(firstTrain: firstTrain, now: entry.date, compact: compact)
            Spacer(minLength: 0)
        case .noService:
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text("NO SERVICE").font(.system(size: compact ? 16 : 20, weight: .heavy)).tracking(1)
                Text("All trains cancelled").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
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
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
        }
    }
}

/// The system decides on its own when a widget reloads, and in Notification Center that can be
/// well over half an hour. This asks for one now; app-requested reloads are served immediately.
struct RefreshButton: View {
    let compact: Bool

    var body: some View {
        Button(intent: RefreshIntent()) {
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

struct JourneyPins: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 7, height: 7).padding(.top, 4)
            Rectangle().fill(.secondary).frame(width: 1.5, height: compact ? 9 : 10)
            Circle().fill(.primary).frame(width: 9, height: 9)
        }
        .accessibilityHidden(true)
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
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
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
                .font(.caption.monospacedDigit())
                .strikethrough(train.isCancelled)
            switch train.status {
            case .cancelled: Text("canc.").font(.caption2)
            case .unknown: Text("+?").font(.caption2)
            case .delayed, .severelyDelayed: Text("+\(train.delayMinutes ?? 0)").font(.caption2.monospacedDigit())
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

struct HazardStripes: View {
    var body: some View {
        Canvas { context, size in
            let width: CGFloat = 14
            var x = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + width, y: size.height))
                stripe.addLine(to: CGPoint(x: x + width + size.height * 0.7, y: 0))
                stripe.addLine(to: CGPoint(x: x + size.height * 0.7, y: 0))
                context.fill(stripe, with: .color(.orange.opacity(0.22)))
                x += width * 2
            }
        }
        .background(Color.black)
    }
}

struct EndOfService: View {
    let firstTrain: Date
    let now: Date
    let compact: Bool

    private var day: Text {
        Calendar.current.isDate(firstTrain, inSameDayAs: now.addingTimeInterval(86400))
            ? Text("tomorrow") : Text(firstTrain, format: .dateTime.weekday(.wide))
    }

    var body: some View {
        HStack(spacing: 10) {
            if !compact {
                Image(systemName: "moon.zzz.fill").font(.system(size: 26)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("End of service").font(.system(size: compact ? 14 : 15, weight: .semibold))
                Text("First train \(day) at \(Text(firstTrain, format: .dateTime.hour().minute()).bold())")
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundStyle(.secondary)
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
                .font(.system(size: compact ? 14 : 15, weight: .semibold).monospacedDigit())
                .strikethrough(train.isCancelled)
                .fixedSize()
            if !compact || !train.isCancelled {
                // A journey knows how long it takes; a station board knows where the train goes.
                if let duration = train.duration {
                    Text("\(Int(duration / 60)) min")
                        .font(.system(size: compact ? 11 : 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else if let direction = train.direction {
                    Text(direction)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 2)
            badge
        }
        .padding(.horizontal, compact ? 3 : 5)
        .padding(.vertical, compact ? 1 : 2)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        .opacity(train.isCancelled ? 0.75 : 1)
    }

    @ViewBuilder private var badge: some View {
        switch train.status {
        case .onTime:
            if let delay = train.delayMinutes, delay > 0 { label("+\(delay)", .secondary) }
        case .delayed, .severelyDelayed:
            label("+\(train.delayMinutes ?? 0)", tint)
        case .cancelled:
            label(compact ? "CANC." : "CANCELLED", tint)
        case .unknown:
            label("delay ?", tint)
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: compact ? 11 : 12, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private var tint: Color {
        switch train.status {
        case .onTime: .clear
        case .delayed, .unknown: .orange
        case .severelyDelayed, .cancelled: .red
        }
    }
}
