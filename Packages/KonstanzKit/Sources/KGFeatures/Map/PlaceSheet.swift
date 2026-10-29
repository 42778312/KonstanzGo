import KGCore
import KGDesign
import SwiftUI

/// A place picked from the search (Apple Maps style): name, what and where it is, ★ and ✕, then the
/// connections there from where the user is, now or at a chosen time. Each card opens that route on the map;
/// the start can be changed.
struct PlaceSheet: View {
    let services: AppServices
    let target: SavedTarget
    let onClose: () -> Void
    @State private var query: PlanQuery
    @State private var journeys: [Journey] = []
    @State private var tags: [String: Set<JourneyTag>] = [:]
    @State private var searching = true
    @State private var choosingWhen = false
    @State private var choosingStart = false
    @State private var now = Date.now

    init(services: AppServices, target: SavedTarget, onClose: @escaping () -> Void) {
        self.services = services
        self.target = target
        self.onClose = onClose
        let start = services.here ?? Endpoint(name: String(localized: "Altstadt", bundle: .module),
                                              coordinate: MapRegion.center)
        _query = State(initialValue: PlanQuery(from: start, to: Endpoint(name: target.name,
                                                                         coordinate: target.coordinate)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                header
                startRow
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
        .sheet(isPresented: $choosingStart) {
            EndpointPicker(services: services, title: Text("Von wo?", bundle: .module)) { query.from = $0 }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: KGSpace.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: target.name).kgFont(.title).foregroundStyle(KGColor.ink)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle).kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        .lineLimit(2)
                }
            }
            Spacer()
            FavoriteButton(services: services, target: target)
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
            let minutes = max(1, Int((target.coordinate.distance(to: services.anchor) * 1.25 / 80).rounded(.up)))
            parts.append(String(localized: "\(minutes) Min. zu Fuß", bundle: .module))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Von Mein Standort ›": tap to start somewhere else.
    private var startRow: some View {
        let isHere = query.from.coordinate == services.here?.coordinate
        return Button { choosingStart = true } label: {
            HStack(spacing: KGSpace.medium) {
                Circle().strokeBorder(KGColor.location, lineWidth: 4).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Von", bundle: .module).kgFont(.caption.weighted(KGFont.semiBold))
                        .foregroundStyle(KGColor.ink2)
                    Text(verbatim: query.from.name).kgFont(.bodyMedium).lineLimit(1)
                        .foregroundStyle(isHere ? KGColor.location : KGColor.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KGIconView(.chevronRight, size: 13).foregroundStyle(KGColor.chevron)
            }
            .padding(.horizontal, KGSpace.screen)
            .frame(minHeight: 56)
            .background(KGColor.card, in: .kgRounded(KGRadius.option))
            .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Tippen zum Ändern", bundle: .module))
        .accessibilityIdentifier("placeFrom")
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
            ForEach(journeys) { journey in
                JourneyCard(journey: journey, tag: tags[journey.id]?.first, when: query.when,
                            isFirst: journey.id == journeys.first?.id, isSelected: false, now: now) {
                    services.router.open(.routeMap(journey, query))
                }
            }
            HStack {
                KGTextButton(Text("Spätere Verbindungen", bundle: .module)) { later() }
                Spacer()
                KGTextButton(Text("Alle Details", bundle: .module)) { services.router.open(.routes(query)) }
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
        let found = await Task.detached(priority: .userInitiated) { (try? transit.plan(request)) ?? [] }.value
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
