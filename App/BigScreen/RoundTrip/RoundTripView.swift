import SNCFCore
import SwiftUI

/// Round trip — the outbound board and the way back side by side, with the stay stepper. Across the Duo's
/// fold the two panes come from Apple's `ArrangementView` and only a dashed tie crosses the fold
/// (Design/BigScreen/Duo/DuoLayouts.html, screen 4); elsewhere two panes whenever the window is wide enough
/// for two compact columns (iPad, iPad split view, Mac), with the pairing pill between them; otherwise
/// (the folded Duo, a narrow iPad window) the way back is a pushed second screen.
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
    /// The picked rows' positions, which line the Duo's two panes up and place the tie between them.
    @State private var outboundY: RowY?
    @State private var returnY: RowY?
    /// The board the round trip was opened from; nil takes the first saved journey.
    private let outbound: Leg?

    init(now: Date = Date(), outbound: Leg? = nil) {
        self.now = now
        self.outbound = outbound
    }

    /// Below this the two columns would be too cramped, so the way back becomes a pushed screen.
    private let minTwoPaneWidth: CGFloat = 680
    private let cal = SNCFTime.calendar

    var body: some View {
        GeometryReader { geo in
            Group {
                if let fold = Fold.division(in: geo) {
                    duo(fold: fold)
                } else if geo.size.width >= minTwoPaneWidth {
                    twoPane
                } else {
                    narrow
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.ground.ignoresSafeArea())
        }
        // One reload covers the first appearance, ⌘R, a new minimum stay and a re-picked outbound.
        .task(id: ReloadKey(tick: model.refreshTick, stayMinutes: Int(stay / 60), pick: pick)) {
            await load()
        }
    }

    private struct ReloadKey: Hashable { let tick: Int; let stayMinutes: Int; let pick: TrainIdentity? }

    private func load() async {
        watchedBoth = false
        if let outbound {
            plan = await data.roundTrip.roundTrip(outbound: outbound, pick: pick, stay: stay, at: now)
            return
        }
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
            pane { outboundPane() }
            pane { returnPane() }
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
                    outboundPane()
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
                ScrollView { returnPane().padding(16) }
                    .background(Color.ground.ignoresSafeArea())
                    .navigationTitle("Way back")
            }
        }
    }

    // MARK: Duo

    // Nonisolated: the row measuring reads them from `onGeometryChange`'s Sendable closure.
    nonisolated static let outboundSpace = "roundTrip.outbound"
    nonisolated static let returnSpace = "roundTrip.return"
    nonisolated static let screenSpace = "roundTrip.screen"
    /// Each pane's inset on the fold side: the gap the tie spans on either side of the division.
    private static let foldGutter: CGFloat = 20

    /// The Duo's inner display. Apple places the two panes (`ArrangementView`, pinned side by side while
    /// the fold runs top to bottom, left to stack in portrait); nothing sits on the fold but the tie,
    /// drawn from the division's own frame so it spans the active ~30 pt band when half open too. The
    /// actions are toolbar items, which the Duo stands up in its strip.
    @ViewBuilder private func duo(fold: CGRect) -> some View {
        let landscape = fold.height > fold.width
        let out = duoPane(Self.outboundSpace, raise: landscape ? lift(outboundY, under: returnY) : 0) {
            outboundPane(duo: true)
        }
        let back = duoPane(Self.returnSpace, raise: landscape ? lift(returnY, under: outboundY) : 0) {
            returnPane(duo: true)
        }
        Group {
            #if os(iOS)
            if #available(iOS 27.1, *) {
                ArrangementView { out } secondary: { back }
                    .arrangementViewStyle(landscape ? SplitArrangementViewStyle().axes(.horizontal) : SplitArrangementViewStyle())
            } else {
                handSplit(out, back, fold: fold, landscape: landscape)
            }
            #else
            handSplit(out, back, fold: fold, landscape: landscape)
            #endif
        }
        .overlay { if landscape { tie(fold) } }
        .coordinateSpace(.named(Self.screenSpace))
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(watchedBoth ? "Watching both trains" : "Watch both trains",
                       systemImage: watchedBoth ? "bell.fill" : "bell") {
                    if let plan { Task { await watch(plan) } }
                }
                .prominentToolbarButton()
                .disabled(plan == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink("Share the plan", item: shareText).disabled(plan == nil)
            }
            // Text only, so it stays horizontal at the top while the labelled items stand up in the strip.
            // No multi-day in scope: today is the only day.
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Today") { Button("Today", systemImage: "checkmark") {} }
            }
        }
        #endif
    }

    /// Where `ArrangementView` is missing (before iOS 27.1, which has no fold to report anyway) and in the
    /// headless renders: the same two panes cut at the division by hand.
    @ViewBuilder private func handSplit(_ out: some View, _ back: some View, fold: CGRect, landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: fold.width) { out.frame(width: fold.minX); back }
        } else {
            VStack(spacing: fold.height) { out.frame(height: fold.minY); back }
        }
    }

    /// One pane, scrolling inside itself (Apple: never an `ArrangementView` inside a scroll view). `raise`
    /// pushes its content down so its picked row lines up with the other pane's.
    private func duoPane<Content: View>(_ space: String, raise: CGFloat,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .coordinateSpace(.named(space))
                .padding(.top, raise)
                .padding(.horizontal, Self.foldGutter).padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// How far down a pane's content goes for its picked row to meet the other one's; measured in the
    /// pane's own content, which the padding does not move, so the two values never chase each other.
    private func lift(_ mine: RowY?, under other: RowY?) -> CGFloat {
        guard let mine, let other else { return 0 }
        return max(0, other.content - mine.content)
    }

    /// The dashed tie: card edge to card edge across the division, at the picked rows' shared line. Hidden
    /// while one pane is scrolled away from the other, where a tie would point at nothing.
    @ViewBuilder private func tie(_ fold: CGRect) -> some View {
        if let outboundY, let returnY, abs(outboundY.screen - returnY.screen) < 2, outboundY.screen > 0 {
            Path { path in
                path.move(to: CGPoint(x: fold.minX - Self.foldGutter, y: outboundY.screen))
                path.addLine(to: CGPoint(x: fold.maxX + Self.foldGutter, y: outboundY.screen))
            }
            .stroke(Color.ink.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Minutes at the destination between the picked outbound's arrival and the paired return.
    private var thereMinutes: Int? {
        guard let arrival = plan?.pairedArrival, let back = plan?.pairedReturn else { return nil }
        return Int(back.scheduledDeparture.timeIntervalSince(arrival) / 60)
    }

    /// The outbound's paper tab, "✓ 2 h 31 THERE", reaching the card's inner edge where the tie leaves.
    private func thereTab(_ minutes: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.onAmber)
                .frame(width: 18, height: 18).background(Color.amber, in: Circle())
            Text("\(durationWords(minutes).uppercased()) THERE").font(.mono(11, weight: .bold)).tracking(0.8)
                .foregroundStyle(Color.ground)
        }
        .padding(.leading, 5).padding(.trailing, 16).padding(.vertical, 5)
        .background(Color.ink, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14))
        .padding(.trailing, -16)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Picked, \(durationWords(minutes)) there")
    }

    /// One pane's scrolling column; a ScrollView keeps a short Mac window from clipping the rows.
    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { content().padding(.horizontal, 20).padding(.vertical, 24) }
            .frame(maxWidth: .infinity)
    }

    // MARK: Outbound pane

    /// `duo`: the Duo's pane, whose day picker, Share and Watch live in the toolbar and whose picked row
    /// carries the paper tab instead of the check.
    @ViewBuilder private func outboundPane(duo: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("① OUTBOUND")
                Spacer()
                // No multi-day in scope; the pill is decorative, so it carries no action.
                if !duo {
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(Color.raised.opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(Color.ink.opacity(0.10), lineWidth: 1))
                }
            }

            if let plan {
                routeHeader(plan.outbound)
                card {
                    ForEach(Array(plan.outboundOptions.enumerated()), id: \.offset) { index, train in
                        if index > 0 { rowDivider }
                        outboundRow(train, selectedID: selectedOutboundID, duo: duo)
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

    private func outboundRow(_ train: TrainDeparture, selectedID: TrainIdentity?, duo: Bool) -> some View {
        let id = TrainIdentity(train, calendar: cal)
        let picked = id != nil && id == selectedID
        return Button { if !train.isCancelled, let id { pick = id } } label: {
            outboundRowContent(train, picked: picked, duo: duo)
                .measuringRow(duo && picked, in: Self.outboundSpace) { outboundY = $0 }
        }
        .buttonStyle(.plain)
        .disabled(train.isCancelled || id == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func outboundRowContent(_ train: TrainDeparture, picked: Bool, duo: Bool) -> some View {
        // On the Duo the tab takes the trailing edge, so an on-time pick's "in 6 min" joins the subtitle.
        let soonInSubtitle = duo && picked && train.status == .onTime
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                timeLine(train)
                if let subtitle = subtitle(train) {
                    if soonInSubtitle {
                        Text("\(subtitle) · \(Text("in \(relative(train.expectedDeparture))").foregroundStyle(Color.soon))")
                            .font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    } else {
                        Text(subtitle).font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                    }
                }
            }
            .opacity(train.isCancelled ? 0.55 : 1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if picked, duo, let there = thereMinutes {
                    thereTab(there)
                } else if picked {
                    checkBadge
                }
                if !soonInSubtitle { outboundTrailing(train, picked: picked) }
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
                sectionLabel("THE WHOLE DAY OUT", accent: false)
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

    @ViewBuilder private func returnPane(duo: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("② WAY BACK")
                Spacer()
                if !duo { shareButton }
            }

            if let plan {
                routeHeader(plan.returnLeg)
                // On the Duo the stepper goes under the list, as the whole day does on the outbound side, so
                // both lists start level and the picked rows can share a line.
                if !duo { stayStepper }
                returnList(plan, duo: duo)
                if duo {
                    stayStepper
                    watchFootnote(plan, prefix: "Watch both trains (the bell): if")
                } else {
                    watchBoth(plan)
                }
            } else {
                loading
            }
        }
    }

    private var shareButton: some View {
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

    @ViewBuilder private func returnList(_ plan: RoundTripPlan, duo: Bool) -> some View {
                // The way back is asked by count from the arrival, so late in the evening it runs on into the
                // morning. Those rows go under the split, tagged TOMORROW: "first that fits" on a train the
                // next day would read as a return tonight.
                let tonight = plan.returnOptions.filter { !BoardReading.isTomorrow($0.train, after: now) }
                let morning = plan.returnOptions.filter { BoardReading.isTomorrow($0.train, after: now) }
                card {
                    ForEach(Array(tonight.enumerated()), id: \.offset) { index, option in
                        if index > 0 { rowDivider }
                        returnRow(option, lastTonight: !morning.isEmpty && index == tonight.count - 1, duo: duo)
                    }
                    if !morning.isEmpty {
                        TomorrowSplit(lastTonight: tonight.last { !$0.train.isCancelled }?.train.scheduledDeparture, inset: 16)
                        ForEach(Array(morning.enumerated()), id: \.offset) { index, option in
                            if index > 0 { rowDivider }
                            returnRow(option, tomorrow: true)
                        }
                    }
                }
    }

    /// `lastTonight` marks tonight's final row when the morning follows: the planner gave LAST TRAIN to the
    /// list's final row, which is then tomorrow's, so tonight's last would otherwise read "+1 h there".
    private func returnRow(_ option: ReturnOption, lastTonight: Bool = false, tomorrow: Bool = false, duo: Bool = false) -> some View {
        let dimmed = option.fit == .tooEarly && !tomorrow
        let paired = option.fit == .firstThatFits && !tomorrow
        var fit = option.fit
        if lastTonight, case .laterBy = fit { fit = .lastTrain }
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                timeLine(option.train, tab: duo && paired)
                if let subtitle = subtitle(option.train) {
                    Text(subtitle).font(.mono(11.5, weight: .medium)).foregroundStyle(Color.inkSecondary)
                }
            }
            .opacity(option.train.isCancelled ? 0.55 : 1)
            Spacer(minLength: 4)
            // A return can be late or cancelled too; say so beside its fit, as the outbound rows do.
            VStack(alignment: .trailing, spacing: 4) {
                if tomorrow { tomorrowTag } else { returnTag(fit) }
                returnStatus(option.train)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
        .modifier(RowHighlight(selected: paired))
        .measuringRow(duo && paired, in: Self.returnSpace) { returnY = $0 }
        .accessibilityElement(children: .combine)
    }

    private var tomorrowTag: some View {
        Text("TOMORROW").font(.mono(10, weight: .bold)).tracking(1.2)
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(TomorrowSplit.navy, in: RoundedRectangle(cornerRadius: 5))
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
                .foregroundStyle(Color.amberText)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.amberText, lineWidth: 1.5))
        }
    }

    private var stayStepper: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("STAY AT LEAST", accent: false)
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
            watchFootnote(plan, prefix: "If").multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }

    /// `pairedReturn` is already the first return that fits, so if the earliest one is lost the view simply
    /// proposes the next; the copy promises that.
    @ViewBuilder private func watchFootnote(_ plan: RoundTripPlan, prefix: String) -> some View {
        if let back = plan.pairedReturn {
            Text("\(prefix) the \(hhmm(back.scheduledDeparture)) is cancelled or late, you get the next one that fits.")
                .font(.system(size: 11.5)).foregroundStyle(Color.inkSecondary)
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

    private func sectionLabel(_ text: String, accent: Bool = true) -> some View {
        Text(text).font(.mono(accent ? 12 : 10.5, weight: accent ? .bold : .semibold))
            .tracking(accent ? 1.8 : 1.4).foregroundStyle(accent ? Color.amberText : Color.inkSecondary)
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
    /// `tab`: the paired return on the Duo, its time on a paper tab reaching the card's inner edge, where the
    /// tie from the outbound lands.
    private func timeLine(_ train: TrainDeparture, tab: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(hhmm(train.scheduledDeparture)).font(.mono(22, weight: .bold))
                .foregroundStyle(tab ? Color.ground : train.isCancelled ? Color.inkSecondary : Color.amberText)
                .strikethrough(train.isCancelled)
                .padding(tab ? EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 9) : EdgeInsets())
                .background(tab ? Color.ink : .clear,
                            in: UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
                .padding(.leading, tab ? -16 : 0)
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
            .background(Color.surface)
            // Clipped so a selected first or last row's edge-to-edge tint follows the card's corners.
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.ink.opacity(0.07)).frame(height: 1)
    }

    private var loading: some View {
        HStack { Spacer(); ProgressView().tint(.amberText); Spacer() }.frame(height: 120)
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

    private func hhmm(_ date: Date) -> String { SNCFTime.hhmm(date) }
}

/// The row padding, and the selected-row tint that marks the picked outbound and the first return that fits.
private struct RowHighlight: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, 13)
            .selectedRowBackground(selected)
    }
}

/// A picked row's middle: in its pane's content (to line the panes up) and in the round trip (for the tie).
struct RowY: Equatable {
    var content: CGFloat
    var screen: CGFloat
}

private extension View {
    @ViewBuilder func measuringRow(_ isOn: Bool, in space: String, _ action: @escaping (RowY) -> Void) -> some View {
        if isOn {
            onGeometryChange(for: RowY.self) { proxy in
                RowY(content: proxy.frame(in: .named(space)).midY,
                     screen: proxy.frame(in: .named(RoundTripView.screenSpace)).midY)
            } action: { action($0) }
        } else {
            self
        }
    }
}

#Preview {
    RoundTripView(now: BigScreenFixtures.now)
        .environment(BigScreenModel())
        .frame(width: 900, height: 900)
}
