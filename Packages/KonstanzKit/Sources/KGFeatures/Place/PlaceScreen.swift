import KGCore
import KGDesign
import SwiftUI

/// Screen 15 (Ort): map with the place, its name and address, walk and area; "Merken"; stops
/// nearby with their next bus; "Route hierher" (plan S7.1).
struct PlaceScreen: View {
    let services: AppServices
    let place: Place

    var body: some View {
        ZStack(alignment: .top) {
            MapStrip(services: services, center: place.coordinate, zoom: 16, marker: .place)
                .frame(height: 330)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                Color.clear.frame(height: 296 - 47)
                PlacePanel(services: services, title: Text(verbatim: place.name), subtitle: subtitle,
                           coordinate: place.coordinate, target: target, area: place.area)
            }
            HStack {
                KGRoundIconButton(.back, label: Text("Zurück", bundle: .module)) { services.router.back() }
                Spacer()
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, 11)
        }
        .background(KGColor.surface.ignoresSafeArea())
    }

    private var subtitle: String {
        [place.address ?? "", place.categoryGerman].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var target: SavedTarget {
        .place(id: place.id, name: place.name, kind: place.kind, coordinate: place.coordinate)
    }
}

/// The white panel shared by 15 and 16: title, line, chips, actions, nearby stops, "Route hierher".
struct PlacePanel: View {
    let services: AppServices
    let title: Text
    let subtitle: String
    let coordinate: Coordinate
    let target: SavedTarget
    var area: String = ""
    var extraActions: AnyView?
    @State private var stops: [(station: Station, metres: Double, next: Departure?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    title.kgFont(.display.weighted(KGFont.bold)).foregroundStyle(KGColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty {
                        Text(verbatim: subtitle).kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                            .padding(.top, 2)
                    }
                    HStack(spacing: KGSpace.small) {
                        if services.here != nil {
                            KGWalkChip(minutes: walkMinutes(coordinate.distance(to: services.anchor)))
                        }
                        if !area.isEmpty {
                            Text(verbatim: area.components(separatedBy: ",").first ?? area)
                                .kgFont(.footnote.weighted(KGFont.bold))
                                .foregroundStyle(KGColor.location)
                                .padding(.horizontal, KGSpace.medium)
                                .frame(minHeight: 30)
                                .background(KGColor.locationTint, in: .capsule)
                        }
                    }
                    .padding(.top, KGSpace.medium)
                    HStack(spacing: KGSpace.compact) {
                        let saved = services.isFavorite(target)
                        KGButton(saved ? Text("Gemerkt", bundle: .module) : Text("Merken", bundle: .module),
                                 icon: .star, kind: .outline) {
                            withAnimation(KGMotion.pop) { services.toggleFavorite(target) }
                        }
                        .accessibilityAddTraits(saved ? .isSelected : [])
                        if let extraActions { extraActions }
                    }
                    .padding(.top, KGSpace.screen)
                    if !stops.isEmpty {
                        KGSectionHeader(Text("Haltestellen in der Nähe", bundle: .module)).padding(.top, KGSpace.large)
                        ForEach(Array(stops.enumerated()), id: \.element.station.id) { index, stop in
                            NearbyStopRow(station: stop.station, metres: stop.metres, next: stop.next)
                                .onTapGesture { services.router.open(.stop(stop.station.id)) }
                                .accessibilityAddTraits(.isButton)
                                .overlay(alignment: .bottom) {
                                    if index < stops.count - 1 { Rectangle().fill(KGColor.line).frame(height: 1) }
                                }
                        }
                    }
                }
                .padding(.bottom, KGSpace.large)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 22)
        .padding(.horizontal, KGSpace.large)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KGColor.surface, in: UnevenRoundedRectangle(topLeadingRadius: KGRadius.card,
                                                                topTrailingRadius: KGRadius.card, style: .continuous))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(background: KGColor.surface) {
                KGButton(Text("Route hierher", bundle: .module), icon: .swap) { routeHere() }
                    .accessibilityIdentifier("routeHere")
            }
        }
        .task(id: coordinate) { load() }
    }

    private func walkMinutes(_ metres: Double) -> Int { max(1, Int((metres * 1.25 / 80).rounded(.up))) }

    private func load() {
        let now = Date.now
        stops = services.transit.stations(near: coordinate, within: 800, limit: 3).map { station, metres in
            (station, metres, (try? services.transit.departures(at: station.id, from: now, limit: 1))?.first)
        }
    }

    private func routeHere() {
        let destination = Endpoint(name: target.name, coordinate: coordinate)
        let start = services.here ?? Endpoint(name: String(localized: "Altstadt", bundle: .module),
                                              coordinate: MapRegion.center)
        services.updateUser { try $0.addRecent(target) }
        services.router.open(.routes(PlanQuery(from: start, to: destination)))
    }
}

/// "Bahnhof · 200 m · [5] 3 Min." (screen 15).
private struct NearbyStopRow: View {
    let station: Station
    let metres: Double
    let next: Departure?

    var body: some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(.bus, size: 18).foregroundStyle(KGColor.white)
                .frame(width: 36, height: 36)
                .background(KGColor.coral, in: .kgRounded(11))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: station.shortName).kgFont(.body.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink)
                Text(verbatim: Measurement(value: metres.rounded(), unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road)))
                    .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let next {
                KGLineBadge(next.line.name, size: .small)
                KGMinutes(next.expected, now: .now, isLive: next.status.isLive)
            }
        }
        .frame(minHeight: 60)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
