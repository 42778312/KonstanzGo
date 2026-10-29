import KGCore
import KGDesign
import SwiftUI

/// What the map's sheet shows: "In deiner Nähe" with the nearest stop, more stops when pulled up, or the stop
/// tapped on the map. Covers the states of S4.7: no location, not in Konstanz, loading, nothing running.
struct NearbySheetContent: View {
    let nearby: NearbyModel
    let location: LocationModel
    let isLarge: Bool
    let bottomPadding: CGFloat
    let onClose: () -> Void
    let onShowAll: () -> Void
    let onOpenStop: (Station) -> Void
    let onAllowLocation: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                if let selected = nearby.selected {
                    header(Text(verbatim: selected.station.shortName)) {
                        KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain,
                                          action: onClose)
                    }
                    Button { onOpenStop(selected.station) } label: { departureList(selected) }
                        .buttonStyle(KGPressStyle())
                        .accessibilityHint(Text("Öffnet die Haltestelle", bundle: .module))
                } else {
                    header(Text("In deiner Nähe", bundle: .module)) {
                        if !isLarge, nearby.stops.count > 1 {
                            KGTextButton(Text("Alle", bundle: .module), action: onShowAll)
                        }
                    }
                    locationNotice
                    if nearby.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    } else if nearby.stops.isEmpty {
                        KGEmptyState(.sleepy, title: Text("Keine Haltestelle in der Nähe", bundle: .module),
                                     message: Text("Hier fährt im Umkreis von 1,5 km kein Bus.", bundle: .module))
                    } else {
                        ForEach(isLarge ? nearby.stops : Array(nearby.stops.prefix(1))) { stop in
                            Button { onOpenStop(stop.station) } label: { card(stop, rows: 3) }
                                .buttonStyle(KGPressStyle())
                                .accessibilityHint(Text("Öffnet die Haltestelle", bundle: .module))
                        }
                    }
                }
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.bottom, bottomPadding + KGSpace.large)
        }
        .scrollDisabled(!isLarge)
        .scrollIndicators(.hidden)
    }

    private func header<Trailing: View>(_ title: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            title.kgFont(.title).foregroundStyle(KGColor.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: KGSpace.small)
            trailing()
        }
        .padding(.horizontal, KGSpace.xxs)
    }

    /// The tapped stop: its name is the sheet's title, so the card shows only the walk and the departures.
    @ViewBuilder private func departureList(_ stop: NearbyModel.Stop) -> some View {
        if stop.departures.isEmpty {
            NothingRunningCard(name: stop.station.shortName, walkMinutes: stop.walkMinutes)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if location.coordinate != nil {
                    KGWalkChip(minutes: stop.walkMinutes).padding(.bottom, KGSpace.xxs)
                }
                ForEach(Array(stop.departures.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(KGColor.line).frame(height: 1) }
                    KGDepartureRow(line: item.line, destination: item.destination, platform: item.platform,
                                   departure: item.departure, now: nearby.now, isLive: item.isLive, style: .large)
                }
            }
            .padding(.horizontal, KGSpace.mediumLarge)
            .padding(.vertical, KGSpace.small)
            .background(KGColor.card, in: .kgRounded(KGRadius.card))
        }
    }

    @ViewBuilder private func card(_ stop: NearbyModel.Stop, rows: Int) -> some View {
        if stop.departures.isEmpty {
            NothingRunningCard(name: stop.station.shortName, walkMinutes: stop.walkMinutes)
        } else {
            KGStopCard(name: stop.station.shortName,
                       walkMinutes: location.coordinate == nil ? nil : stop.walkMinutes,
                       departures: Array(stop.departures.prefix(rows)), now: nearby.now)
        }
    }

    /// Without the user's position the sheet shows the old town's stops and says so (S4.7).
    @ViewBuilder private var locationNotice: some View {
        switch location.access {
        case .allowed:
            if let point = location.coordinate, !MapRegion.contains(point) {
                notice(Text("Du bist gerade nicht in Konstanz. Hier sind Haltestellen in der Altstadt.",
                            bundle: .module), action: nil)
            }
        case .unknown:
            notice(Text("Erlaube deinen Standort, dann zeige ich dir die nächste Haltestelle.", bundle: .module),
                   action: Text("Standort erlauben", bundle: .module))
        case .denied:
            notice(Text("Ohne Standort zeige ich dir die Altstadt. Erlauben geht in den Einstellungen.",
                        bundle: .module), action: nil)
        }
    }

    private func notice(_ text: Text, action: Text?) -> some View {
        HStack(alignment: .center, spacing: KGSpace.medium) {
            KGIconView(.locate, size: 18)
                .foregroundStyle(KGColor.location)
                .frame(width: 36, height: 36)
                .background(KGColor.locationTint, in: .circle)
            VStack(alignment: .leading, spacing: KGSpace.xxs) {
                text.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action: onAllowLocation) {
                        action.kgFont(.callout).foregroundStyle(KGColor.location)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(KGSpace.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.card, in: .kgRounded(KGRadius.option))
    }
}

/// A stop with nothing leaving in the next hours: "Heute fährt hier nichts mehr" (S4.7).
private struct NothingRunningCard: View {
    let name: String
    let walkMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            HStack {
                Text(verbatim: name).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                Spacer()
                KGWalkChip(minutes: walkMinutes)
            }
            HStack(spacing: KGSpace.medium) {
                Seeri(.sleepy, detail: .compact).frame(width: 34, height: 36)
                Text("Heute fährt hier nichts mehr.", bundle: .module)
                    .kgFont(.body).foregroundStyle(KGColor.ink2)
            }
        }
        .padding(KGSpace.mediumLarge)
        .background(KGColor.card, in: .kgRounded(KGRadius.card))
        .accessibilityElement(children: .combine)
    }
}
