import SNCFCore
import SwiftUI
import WidgetKit

@main
struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DeparturesWidget", intent: JourneyIntent.self, provider: Provider()) { entry in
            DeparturesView(entry: entry)
        }
        .configurationDisplayName("Trains near me")
        .description("Next direct trains for one journey.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DeparturesView: View {
    let entry: DeparturesEntry
    @Environment(\.widgetFamily) private var family

    private var rowLimit: Int {
        let rows = family == .systemLarge ? 8 : 3
        // The location warning takes the height of one row.
        return entry.locationIssue == nil ? rows : rows - 1
    }

    private var isStale: Bool { RefreshPlanner.isStale(fetchedAt: entry.fetchedAt, at: entry.date) }

    private enum Backdrop { case standard, hazard, night }

    private var backdrop: Backdrop {
        if isStale { return .standard }
        switch entry.state {
        case .noService: return .hazard
        case .endOfService: return .night
        default: return .standard
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
            if let leg = entry.leg {
                header(leg)
                content
            } else {
                message("Choose stations", detail: "Edit the widget to pick departure and arrival.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            switch backdrop {
            case .standard: Color(nsColor: .windowBackgroundColor)
            case .hazard: HazardStripes()
            case .night: LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.28), Color(red: 0.04, green: 0.05, blue: 0.12)], startPoint: .top, endPoint: .bottom)
            }
        }
        .foregroundStyle(backdrop == .standard ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
    }

    @ViewBuilder private func header(_ leg: Leg) -> some View {
        let compact = family == .systemSmall
        HStack(alignment: .top, spacing: 7) {
            VStack(spacing: 0) {
                Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 7, height: 7).padding(.top, 4)
                Rectangle().fill(.secondary).frame(width: 1.5, height: compact ? 9 : 10)
                Circle().fill(.primary).frame(width: 9, height: 9)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(leg.from.name)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
                Text(leg.to.name)
                    .font(.system(size: compact ? 16 : 18, weight: .bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(leg.from.name) to \(leg.to.name)")
            Spacer(minLength: 4)
            if !compact {
                Text(entry.fetchedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

    @ViewBuilder private var content: some View {
        if isStale {
            message("Data out of date", detail: "Waiting for macOS to refresh the widget.")
        } else {
            switch entry.state {
            case .departures(let trains):
                let upcoming = trains.filter { $0.expectedDeparture > entry.date }.prefix(rowLimit)
                if upcoming.isEmpty {
                    message("No more trains", detail: "Refreshing soon.")
                } else {
                    ForEach(Array(upcoming), id: \.self) { DepartureRow(train: $0, compact: family == .systemSmall) }
                    Spacer(minLength: 0)
                }
            case .noTrains:
                message("No trains", detail: "No direct train found for now.")
            case .endOfService(let firstTrain):
                Spacer(minLength: 0)
                EndOfService(firstTrain: firstTrain, now: entry.date, compact: family == .systemSmall)
                Spacer(minLength: 0)
            case .noService:
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("NO SERVICE").font(.system(size: family == .systemSmall ? 16 : 20, weight: .heavy)).tracking(1)
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
        HStack(spacing: 6) {
            Text(train.scheduledDeparture, format: .dateTime.hour().minute())
                .font(.system(size: compact ? 14 : 15, weight: .semibold).monospacedDigit())
                .strikethrough(train.isCancelled)
            if !compact || !train.isCancelled {
                Text("\(Int(train.duration / 60)) min")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            badge
        }
        .padding(.horizontal, 5)
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
        Text(text).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(color)
    }

    private var tint: Color {
        switch train.status {
        case .onTime: .clear
        case .delayed, .unknown: .orange
        case .severelyDelayed, .cancelled: .red
        }
    }
}
