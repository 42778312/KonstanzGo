import KGCore
import KGDesign
import SwiftUI

/// A place picked from the search (Apple Maps style): name, what and where it is, ★ and ✕, then "Von / Nach"
/// (both can be changed, and swapped) and the connections, now or at a chosen time. Each card opens that
/// route on the map.
struct PlaceSheet: View {
    let services: AppServices
    let target: SavedTarget
    let onClose: () -> Void
    /// Tells the map the current Von, Nach and time, which outlive this view while a route is open on top.
    let onQuery: (PlanQuery) -> Void
    @State private var query: PlanQuery
    @State private var journeys: [Journey] = []
    @State private var tags: [String: Set<JourneyTag>] = [:]
    @State private var searching = true
    @State private var choosingWhen = false
    @State private var editing: End?
    @State private var swapTurns = 0.0
    @State private var now = Date.now

    enum End: Identifiable {
        case from, to
        var id: Self { self }
    }

    /// `saved`: what the user had chosen before opening a route, to come back to. Without it, from where they are.
    init(services: AppServices, target: SavedTarget, saved: PlanQuery? = nil, onQuery: @escaping (PlanQuery) -> Void = { _ in },
         onClose: @escaping () -> Void) {
        self.services = services
        self.target = target
        self.onClose = onClose
        self.onQuery = onQuery
        _query = State(initialValue: saved ?? PlanQuery(from: services.routeStart, to: Endpoint(name: target.name,
                                                                                  coordinate: target.coordinate)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                header
                endpoints
                HStack(spacing: KGSpace.small) {
                    KGChip(whenTitle, isOn: true) { choosingWhen = true }
                        .accessibilityIdentifier("whenChip")
                    KGChip(Text("Später", bundle: .module)) { later() }
                    Spacer()
                }
                connections
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, KGSpace.large)
            .padding(.bottom, KGSpace.xl)
        }
        .scrollIndicators(.hidden)
        .task(id: query) { await plan() }
        .onChange(of: query) { _, new in onQuery(new) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
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
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: KGSpace.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: isPicked ? target.name : query.to.name).kgFont(.title).foregroundStyle(KGColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if isPicked, !subtitle.isEmpty {
                    Text(verbatim: subtitle).kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        .lineLimit(1)
                }
                // A dropped pin: its exact latitude and longitude (about a metre), selectable to copy.
                if isPicked, case .point = target {
                    Label {
                        Text(verbatim: PinScreen.degrees(target.coordinate, digits: 5)).monospacedDigit()
                    } icon: {
                        KGIconView(.pin, size: 13)
                    }
                    .kgFont(.footnote.weighted(KGFont.semiBold))
                    .foregroundStyle(KGColor.location)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pinCoordinates")
                }
            }
            Spacer()
            if isPicked { FavoriteButton(services: services, target: target) }
            KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain, action: onClose)
                .accessibilityIdentifier("closePlace")
        }
    }

    /// "Hafenstraße 2 · Café · 6 Min. zu Fuß".
    private var subtitle: String {
        var parts: [String] = []
        switch target {
        case let .place(id, _, _, _):
            if let place = services.transit.placeSearch.place(id: id) {
                parts += [place.address ?? "", place.categoryGerman]
                if place.address == nil { parts.append(place.area.components(separatedBy: ",").first ?? "") }
            }
        case .point:
            parts.append(String(localized: "Markierter Ort", bundle: .module))
        case .station:
            parts.append(String(localized: "Haltestelle", bundle: .module))
        }
        if services.here != nil {
            // The same number as the walking option below, when there is one.
            let walkOption = query.from.coordinate == services.here?.coordinate ? journeys.first { $0.rides.isEmpty } : nil
            let minutes = walkOption?.minutes ?? max(1, Int((target.coordinate.distance(to: services.anchor) * 1.25 / 80).rounded(.up)))
            // Further than this nobody walks: saying "137 Min. zu Fuß" only confuses.
            if minutes <= 45 { parts.append(String(localized: "\(minutes) Min. zu Fuß", bundle: .module)) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The place is still the target (not changed or swapped away).
    private var isPicked: Bool { query.to.coordinate == target.coordinate }

    /// "Von" (blue ring) and "Nach" (black diamond) on a dotted rail, each tappable, swap on the right.
    private var endpoints: some View {
        HStack(spacing: KGSpace.medium) {
            VStack(spacing: 4) {
                Circle().strokeBorder(KGColor.location, lineWidth: 4).frame(width: 14, height: 14)
                Rectangle().fill(KGColor.chevron).frame(width: 2, height: 30)
                    .mask(VStack(spacing: 3) { ForEach(0..<5, id: \.self) { _ in Rectangle().frame(height: 3) } })
                RoundedRectangle(cornerRadius: 3).fill(KGColor.ink).frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
            }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                field(Text("Von", bundle: .module), query.from) { editing = .from }
                    .accessibilityIdentifier("placeFrom")
                Rectangle().fill(KGColor.line).frame(height: 1)
                field(Text("Nach", bundle: .module), query.to) { editing = .to }
                    .accessibilityIdentifier("placeTo")
            }
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { swapTurns += 180 }
                query = query.swapped
            } label: {
                KGIconView(.swap, size: 20).foregroundStyle(KGColor.ink)
                    .rotationEffect(.degrees(swapTurns))
                    .frame(width: KGSize.touch, height: KGSize.touch)
                    .kgGlassCard(in: .circle)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Start und Ziel tauschen", bundle: .module))
            .accessibilityIdentifier("swapEnds")
        }
        .padding(.leading, KGSpace.screen)
        .padding(.trailing, KGSpace.compact)
        .padding(.vertical, KGSpace.xxs)
        .kgGlassCard(in: .kgRounded(KGRadius.option))
    }

    private func field(_ label: Text, _ endpoint: Endpoint, action: @escaping () -> Void) -> some View {
        let isHere = endpoint.coordinate == services.here?.coordinate
        return Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    label.kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.ink2)
                    Text(verbatim: endpoint.name).kgFont(.bodyMedium).lineLimit(1)
                        .foregroundStyle(isHere ? KGColor.location : KGColor.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KGIconView(.chevronRight, size: 12).foregroundStyle(KGColor.chevron)
            }
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Tippen zum Ändern", bundle: .module))
    }

    @ViewBuilder private var connections: some View {
        if searching {
            HStack(spacing: KGSpace.small) {
                ProgressView()
                Text("Seeri sucht deine Verbindung", bundle: .module)
                    .kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
        } else if journeys.isEmpty {
            Text("Keine Verbindung gefunden", bundle: .module)
                .kgFont(.body).foregroundStyle(KGColor.ink2)
                .frame(maxWidth: .infinity, minHeight: 90)
        } else {
            let rain = services.rainAdvice(for: journeys, when: query.when, now: now)
            ForEach(journeys) { journey in
                if rain?.journeyID == journey.id, let rain { RainNote(minutes: rain.minutesSaved) }
                JourneyCard(journey: journey, tag: tags[journey.id]?.first, when: query.when,
                            isFirst: journey.id == journeys.first?.id, isSelected: false, now: now,
                            delay: journey.firstRide.map { services.live.status(ofTrip: $0.tripID, at: now).delayMinutes } ?? 0) {
                    services.router.open(.journey(journey))
                }
            }
            HStack {
                KGTextButton(Text("Spätere Verbindungen", bundle: .module)) { later() }
                Spacer()
            }
        }
    }

    private var whenTitle: Text {
        switch query.when {
        case .now: Text("Jetzt", bundle: .module)
        case let .departAt(date): Text("Ab \(KGStrings.clock(date))", bundle: .module)
        case let .arriveBy(date): Text("An \(KGStrings.clock(date))", bundle: .module)
        }
    }

    // MARK: Planning

    private func plan() async {
        searching = true
        let request = query.request()
        let transit = services.transit
        // Now, what's known counts; a later time goes by the timetable.
        let live = query.when == .now ? services.live.state : LiveState()
        let found = await Task.detached(priority: .userInitiated) { (try? transit.plan(request, live: live)) ?? [] }.value
        guard !Task.isCancelled else { return }
        let ranked = JourneyPlanner.ranked(found, by: query.preference, arriveBy: request.arriveBy)
        withAnimation(.easeOut(duration: 0.2)) {
            journeys = ranked
            tags = JourneyPlanner.tags(for: ranked)
            searching = false
        }
    }

    /// "Später": from just after the last option's departure.
    private func later() {
        let last = journeys.map(\.start).max() ?? .now
        query.when = .departAt(last.addingTimeInterval(60))
    }
}
