import SNCFCore
import SwiftUI

/// Round trip — the outbound board and the way back side by side, with the stay stepper and the
/// paper pairing pill across the hinge (Design/BigScreen/Duo.dc.html). Two panes whenever the window
/// is wide enough for two compact columns (iPad, iPad split view, Mac); otherwise the way back is a
/// pushed second screen. There is no iPhone "Duo" today, so compact iPhone never reaches here.
///
/// The screen is the Board (dark) look whatever the app appearance, like Main and Wall: it forces the
/// dark token variants locally rather than flipping the whole window, so the sidebar and the light
/// Lanes screen keep their own scheme.
struct RoundTripView: View {
    @Environment(\.bigScreenData) private var data
    @Environment(BigScreenModel.self) private var model

    /// "now" is fixed so the fake world (Thu 15 Oct 2026 17:40) reads the same in previews and the
    /// screenshot build; the running app passes the live clock.
    private let now: Date
    @State private var plan: RoundTripPlan?
    /// The outbound the user ringed, by stable identity so the pick survives a reload; nil means "the
    /// next one", which the planner resolves. The fake planner ignores it (one canned scenario), so the
    /// ring stays on the first outbound until the live provider honours the pick.
    @State private var pick: TrainIdentity?
    /// Minimum stay at the destination; the stepper nudges it ±15 min and the planner re-tags the returns.
    /// Starts at 2 h 30, the mockup's value and the fake plan's `minimumStay`.
    @State private var stay: TimeInterval = 150 * 60
    @State private var watchedBoth = false
    @State private var showReturn = false

    init(now: Date = Date()) { self.now = now }

    /// Below this the two columns would be too cramped, so the way back becomes a pushed screen.
    private let minTwoPaneWidth: CGFloat = 680
    private let cal = SNCFTime.calendar

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= minTwoPaneWidth {
                    twoPane
                } else {
                    narrow
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.ground.ignoresSafeArea())
        }
        .environment(\.colorScheme, .dark)
        // One reload covers the first appearance, ⌘R, a new minimum stay and a re-picked outbound.
        .task(id: ReloadKey(tick: model.refreshTick, stayMinutes: Int(stay / 60), pick: pick)) {
            await load()
        }
    }

    private struct ReloadKey: Hashable { let tick: Int; let stayMinutes: Int; let pick: TrainIdentity? }

    private func load() async {
        watchedBoth = false
        let boards = await data.journeyBoards.boards(at: now)
        guard let primary = boards.first?.journey else { plan = nil; return }
        // The outbound is the primary journey's B → A: you leave home (the saved destination) and come
        // back to it. Read from the saved stations, not the leg the board resolved at `now` — an automatic
        // journey flips at its switch time, and the round trip must not flip with it. The planner returns
        // the authoritative legs, so the panes read `plan.outbound` / `plan.returnLeg`.
        let outbound = Leg(from: primary.stationB, to: primary.stationA)
        plan = await data.roundTrip.roundTrip(outbound: outbound, pick: pick, stay: stay, at: now)
    }

    // MARK: Layouts

    private var twoPane: some View {
        HStack(spacing: 16) {
            pane { outboundPane }
            pane { returnPane }
        }
        .padding(16)
        // The pairing pill straddles the fold; its exact drop is cosmetic, so it is anchored by hand just
        // under the two route headers rather than pinned to a device coordinate.
        .overlay(alignment: .top) { hingePill.padding(.top, 92) }
    }

    private var narrow: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    outboundPane
                    hingePill
                    Button { showReturn = true } label: {
                        HStack { Text("Way back"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.onAmber)
                            .padding(.horizontal, 18).frame(height: 52)
                            .background(Color.amber, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Color.ground.ignoresSafeArea())
            .navigationDestination(isPresented: $showReturn) {
                ScrollView { returnPane.padding(16) }
                    .background(Color.ground.ignoresSafeArea())
                    .navigationTitle("Way back")
            }
        }
    }

    /// One scrolling column; a ScrollView keeps a short Mac window from clipping the rows.
    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { content().padding(.horizontal, 20).padding(.vertical, 24) }
            .frame(maxWidth: .infinity)
    }

    // MARK: Outbound pane

    @ViewBuilder private var outboundPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("① OUTBOUND")
                Spacer()
                // No multi-day in scope; the pill is decorative, so it carries no action.
                Text("Today")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color.raised.opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(Color.ink.opacity(0.10), lineWidth: 1))
            }

            if let plan {
                routeHeader(plan.outbound)
                card {
                    ForEach(Array(plan.outboundOptions.enumerated()), id: \.offset) { index, train in
                        if index > 0 { rowDivider }
                        outboundRow(train, selectedID: selectedOutboundID)
                    }
                }
                wholeDayOut(plan)
            } else {
                loading
            }
        }
    }

    private var selectedOutboundID: TrainIdentity? {
        plan?.selectedOutbound.flatMap { TrainIdentity($0, calendar: cal) }
    }

    private func outboundRow(_ train: TrainDeparture, selectedID: TrainIdentity?) -> some View {
        let id = TrainIdentity(train, calendar: cal)
        let picked = id != nil && id == selectedID
        return Button { if !train.isCancelled, let id { pick = id } } label: {
            outboundRowContent(train, picked: picked)
        }
        .buttonStyle(.plain)
        .disabled(train.isCancelled || id == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func outboundRowContent(_ train: TrainDeparture, picked: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                timeLine(train)
                if let subtitle = subtitle(train) {
                    Text(subtitle).font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
            .opacity(train.isCancelled ? 0.55 : 1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if picked { checkBadge }
                outboundTrailing(train, picked: picked)
            }
        }
        .modifier(RowHighlight(selected: picked))
        .contentShape(Rectangle())
    }

    @ViewBuilder private func outboundTrailing(_ train: TrainDeparture, picked: Bool) -> some View {
        switch train.status {
        case .onTime:
            // The picked / next train gets the green "in 6 min"; the rest show plain time-from-now.
            Text(picked ? "in \(relative(train.expectedDeparture))" : relative(train.expectedDeparture))
                .font(.mono(picked ? 12.5 : 13, weight: picked ? .semibold : .regular))
                .foregroundStyle(picked ? Color.soon : Color.inkSecondary)
                .fixedSize()
        case .delayed, .severelyDelayed:
            StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
            Text("leaves \(hhmm(train.expectedDeparture))")
                .font(.mono(11)).foregroundStyle(train.status.tableauInk)
        case .cancelled:
            StatusPill("CANCELLED", status: .cancelled)
        case .unknown:
            StatusPill("delay ?", status: .unknown)
        }
    }

    /// The day as one bar: the outbound leg (amber) · the stay at the destination · the way back (amber).
    @ViewBuilder private func wholeDayOut(_ plan: RoundTripPlan) -> some View {
        if let out = plan.selectedOutbound, let back = plan.pairedReturn,
           let arrival = out.expectedArrival, let backArrival = back.expectedArrival {
            let total = max(1, backArrival.timeIntervalSince(out.scheduledDeparture))
            let outFraction = (out.duration ?? 0) / total
            let backFraction = (back.duration ?? 0) / total
            let stayMinutes = Int(back.scheduledDeparture.timeIntervalSince(arrival) / 60)
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("THE WHOLE DAY OUT", color: .inkSecondary)
                VStack(spacing: 5) {
                    HStack {
                        Text(hhmm(out.scheduledDeparture)).foregroundStyle(Color.inkSecondary)
                        Spacer()
                        Text("\(durationWords(stayMinutes)) IN \(plan.outbound.to.name.uppercased())")
                            .foregroundStyle(Color.ink.opacity(0.85))
                        Spacer()
                        Text(hhmm(backArrival)).foregroundStyle(Color.inkSecondary)
                    }
                    .font(.mono(10, weight: .semibold))
                    GeometryReader { geo in
                        let width = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.raised)
                            Capsule().fill(Color.amber).frame(width: width * outFraction)
                            Capsule().fill(Color.amber).frame(width: width * backFraction)
                                .offset(x: width * (1 - backFraction))
                        }
                    }
                    .frame(height: 10)
                    HStack {
                        Text(legWords(out)).foregroundStyle(Color.inkSecondary)
                        Spacer()
                        Text(legWords(back)).foregroundStyle(Color.inkSecondary)
                    }
                    .font(.mono(10))
                }
            }
            .padding(14)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ink.opacity(0.06), lineWidth: 1))
        }
    }

    // MARK: Way-back pane

    @ViewBuilder private var returnPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("② WAY BACK")
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                        .frame(width: 36, height: 36)
                        .background(Color.raised.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(Color.ink.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share both trains")
            }

            if let plan {
                routeHeader(plan.returnLeg)
                stayStepper
                card {
                    ForEach(Array(plan.returnOptions.enumerated()), id: \.offset) { index, option in
                        if index > 0 { rowDivider }
                        returnRow(option)
                    }
                }
                watchBoth(plan)
            } else {
                loading
            }
        }
    }

    private func returnRow(_ option: ReturnOption) -> some View {
        let dimmed = option.fit == .tooEarly
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                timeLine(option.train)
                if let subtitle = subtitle(option.train) {
                    Text(subtitle).font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
            .opacity(option.train.isCancelled ? 0.55 : 1)
            Spacer(minLength: 4)
            // A return can be late or cancelled too; say so beside its fit, as the outbound rows do.
            VStack(alignment: .trailing, spacing: 4) {
                returnTag(option.fit)
                returnStatus(option.train)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
        .modifier(RowHighlight(selected: option.fit == .firstThatFits))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func returnStatus(_ train: TrainDeparture) -> some View {
        switch train.status {
        case .onTime: EmptyView()
        case .delayed, .severelyDelayed:
            StatusPill("+\(train.delayMinutes ?? 0)", status: train.status)
            Text("leaves \(hhmm(train.expectedDeparture))").font(.mono(11)).foregroundStyle(train.status.tableauInk)
        case .cancelled: StatusPill("CANCELLED", status: .cancelled)
        case .unknown: StatusPill("delay ?", status: .unknown)
        }
    }

    @ViewBuilder private func returnTag(_ fit: ReturnFit) -> some View {
        switch fit {
        case .tooEarly:
            Text("TOO EARLY").font(.mono(10.5, weight: .semibold)).tracking(1)
                .foregroundStyle(Color.inkSecondary)
        case .firstThatFits:
            Text("FIRST THAT FITS").font(.mono(10, weight: .bold)).tracking(1.2)
                .foregroundStyle(Color.onAmber)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 5))
        case .laterBy(let minutes):
            Text("+\(durationWords(minutes)) there").font(.mono(12.5, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
        case .lastTrain:
            Text("LAST TRAIN").font(.mono(10, weight: .bold)).tracking(1.2)
                .foregroundStyle(Color.amber)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.amber, lineWidth: 1.5))
        }
    }

    private var stayStepper: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("STAY AT LEAST", color: .inkSecondary)
                Text(durationWords(Int(stay / 60))).font(.mono(24, weight: .bold)).foregroundStyle(Color.ink)
            }
            Spacer()
            HStack(spacing: 6) {
                stepButton("minus", enabled: stay > 15 * 60) { stay = max(15 * 60, stay - 15 * 60) }
                stepButton("plus", enabled: true) { stay += 15 * 60 }
            }
        }
        .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }

    private func stepButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44).background(Color.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(symbol == "minus" ? "Stay 15 minutes less" : "Stay 15 minutes more")
    }

    @ViewBuilder private func watchBoth(_ plan: RoundTripPlan) -> some View {
        VStack(spacing: 8) {
            Button {
                Task { await watch(plan) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: watchedBoth ? "bell.fill" : "bell")
                    Text(watchedBoth ? "Watching both trains" : "Watch both trains")
                }
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.onAmber)
                .frame(maxWidth: .infinity).frame(minHeight: 52)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityValue(watchedBoth ? "On" : "Off")
            if let back = plan.pairedReturn {
                // `pairedReturn` is already the first return that fits, so if the earliest one is lost the
                // view simply proposes the next; the copy promises that.
                Text("If the \(hhmm(back.scheduledDeparture)) is cancelled or late, you get the next one that fits.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
    }

    private func watch(_ plan: RoundTripPlan) async {
        if let out = plan.selectedOutbound { await data.watching.watch(out, to: plan.outbound) }
        if let back = plan.pairedReturn { await data.watching.watch(back, to: plan.returnLeg) }
        watchedBoth = true
    }

    private var shareText: String {
        guard let plan else { return "" }
        return [plan.selectedOutbound.map { data.eta.shareText(for: $0, leg: plan.outbound) },
                plan.pairedReturn.map { data.eta.shareText(for: $0, leg: plan.returnLeg) }]
            .compactMap { $0 }.joined(separator: "\n\n")
    }

    // MARK: Shared pieces

    private func sectionLabel(_ text: String, color: Color = .amber) -> some View {
        Text(text).font(.mono(color == .amber ? 12 : 10.5, weight: color == .amber ? .bold : .semibold))
            .tracking(color == .amber ? 1.8 : 1.4).foregroundStyle(color)
    }

    private func routeHeader(_ leg: Leg) -> some View {
        HStack(spacing: 12) {
            RoutePins(lineColor: .inkSecondary, destination: .solid(.amber),
                      originDiameter: 10, destinationDiameter: 13, lineWidth: 2.5)
                .frame(width: 14, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.from.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Color.ink.opacity(0.7))
                Text(leg.to.name).font(.system(size: 30, weight: .bold)).foregroundStyle(Color.ink)
            }
        }
    }

    /// Departure → arrival, the scheduled departure in amber and the amended arrival next to it; both
    /// struck through when the train is cancelled.
    private func timeLine(_ train: TrainDeparture) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(hhmm(train.scheduledDeparture)).font(.mono(22, weight: .bold))
                .foregroundStyle(train.isCancelled ? Color.inkSecondary : Color.amber)
                .strikethrough(train.isCancelled)
            if let arrival = train.expectedArrival ?? train.scheduledArrival {
                dash
                Text(hhmm(arrival)).font(.mono(15, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.85)).strikethrough(train.isCancelled)
            }
        }
    }

    private var dash: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.inkSecondary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
        .frame(width: 18, height: 2)
        .accessibilityHidden(true)
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.onAmber)
            .frame(width: 22, height: 22).background(Color.amber, in: Circle())
            .accessibilityLabel("Picked")
    }

    private var hingePill: some View {
        Group {
            if let plan, let arrival = plan.pairedArrival, let back = plan.pairedReturn {
                HStack(spacing: 8) {
                    Text(hhmm(arrival))
                    dashWide
                    Text(hhmm(back.scheduledDeparture))
                }
                .font(.mono(12, weight: .bold)).tracking(0.6).foregroundStyle(Color.ground)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.ink, in: Capsule())
                .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                .accessibilityLabel("Arrive \(hhmm(arrival)), return \(hhmm(back.scheduledDeparture))")
            }
        }
    }

    private var dashWide: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.ground), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 3]))
        }
        .frame(width: 30, height: 10)
        .accessibilityHidden(true)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.ink.opacity(0.07)).frame(height: 1)
    }

    private var loading: some View {
        HStack { Spacer(); ProgressView().tint(.amber); Spacer() }.frame(height: 120)
    }

    // MARK: Formatting

    private func relative(_ date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return minutes < 1 ? "now" : durationWords(minutes)
    }

    /// Minutes as "45 min" / "2 h 30" / "1 h", the house wording. The hour form drops ":00" to match the
    /// "+1 h there" / "LAST 22:42" copy, but keeps "2 h 30".
    private func durationWords(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    private func legWords(_ train: TrainDeparture) -> String {
        guard let duration = train.duration else { return "" }
        return durationWords(Int(duration / 60))
    }

    /// "TER 17652 · 25 min". nil for a bare preview row with no train number (the "TOO EARLY" placeholder),
    /// which the mockup draws without a subtitle.
    private func subtitle(_ train: TrainDeparture) -> String? {
        guard let number = train.trainNumber else { return nil }
        var text = ""
        if let mode = train.mode { text += mode + " " }
        text += number
        if let duration = train.duration { text += " · \(Int(duration / 60)) min" }
        return text
    }

    private func hhmm(_ date: Date) -> String { Self.hhmm.string(from: date) }

    /// 24-hour Paris wall-clock, like the mockup ("17:46"), independent of the device locale and zone —
    /// SNCF times are Europe/Paris.
    private static let hhmm: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// The amber 8 % fill and inset ring that marks the picked outbound and the first return that fits.
private struct RowHighlight: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background { if selected { RoundedRectangle(cornerRadius: 16).fill(Color.amber.opacity(0.08)) } }
            .overlay { if selected { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.amber.opacity(0.55), lineWidth: 1.5) } }
    }
}

#Preview {
    RoundTripView(now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .frame(width: 900, height: 900)
}
