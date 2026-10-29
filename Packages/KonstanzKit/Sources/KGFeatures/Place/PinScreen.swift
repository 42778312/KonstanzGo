import KGCore
import KGDesign
import SwiftUI

/// Screen 16 (Pin gesetzt): a pin on the map that can be moved by dragging the map under it; the street,
/// the coordinates, the nearest stop; "Als Zuhause", "Merken", "Route hierher" (plan S7.2).
struct PinScreen: View {
    let services: AppServices
    @State private var point: Coordinate
    @State private var model = MapModel()
    @State private var dropped = false
    @State private var whereabouts: Whereabouts?
    @State private var savedHome = false

    init(services: AppServices, point: Coordinate) {
        self.services = services
        _point = State(initialValue: point)
    }

    var body: some View {
        ZStack(alignment: .top) {
            #if canImport(MapLibre) && canImport(UIKit)
            KGMapView(data: services.data, model: model)
                .ignoresSafeArea()
            #else
            KGColor.mapLand.ignoresSafeArea()
            #endif
            pin
            topBar
            sheet
        }
        .onAppear {
            model.stations = services.transit.stations
            model.insets = MapInsets(top: 120, bottom: 340)
            model.move(CameraMove(center: point, zoom: 17, animated: false))
            lookUp()
            withAnimation(KGMotion.pop.delay(0.2)) { dropped = true }
        }
        .onChange(of: model.centerCoordinate) { _, center in
            guard let center else { return }
            point = center
            lookUp()
        }
        .sensoryFeedback(KGHaptic.drop, trigger: dropped)
    }

    /// The pin stays in the middle of the visible map; the map moves under it.
    private var pin: some View {
        GeometryReader { proxy in
            let visible = proxy.size.height + proxy.safeAreaInsets.top - 340 + 120
            VStack(spacing: 0) {
                KGIconView(.pinFilled, size: 44).foregroundStyle(KGColor.coral)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
                Ellipse().fill(Color.black.opacity(0.18)).frame(width: 22, height: 8)
            }
            .offset(y: dropped ? 0 : -60)
            .opacity(dropped ? 1 : 0)
            .position(x: proxy.size.width / 2, y: visible / 2 - proxy.safeAreaInsets.top - 18)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack(spacing: KGSpace.xs) {
            Button { services.router.back() } label: {
                KGIconView(.back, size: 22).foregroundStyle(KGColor.ink)
                    .frame(width: KGSize.touch, height: KGSize.touch)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Zurück", bundle: .module))
            Text("Pin gesetzt", bundle: .module).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
            Spacer()
            Text("Karte verschieben", bundle: .module).kgFont(.caption.weighted(KGFont.bold))
                .foregroundStyle(KGColor.ink2)
        }
        .padding(.leading, KGSpace.xxs)
        .padding(.trailing, KGSpace.screen)
        .frame(minHeight: KGSize.searchBar)
        .background(KGColor.glassFill, in: .kgRounded(KGRadius.search))
        .kgShadow(.search, in: .kgRounded(KGRadius.search))
        .padding(.horizontal, KGSpace.screen)
        .padding(.top, 11)
    }

    private var sheet: some View {
        VStack {
            Spacer()
            KGSheetSurface {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Markierter Ort", bundle: .module).kgFont(.titleL.sized(26)).foregroundStyle(KGColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: [whereabouts?.street, whereabouts?.town].compactMap { $0 }.joined(separator: " · "))
                        .kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2).padding(.top, 2)
                    Text(verbatim: Self.degrees(point))
                        .kgFont(.caption.weighted(KGFont.regular)).monospacedDigit().foregroundStyle(KGColor.ink2)
                        .padding(.top, KGSpace.xxs)
                    if let station = whereabouts?.nearestStation {
                        Button { services.router.open(.stop(station.id)) } label: {
                            HStack(spacing: KGSpace.medium) {
                                KGIconView(.bus, size: 16).foregroundStyle(KGColor.white)
                                    .frame(width: 32, height: 32).background(KGColor.coral, in: .kgRounded(10))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: station.shortName).kgFont(.callout.weighted(KGFont.extraBold))
                                    Text("Nächste Haltestelle · \(whereabouts?.walkMinutes ?? 1) Min. zu Fuß",
                                         bundle: .module)
                                        .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                                }
                                .foregroundStyle(KGColor.ink)
                                Spacer()
                                KGIconView(.chevronRight, size: 14).foregroundStyle(KGColor.chevron)
                            }
                            .padding(.horizontal, KGSpace.mediumLarge)
                            .frame(minHeight: 56)
                            .background(KGColor.glassFill, in: .kgRounded(KGRadius.option))
                        }
                        .buttonStyle(KGPressStyle())
                        .padding(.top, KGSpace.mediumLarge)
                    }
                    HStack(spacing: KGSpace.compact) {
                        KGButton(savedHome ? Text("Zuhause ✓", bundle: .module) : Text("Als Zuhause", bundle: .module),
                                 icon: .home, kind: .outline) {
                            services.updateUser { try $0.setSlot(.home, to: target) }
                            withAnimation(KGMotion.pop) { savedHome = true }
                        }
                        KGButton(services.isFavorite(target) ? Text("Gemerkt", bundle: .module)
                                                             : Text("Merken", bundle: .module),
                                 icon: .star, kind: .outline) {
                            services.toggleFavorite(target)
                        }
                    }
                    .padding(.top, KGSpace.medium)
                    KGButton(Text("Route hierher", bundle: .module), icon: .swap) {
                        let start = services.here ?? Endpoint(name: String(localized: "Altstadt", bundle: .module),
                                                              coordinate: MapRegion.center)
                        services.router.open(.routes(PlanQuery(from: start, to: Endpoint(name: target.name,
                                                                                         coordinate: point))))
                    }
                    .padding(.top, KGSpace.large)
                }
                .padding(.horizontal, KGSpace.large)
                .padding(.bottom, KGSpace.large)
            }
            .frame(height: 340)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var target: SavedTarget {
        .point(name: whereabouts?.street ?? String(localized: "Markierter Ort", bundle: .module), coordinate: point)
    }

    private func lookUp() {
        whereabouts = services.transit.whereabouts(at: point)
    }

    /// "47,66° N · 9,18° O" in German, "47.66° N · 9.18° E" in English.
    static func degrees(_ point: Coordinate) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        return String(localized: "\(point.latitude.formatted(format))° N · \(point.longitude.formatted(format))° O",
                      bundle: .module)
    }
}
