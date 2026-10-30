import KGCore
import KGDesign
import SwiftUI

/// Screen 07 (Karte), Apple Maps style: the offline map full screen and free to move, "Offline bereit" on
/// top, layers and location on the right, and one glass search bar at the bottom with Seeri. Search, a tapped
/// stop and a picked place each open in a sheet over the map (reworked after testing on a phone).
public struct MapScreen: View {
    let services: AppServices
    /// How far the search bar sits above the screen's bottom edge.
    let bottomBar: CGFloat
    let onReplayOnboarding: () -> Void
    @State var map = MapModel()
    @State private var sheet: MapSheet?
    /// Counts long presses, for the haptic tap when a pin drops.
    @State private var drops = 0
    @State private var touring = false
    /// When the last sheet closed: a new one can only open once its closing animation is over.
    @State private var closedAt = Date.distantPast
    /// The search was opened with the microphone: listen instead of typing.
    @State private var listens = false
    /// How far the stop or place sheet is open; a tap on the map folds it to a bar.
    @State private var detent = FoldingSheet<EmptyView>.half
    @State private var height: CGFloat = 800
    @State private var showsLayers = false
    @State private var toast: Text?
    @AppStorage("map.showsStops") private var showsStops = true
    @AppStorage("map.showsVehicles") var showsVehicles = true
    /// Buses and trains where the timetable puts them now (offline, no live feed).
    @State var vehicles: [VehiclePosition] = []

    public init(services: AppServices, bottomBar: CGFloat, onReplayOnboarding: @escaping () -> Void = {}) {
        self.services = services
        self.bottomBar = bottomBar
        self.onReplayOnboarding = onReplayOnboarding
    }

    private var transit: TransitService { services.transit }
    private var location: LocationModel { services.location }
    /// The folded stop or place bar, from the screen's bottom edge.
    private static let foldedSpace: CGFloat = 100
    /// The search bar, from the screen's bottom edge.
    private var barSpace: CGFloat { bottomBar + Self.searchBarHeight }
    /// A bit taller than the design's 56 after testing on a phone.
    private static let searchBarHeight: CGFloat = 66

    public var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            OfflinePill(info: transit.timetableInfo)
                .padding(.horizontal, KGSpace.screen)
                .padding(.top, KGSpace.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "© OpenStreetMap")
                .kgFont(.caption.weighted(KGFont.regular).sized(10))
                .foregroundStyle(KGColor.ink3)
                .padding(.horizontal, KGSpace.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, barSpace + KGSpace.xs)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            controls
                .padding(.trailing, KGSpace.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, (sheet == nil ? barSpace : Self.foldedSpace) + KGSpace.medium)
                .ignoresSafeArea(edges: .bottom)
            // While a stop or place is open its sheet (or folded bar) takes the bottom.
            if sheet == nil {
                searchBar
                    .padding(.horizontal, KGSpace.screen)
                    .padding(.bottom, bottomBar)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
            if let toast {
                KGToast(toast)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, barSpace + KGSpace.large)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlayPreferenceValue(TourAnchors.self) { anchors in
            if touring {
                SeeriTour(anchors: anchors) { withAnimation(.easeOut(duration: 0.3)) { touring = false } }
            }
        }
        .onChange(of: services.wantsTour, initial: true) { _, wants in
            guard wants else { return }
            services.wantsTour = false
            sheet = nil
            withAnimation(.easeOut(duration: 0.3)) { touring = true }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .sensoryFeedback(.impact(weight: .medium), trigger: drops)
        .sheet(item: presented) { sheet in sheetContent(sheet) }
        .sheet(isPresented: $showsLayers) { LayersSheet(showsStops: $showsStops, showsVehicles: $showsVehicles) }
        .task { await moveVehicles() }
        .onAppear(perform: appear)
        .onChange(of: location.coordinate) { old, point in
            map.userLocation = point
            // The first fix: look at where the user is.
            if old == nil, let point, MapRegion.contains(point), sheet == nil {
                map.move(CameraMove(center: point, zoom: MapRegion.userZoom))
            }
        }
        .onChange(of: showsStops) { _, show in map.stations = show ? transit.stations : [] }
        .onChange(of: sheet, initial: true) { _, new in sheetChanged(new) }
        .onChange(of: detent) { _, new in
            if sheet != nil, sheet != .search, sheet != .menu {
                map.insets.bottom = new == FoldingSheet<EmptyView>.folded ? Self.foldedSpace : height * 0.5
            }
        }
        .onChange(of: services.router.homeCount) { _, _ in sheet = nil }
        // Saved stops and places, widget links and departures open here, in the map's own sheet.
        .onChange(of: services.sheetRequest) { _, request in
            guard let request else { return }
            services.sheetRequest = nil
            sheet = request
        }
        .onChange(of: sheet) { _, new in services.showsMenu = new == .menu }
        .onChange(of: services.showsMenu) { _, shows in
            if !shows, sheet == .menu { sheet = nil }
        }
        .onChange(of: services.wantsSearch) { _, wants in
            if wants {
                services.wantsSearch = false
                sheet = .search
            }
        }
    }

    /// The sheet hides while a screen is pushed over the map and comes back with the map.
    private var presented: Binding<MapSheet?> {
        Binding(get: { services.router.path.isEmpty ? sheet : nil },
                set: { if services.router.path.isEmpty { sheet = $0 } })
    }

    // MARK: Parts

    @ViewBuilder private var mapLayer: some View {
        ZStack(alignment: .topLeading) {
            #if canImport(MapLibre) && canImport(UIKit)
            KGMapView(data: services.data, model: map)
            #else
            KGColor.mapLand
            #endif
            ForEach(vehicles) { vehicle in
                if let point = map.pinPoints[Self.pinID(vehicle)] {
                    KGVehicleMarker(line: vehicle.line.name, isTrain: vehicle.line.mode == .train,
                                    isKreuzlingen: vehicle.line.isYellowBus, heading: .degrees(vehicle.heading))
                        .position(point)
                        .allowsHitTesting(false)
                }
            }
            if let point = map.userPoint {
                KGUserDot(heading: location.heading.map { .degrees($0) })
                    .position(point)
                    .allowsHitTesting(false)
            }
            if let point = map.selectedPoint, map.selectedStation != nil {
                KGStopMarker("", isSelected: true, showsName: false)
                    .position(point)
                    .allowsHitTesting(false)
            }
            if let point = map.pinPoints["place"], let pinned = map.pins.first(where: { $0.id == "place" }) {
                DroppedPin()
                    .id(pinned.coordinate)  // a new drop plays again
                    .position(point)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    /// One glass bar: magnifier and "Wohin möchtest du?" open the search, the microphone opens it listening,
    /// Seeri at the end opens the menu.
    private var searchBar: some View {
        HStack(spacing: KGSpace.xs) {
            Button {
                listens = false
                open(.search)
            } label: {
                HStack(spacing: KGSpace.medium) {
                    KGIconView(.search, size: 24).foregroundStyle(KGColor.ink)
                    Text("Wohin möchtest du?", bundle: .module).kgFont(.bodyMedium.sized(19)).foregroundStyle(KGColor.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, KGSpace.large)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Wohin möchtest du?", bundle: .module))
            .accessibilityHint(Text("Öffnet die Suche", bundle: .module))
            .accessibilityIdentifier("mapSearch")
            .tourSpot(.search)
            Button {
                listens = true
                open(.search)
            } label: {
                KGIconView(.mic, size: 23).foregroundStyle(KGColor.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Per Sprache suchen", bundle: .module))
            .accessibilityIdentifier("mapVoiceSearch")
            .tourSpot(.mic)
            Button { open(.menu) } label: {
                SeeriAlive(.happy, detail: .compact)
                    .frame(width: 46, height: 50)
                    .frame(width: 54, height: 54)
                    .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Mehr", bundle: .module))
            .accessibilityHint(Text("Favoriten und Einstellungen", bundle: .module))
            .accessibilityIdentifier("seeriMenu")
            .tourSpot(.seeri)
            .padding(.trailing, KGSpace.xs)
        }
        .frame(height: Self.searchBarHeight)
        .kgGlass(in: Capsule())
        .kgShadow(.search, in: Capsule())
    }

    /// Layers and my location, one glass column.
    private var controls: some View {
        VStack(spacing: 0) {
            controlButton(.layers, label: Text("Kartenebenen", bundle: .module), tint: KGColor.ink) {
                showsLayers = true
            }
            Rectangle().fill(KGColor.line).frame(width: 26, height: 1)
            controlButton(.locate, label: Text("Mein Standort", bundle: .module), tint: KGColor.location) {
                locate()
            }
        }
        .kgGlass(in: Capsule())
        .kgShadow(.floating, in: Capsule())
        .tourSpot(.controls)
    }

    private func controlButton(_ icon: KGIcon, label: Text, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KGIconView(icon, size: 21).foregroundStyle(tint)
                .frame(width: KGSize.mapButton, height: KGSize.mapButton)
                .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder private func sheetContent(_ sheet: MapSheet) -> some View {
        switch sheet {
        case .search:
            MapSearchSheet(services: services, listens: listens) { pick($0) }
        case .menu:
            FoldingSheet(detent: $detent, title: String(localized: "Mehr", bundle: .module), onClose: { self.sheet = nil }) {
                MoreScreen(services: services, onReplayOnboarding: onReplayOnboarding)
            }
            .presentationBackground(.thinMaterial)
        case let .station(id):
            if let station = transit.station(id: id) {
                FoldingSheet(detent: $detent, title: station.shortName, onClose: { self.sheet = nil }) {
                    StationPanel(services: services, station: station) { self.sheet = nil }
                        .padding(.top, KGSpace.large)
                }
            }
        case let .place(target):
            FoldingSheet(detent: $detent, title: target.name, onClose: { self.sheet = nil }) {
                PlaceSheet(services: services, target: target) { self.sheet = nil }
            }
        case let .trip(tripID, day, fromStation):
            if let ride = TripScreen.ride(services: services, tripID: tripID, day: day, fromStation: fromStation) {
                FoldingSheet(detent: $detent, title: "\(ride.line.name) · \(ride.headsign)",
                             onClose: { self.sheet = nil }) {
                    TripPanel(services: services, ride: ride, onBack: { self.sheet = .station(fromStation) },
                              onClose: { self.sheet = nil })
                }
            }
        }
    }

    // MARK: Actions

    private func appear() {
        if services.wantsSearch {
            services.wantsSearch = false
            sheet = .search
        }
        map.stations = showsStops ? transit.stations : []
        map.onSelectStation = { station in
            services.updateUser { try $0.addRecent(.station(id: station.id, name: station.shortName,
                                                           coordinate: station.coordinate)) }
            sheet = .station(station.id)
        }
        // A long press drops the target: the connections there from where the user is, straight away.
        map.onLongPress = { point in
            drops += 1
            let street = services.transit.whereabouts(at: point).street
            sheet = .place(.point(name: street ?? String(localized: "Markierter Ort", bundle: .module), coordinate: point))
        }
        map.onTapMap = {
            switch sheet {
            case .station, .place, .trip, .menu:
                withAnimation(KGMotion.sheet) { detent = FoldingSheet<EmptyView>.folded }
            default: break
            }
        }
        // The voice search's recognizer loads in the background, so the microphone listens at once.
        VoiceSearch.warmUp(hints: transit.stations.map(\.shortName))
        // Ask once if nobody has yet (e.g. "Später" in onboarding), so the blue dot can show.
        if location.access == .unknown { location.requestAccess() }
        location.start()
        map.userLocation = location.coordinate
        if let point = location.coordinate, MapRegion.contains(point), sheet == nil {
            map.move(CameraMove(center: point, zoom: MapRegion.userZoom, animated: false))
        }
    }

    /// From the search: anything picked, a stop too, becomes the target ("Nach") with the connections there.
    /// A stop's departures open from tapping it on the map.
    private func pick(_ target: SavedTarget) {
        services.updateUser { try $0.addRecent(target) }
        sheet = .place(target)
    }

    /// Opens search or the menu; right after another sheet closed, once that has finished closing (iOS drops
    /// a sheet presented during the previous one's dismissal).
    private func open(_ new: MapSheet) {
        let wait = 0.45 - Date.now.timeIntervalSince(closedAt)
        guard wait > 0 else { return sheet = new }
        Task {
            try? await Task.sleep(for: .seconds(wait))
            if sheet == nil { sheet = new }
        }
    }

    /// Marks what the sheet is about on the map and keeps it in view above the sheet.
    private func sheetChanged(_ new: MapSheet?) {
        let half = height * 0.5
        detent = FoldingSheet<EmptyView>.half
        switch new {
        case let .station(id):
            map.pins = []
            map.lines = []
            withAnimation(KGMotion.sheet) { map.selectedStationID = id }
            map.insets.bottom = half
            if let station = transit.station(id: id) {
                map.move(CameraMove(center: station.coordinate, zoom: max(MapRegion.userZoom, 16)))
            }
        case let .place(target):
            map.selectedStationID = nil
            map.lines = []
            map.pins = [MapPin(id: "place", coordinate: target.coordinate)]
            map.insets.bottom = half
            map.move(CameraMove(center: target.coordinate, zoom: 16))
        case let .trip(tripID, day, fromStation):
            map.selectedStationID = nil
            if let ride = TripScreen.ride(services: services, tripID: tripID, day: day, fromStation: fromStation) {
                map.lines = Journey(legs: [.ride(ride)]).mapLines
                map.pins = [MapPin(id: "place", coordinate: ride.alighting.platform.coordinate)]
                map.insets.bottom = half
                map.move(.fitting(ride.stops.map(\.platform.coordinate)))
            }
        case .search, .menu:
            break
        case nil:
            closedAt = .now
            withAnimation(KGMotion.sheet) { map.selectedStationID = nil }
            map.pins = []
            map.lines = []
            // Nothing open: the user's position goes in the middle of the screen; the search bar floats over
            // the map's bottom edge.
            map.insets.bottom = 0
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

    private func show(_ message: Text) {
        withAnimation(KGMotion.sheet) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}


// MARK: - Moving buses and trains

extension MapScreen {
    static func pinID(_ vehicle: VehiclePosition) -> String { "vehicle-\(vehicle.tripID)" }

    /// Four times a second: where every bus and train is by the timetable, so they glide along their routes.
    /// Paused while a screen is open over the map.
    func moveVehicles() async {
        let tracker = services.transit.tracker
        while !Task.isCancelled {
            if showsVehicles, services.router.path.isEmpty {
                let now = Date.now
                let found = await Task.detached(priority: .utility) { (try? tracker.positions(at: now)) ?? [] }.value
                vehicles = found.filter { MapRegion.contains($0.coordinate) }
            } else if !showsVehicles, !vehicles.isEmpty {
                vehicles = []
            }
            map.pins = map.pins.filter { !$0.id.hasPrefix("vehicle-") }
                + vehicles.map { MapPin(id: Self.pinID($0), coordinate: $0.coordinate) }
            try? await Task.sleep(for: .milliseconds(250))
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

/// The layers menu (S4.4): stops and vehicles on or off. The app is always dark.
private struct LayersSheet: View {
    @Binding var showsStops: Bool
    @Binding var showsVehicles: Bool
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
            KGToggleRow(Text("Busse & Züge", bundle: .module), isOn: $showsVehicles)
            Spacer(minLength: 0)
        }
        .padding(KGSpace.large)
        .presentationDetents([.height(250)])
        .presentationCornerRadius(KGRadius.card)
    }
}

/// The pin of a picked place or a long press, drawn with its tip on the point: it falls in from above and
/// bounces, its shadow grows as it lands, and a ring spreads from the spot.
private struct DroppedPin: View {
    @State private var landed = false
    @State private var ripple = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(KGColor.coral, lineWidth: 2)
                .frame(width: 20, height: 20)
                .scaleEffect(ripple ? 3.2 : 0.3)
                .opacity(ripple ? 0 : 0.9)
            Ellipse().fill(.black.opacity(0.35))
                .frame(width: landed ? 16 : 6, height: landed ? 6 : 3)
            KGIconView(.pinFilled, size: 40).foregroundStyle(KGColor.coral)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .scaleEffect(landed ? 1 : 0.7, anchor: .bottom)
                .offset(y: landed ? -20 : -80)
                .opacity(landed ? 1 : 0)
        }
        .onAppear {
            guard !reduceMotion else {
                landed = true
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { landed = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.25)) { ripple = true }
        }
    }
}

/// What the sheet over the map shows. Every list opened from the map is one of these, so all of them fold to
/// a bar on a map tap, swipe between half and full height, and close the same way.
enum MapSheet: Identifiable, Hashable {
    case search
    /// Mehr (with Favoriten), from Seeri.
    case menu
    case station(Int)
    case place(SavedTarget)
    /// A departure picked at a stop: the bus's stops ahead.
    case trip(tripID: Int, day: ServiceDay, fromStation: Int)

    var id: String {
        switch self {
        case .search: "search"
        case .menu: "menu"
        case let .station(id): "station-\(id)"
        case let .place(target): "place-\(target.name)-\(target.coordinate.latitude)-\(target.coordinate.longitude)"
        case let .trip(tripID, day, station): "trip-\(tripID)-\(day)-\(station)"
        }
    }
}
