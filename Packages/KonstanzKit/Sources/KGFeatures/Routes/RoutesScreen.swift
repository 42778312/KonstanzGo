import KGCore
import KGDesign
import SwiftUI

/// Screen 10 (Verbindungen), with 20 (Suche läuft) while planning takes longer than 300 ms and 23 (Keine
/// Verbindung) when nothing runs (plan S10, S11, S14).
struct RoutesScreen: View {
    let services: AppServices
    @State private var query: PlanQuery
    @State private var journeys: [Journey] = []
    @State private var tags: [String: Set<JourneyTag>] = [:]
    @State private var selected: String?
    @State private var state = LoadState.searching
    @State private var showsFinding = false
    @State private var choosingWhen = false
    @State private var swapTurns = 0.0
    /// Which end is being changed in the picker.
    @State private var editing: End?

    enum End: Identifiable {
        case from, to
        var id: Self { self }
    }
    @State private var now = Date.now

    enum LoadState { case searching, done, failed }

    init(services: AppServices, query: PlanQuery) {
        self.services = services
        _query = State(initialValue: query)
    }

    var body: some View {
        ZStack {
            KGColor.card.ignoresSafeArea()
            if showsFinding {
                FindingView(query: query) { services.router.back() }
                    .transition(.opacity)
            } else if state == .done, journeys.isEmpty {
                NoRouteView(services: services, query: query) { choosingWhen = true }
            } else {
                list
            }
        }
        .sheet(isPresented: $choosingWhen) {
            WhenSheet(query: query) { newQuery in
                query = newQuery
                choosingWhen = false
            }
        }
        .sheet(item: $editing) { end in
            EndpointPicker(services: services,
                           title: end == .from ? Text("Von wo?", bundle: .module) : Text("Wohin?", bundle: .module)) {
                endpoint in
                if end == .from { query.from = endpoint } else { query.to = endpoint }
            }
        }
        .task(id: query) { await plan() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
    }

    // MARK: List (10)

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Button { services.router.back() } label: {
                    KGIconView(.back, size: 22).foregroundStyle(KGColor.coral)
                        .frame(width: KGSize.touch, height: KGSize.touch)
                }
                .buttonStyle(KGPressStyle())
                .accessibilityLabel(Text("Zurück", bundle: .module))
                Spacer()
                Text("Verbindungen", bundle: .module).kgFont(.bodyMedium).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Color.clear.frame(width: KGSize.touch, height: KGSize.touch)
            }
            .padding(.horizontal, KGSpace.small)
            ScrollView {
                VStack(spacing: KGSpace.medium) {
                    endpoints.riseIn(after: 0)
                    chips.riseIn(after: 0.1)
                    if state == .searching {
                        ForEach(0..<3, id: \.self) { _ in ShimmerCard() }
                    }
                    ForEach(Array(journeys.enumerated()), id: \.element.id) { index, journey in
                        card(journey)
                            .popIn(after: 0.1 + Double(index) * 0.1)
                    }
                    if !journeys.isEmpty {
                        KGTextButton(Text("Spätere Verbindungen", bundle: .module)) { later() }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, KGSpace.screen)
                .padding(.top, KGSpace.small)
                .padding(.bottom, KGSpace.large)
            }
            .scrollIndicators(.hidden)
            // The button sits in its own bar under the list, so it never covers a card or "Spätere Verbindungen".
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let journey = journeys.first(where: { $0.id == selected }) {
                    BottomBar {
                        KGButton(Text("Los geht's", bundle: .module)) {
                            services.router.open(.journey(journey))
                        }
                        .accessibilityIdentifier("startJourney")
                    }
                }
            }
        }
    }

    /// Von / Nach with the rail and the swap button that turns (S11.1).
    private var endpoints: some View {
        HStack(spacing: KGSpace.medium) {
            VStack(spacing: 4) {
                Circle().strokeBorder(KGColor.location, lineWidth: 4).frame(width: 14, height: 14)
                Rectangle().fill(KGColor.chevron).frame(width: 2, height: 34)
                    .mask(VStack(spacing: 3) { ForEach(0..<6, id: \.self) { _ in Rectangle().frame(height: 3) } })
                RoundedRectangle(cornerRadius: 3).fill(KGColor.coral).frame(width: 13, height: 13)
                    .rotationEffect(.degrees(45))
            }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                endpointField(Text("Von", bundle: .module), query.from,
                              isHere: query.from.coordinate == services.here?.coordinate) { editing = .from }
                    .accessibilityIdentifier("editFrom")
                Rectangle().fill(KGColor.line).frame(height: 1)
                endpointField(Text("Nach", bundle: .module), query.to,
                              isHere: query.to.coordinate == services.here?.coordinate) { editing = .to }
                    .accessibilityIdentifier("editTo")
            }
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { swapTurns += 180 }
                query = query.swapped
            } label: {
                KGIconView(.swap, size: 20).foregroundStyle(KGColor.ink)
                    .rotationEffect(.degrees(swapTurns))
                    .frame(width: KGSize.touch, height: KGSize.touch)
                    .background(KGColor.glassFill, in: .circle)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Start und Ziel tauschen", bundle: .module))
        }
        .padding(.leading, KGSpace.screen)
        .padding(.trailing, KGSpace.small)
        .padding(.vertical, KGSpace.xxs)
        .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
    }

    /// Tapping a field opens the picker to change that end.
    private func endpointField(_ label: Text, _ endpoint: Endpoint, isHere: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                label.kgFont(.overline.sized(12)).textCase(nil).foregroundStyle(KGColor.ink2)
                Text(verbatim: endpoint.name).kgFont(.bodyMedium).lineLimit(1)
                    .foregroundStyle(isHere ? KGColor.location : KGColor.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Tippen zum Ändern", bundle: .module))
    }

    /// "Jetzt" (→ 19) and "Später" (S11.2). "Barrierefrei" stays hidden: there is no wheelchair data (0.3).
    private var chips: some View {
        HStack(spacing: KGSpace.small) {
            KGChip(whenTitle, isOn: true) { choosingWhen = true }
                .accessibilityIdentifier("whenChip")
            KGChip(Text("Später", bundle: .module)) { later() }
            Spacer()
        }
    }

    private var whenTitle: Text {
        switch query.when {
        case .now: Text("Jetzt", bundle: .module)
        case let .departAt(date): Text("Ab \(KGStrings.clock(date))", bundle: .module)
        case let .arriveBy(date): Text("An \(KGStrings.clock(date))", bundle: .module)
        }
    }

    private func card(_ journey: Journey) -> some View {
        JourneyCard(journey: journey, tag: tags[journey.id]?.first, when: query.when,
                    isFirst: journey.id == journeys.first?.id, isSelected: journey.id == selected, now: now) {
            withAnimation(.easeOut(duration: 0.2)) { selected = journey.id }
        }
    }

    // MARK: Planning

    /// Plans off the main thread. The finding screen shows only after 300 ms and then stays at least
    /// 600 ms, so it never flickers (S10.2).
    private func plan() async {
        state = .searching
        journeys = []
        let request = query.request()
        let transit = services.transit
        let started = ContinuousClock.now
        let work = Task.detached(priority: .userInitiated) { (try? transit.plan(request)) ?? [] }
        let reveal = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { withAnimation { showsFinding = true } }
        }
        let found = await work.value
        reveal.cancel()
        if showsFinding {
            let shown = ContinuousClock.now - started - .milliseconds(300)
            if shown < .milliseconds(600) { try? await Task.sleep(for: .milliseconds(600) - shown) }
        }
        let ranked = JourneyPlanner.ranked(found, by: query.preference, arriveBy: request.arriveBy)
        withAnimation {
            journeys = ranked
            tags = JourneyPlanner.tags(for: ranked)
            selected = ranked.first?.id
            showsFinding = false
            state = .done
        }
    }

    /// "Später": search again from just after the last option's departure (S11.5).
    private func later() {
        let last = journeys.map(\.start).max() ?? .now
        query.when = .departAt(last.addingTimeInterval(60))
    }
}

/// Grey placeholder cards while searching.
private struct ShimmerCard: View {
    @State private var phase = false

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.compact) {
            Capsule().fill(KGColor.card).frame(width: 190, height: 16)
            Capsule().fill(KGColor.card).frame(width: 120, height: 12)
        }
        .padding(KGSpace.screen)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
        .opacity(phase ? 0.6 : 1)
        .kgLoop(.seeriBounce, phase: $phase)
        .accessibilityHidden(true)
    }
}
