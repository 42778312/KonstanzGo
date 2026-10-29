import KGCore
import KGDesign
import SwiftUI

/// Screen 07 (Karte) and its dark version 28: the offline map full screen, the search bar and "Offline bereit"
/// on top, layers and location buttons above the sheet, and "In deiner Nähe" in the sheet (plan S4).
public struct MapScreen: View {
    let services: AppServices
    /// Room the floating tab bar takes at the bottom.
    let bottomBar: CGFloat
    @State private var map = MapModel()
    @State private var nearby: NearbyModel
    @State private var detent = SheetDetent.medium
    @State private var sheetHeight: CGFloat = 374
    @State private var showsLayers = false
    @State private var toast: Text?
    @AppStorage("map.showsStops") private var showsStops = true
    @Environment(\.scenePhase) private var scenePhase

    public init(services: AppServices, bottomBar: CGFloat) {
        self.services = services
        self.bottomBar = bottomBar
        _nearby = State(initialValue: NearbyModel(transit: services.transit))
    }

    private var transit: TransitService { services.transit }
    private var location: LocationModel { services.location }

    public var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            topBar
            MapSheet(detent: $detent, height: $sheetHeight, showsSeeri: nearby.selected == nil) {
                NearbySheetContent(nearby: nearby, location: location, isLarge: detent == .large,
                                   bottomPadding: bottomBar) {
                    deselect()
                } onShowAll: {
                    detent = .large
                } onOpenStop: { station in
                    services.router.open(.stop(station.id))
                } onAllowLocation: {
                    location.requestAccess()
                }
            }
            Text(verbatim: "© OpenStreetMap")
                .kgFont(.caption.weighted(KGFont.regular).sized(10))
                .foregroundStyle(KGColor.ink3)
                .padding(.horizontal, KGSpace.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, sheetHeight + KGSpace.xxs)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            KGMapControls(isFollowing: false) {
                showsLayers = true
            } onLocate: {
                locate()
            }
            .padding(.trailing, KGSpace.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            // 62 pt above the sheet as in screen 07, which leaves room for Seeri peeking over its edge.
            .padding(.bottom, sheetHeight + 62)
            .opacity(detent == .large ? 0 : 1)
            .ignoresSafeArea(edges: .bottom)
            if let toast {
                KGToast(toast)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, sheetHeight + KGSpace.large)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .sheet(isPresented: $showsLayers) { LayersSheet(showsStops: $showsStops) }
        .onAppear(perform: appear)
        .onDisappear { location.stop() }
        .onChange(of: location.coordinate) { old, point in
            map.userLocation = point
            nearby.update(around: anchor)
            // The first fix: look at where the user is.
            if old == nil, let point, MapRegion.contains(point) {
                map.move(CameraMove(center: point, zoom: MapRegion.userZoom))
            }
        }
        .onChange(of: location.access) { _, _ in nearby.update(around: anchor) }
        .onChange(of: showsStops) { _, show in map.stations = show ? transit.stations : [] }
        .onChange(of: sheetHeight, initial: true) { _, height in map.insets.bottom = height }
        .task(id: scenePhase) {
            // "In deiner Nähe" refreshes every 30 s while on screen (S4.5).
            while scenePhase == .active, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                nearby.refresh()
            }
        }
    }

    // MARK: Parts

    @ViewBuilder private var mapLayer: some View {
        ZStack(alignment: .topLeading) {
            #if canImport(MapLibre) && canImport(UIKit)
            KGMapView(data: services.data, model: map)
            #else
            KGColor.mapLand
            #endif
            if let point = map.userPoint {
                KGUserDot(heading: location.heading.map { .degrees($0) })
                    .position(point)
                    .allowsHitTesting(false)
            }
            if let point = map.selectedPoint, let station = map.selectedStation {
                KGStopMarker(station.shortName, isSelected: true, showsName: false)
                    .position(point)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: KGSpace.medium) {
            KGMapSearchBar {
                services.router.open(.search)
            }
            .accessibilityIdentifier("mapSearch")
            OfflinePill(info: transit.timetableInfo)
        }
        .padding(.horizontal, KGSpace.screen)
        .padding(.top, KGSpace.mediumLarge)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { map.insets.top = proxy.frame(in: .global).maxY }
        })
    }

    // MARK: Actions

    /// Where "nearby" is measured from: the user, or the old town without a usable position (S4.7).
    private var anchor: Coordinate {
        if let point = location.coordinate, MapRegion.contains(point) { return point }
        return MapRegion.center
    }

    private func appear() {
        map.stations = showsStops ? transit.stations : []
        map.onSelectStation = { select($0) }
        map.onLongPress = { services.router.open(.pin($0)) }
        location.start()
        nearby.update(around: anchor)
        if let point = location.coordinate, MapRegion.contains(point) {
            map.move(CameraMove(center: point, zoom: MapRegion.userZoom, animated: false))
        }
    }

    private func locate() {
        switch location.access {
        case .allowed:
            guard let point = location.coordinate else { return }
            if MapRegion.contains(point) {
                map.move(CameraMove(center: point, zoom: MapRegion.userZoom))
            } else {
                show(Text("Du bist gerade nicht in Konstanz.", bundle: .module))
            }
        case .unknown:
            location.requestAccess()
        case .denied:
            show(Text("Standort ist in den Einstellungen aus.", bundle: .module))
        }
    }

    private func select(_ station: Station) {
        map.selectedStationID = station.id
        nearby.select(station)
        map.move(CameraMove(center: station.coordinate, zoom: max(MapRegion.userZoom, 16)))
        if detent == .peek { detent = .medium }
    }

    private func deselect() {
        map.selectedStationID = nil
        nearby.select(nil)
    }

    private func show(_ message: Text) {
        withAnimation(KGMotion.sheet) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}

/// "Offline bereit", orange "Fahrplan endet bald" in the last 14 days of the timetable (S4.2).
private struct OfflinePill: View {
    let info: TimetableInfo?

    var body: some View {
        if let end = info.flatMap({ Calendar.konstanz.date(from: $0.validUntil) }),
           end.timeIntervalSinceNow < 14 * 24 * 3600 {
            KGStatusPill(Text("Fahrplan endet bald", bundle: .module), isWarning: true)
        } else {
            KGStatusPill(Text("Offline bereit", bundle: .module))
        }
    }
}

/// The layers menu (S4.4): stops on or off, and the map's look.
private struct LayersSheet: View {
    @Binding var showsStops: Bool
    @AppStorage("appearance") private var appearance = Appearance.automatic.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.large) {
            HStack {
                Text("Kartenebenen", bundle: .module).kgFont(.title).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain) { dismiss() }
            }
            KGToggleRow(Text("Haltestellen", bundle: .module), isOn: $showsStops)
            VStack(alignment: .leading, spacing: KGSpace.small) {
                KGSectionHeader(Text("Darstellung", bundle: .module))
                KGSegmentedControl(selection: $appearance, options: Appearance.allCases.map { ($0.rawValue, $0.title) })
            }
            Spacer(minLength: 0)
        }
        .padding(KGSpace.large)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(KGRadius.card)
    }
}

/// The app's look: follow the system, or always light or dark (Mehr › Darstellung, layers menu).
public enum Appearance: String, CaseIterable, Sendable {
    case automatic, light, dark

    var title: Text {
        switch self {
        case .automatic: Text("Automatisch", bundle: .module)
        case .light: Text("Hell", bundle: .module)
        case .dark: Text("Dunkel", bundle: .module)
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
