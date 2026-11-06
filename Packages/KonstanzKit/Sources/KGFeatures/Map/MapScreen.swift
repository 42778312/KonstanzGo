import KGCore
import KGDesign
import SwiftUI

/// Screen 07 (Karte), Apple Maps style: the offline map full screen and free to move, the weather on
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
    /// When the last sheet closed: a new one can only open once its closing animation is over.
    @State private var closedAt = Date.distantPast
    /// The search was opened with the microphone: listen instead of typing.
    @State private var listens = false
    /// How far the stop or place sheet is open; a tap on the map folds it to a bar.
    @State private var detent = FoldingSheet<EmptyView>.half
    @State private var height: CGFloat = 800
    @State private var showsLayers = false
    @State private var toast: Text?
    /// Seeri is telling the user about a new notice.
    @State private var seeriSpeaks = false
    /// The notices the user has looked at; the siren flashes until then.
    @AppStorage("live.openedNotices") private var openedNotices = ""
    /// Redraws the open sheet once after it replaced another: iOS brings that one up at full height
    /// until its height is applied again.
    @State private var sheetRedraws = 0
    /// The Von, Nach and time chosen in the place sheet: it goes away while a route is open over the map, and
    /// comes back with them. A new sheet starts afresh.
    @State private var placeQuery: PlanQuery?
    /// The Jetzt card's height, for what sits above it.
    @State private var nowHeight: CGFloat = 0
    /// How far the search bar is being pulled up, towards the menu.
    @State private var barLift: CGFloat = 0
    @AppStorage("map.showsStops") private var showsStops = true
    @AppStorage("map.showsVehicles") var showsVehicles = true
    /// Only this line's buses on the map; empty for all.
    @AppStorage("map.onlyLine") var onlyLine = ""

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
    /// The Jetzt card and its gap, while it's there.
    private var nowSpace: CGFloat { nowHeight > 0 ? nowHeight + KGSpace.large : 0 }
    /// A bit taller than the design's 56 after testing on a phone.
    private static let searchBarHeight: CGFloat = 66

    public var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            // Keeps the clock readable over map labels.
            LinearGradient(colors: [KGColor.mapLand.opacity(0.85), KGColor.mapLand.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            StatusCorner(info: transit.timetableInfo, weather: services.weather)
                .padding(.horizontal, KGSpace.screen)
                .padding(.top, KGSpace.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "© OpenStreetMap")
                .kgFont(.caption.weighted(KGFont.regular).sized(10))
                .foregroundStyle(KGColor.ink3)
                .padding(.horizontal, KGSpace.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, barSpace + nowSpace + KGSpace.xs)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            controls
                .padding(.trailing, KGSpace.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, (sheet == nil ? barSpace + nowSpace : Self.foldedSpace) + KGSpace.medium)
                .ignoresSafeArea(edges: .bottom)
            // While a stop or place is open its sheet (or folded bar) takes the bottom.
            if sheet == nil {
                NowCard(services: services, onStop: { open(.station($0)) }, onHeight: { nowHeight = $0 })
                    .padding(.horizontal, KGSpace.screen)
                    .padding(.bottom, barSpace + KGSpace.large)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                noticesLayer
                searchBar
                    .padding(.horizontal, KGSpace.screen)
                    .padding(.bottom, bottomBar)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
            if let toast {
                KGToast(toast)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, barSpace + nowSpace + KGSpace.large)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .sensoryFeedback(.impact(weight: .medium), trigger: drops)
        .sheet(item: presented) { sheet in sheetContent(sheet) }
        .sheet(isPresented: $showsLayers) { layersSheet }
        .task { await moveVehicles() }
        .task { await followBuses() }
        .task { await services.live.keepFresh() }
        .onChange(of: services.live.closures.stations, initial: true) { _, closed in
            map.closedStations = closed.compactMap { transit.station(id: $0) }
        }
        .environment(\.stopClosures, services.live.closures)
        .onAppear(perform: appear)
        .onChange(of: location.heading, initial: true) { _, heading in map.userHeading = heading }
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
        // A sheet would hide the message, so it waits until the map is in view.
        .onChange(of: services.userMessage, initial: true) { _, _ in showUserMessage() }
        .onChange(of: sheet) { _, _ in showUserMessage() }
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
            MapOverlays(map: map)
        }
        .ignoresSafeArea()
    }

    private var layersSheet: some View {
        LayersSheet(showsStops: $showsStops, showsVehicles: $showsVehicles, onlyLine: $onlyLine,
                    lines: services.transit.store.lines.filter(\.isCity).map(\.name))
    }

    @ViewBuilder private func sheetContent(_ sheet: MapSheet) -> some View {
        let _ = sheetRedraws
        switch sheet {
        case .search:
            MapSearchSheet(services: services, listens: listens) { pick($0) }
        case .menu:
            FoldingSheet(detent: $detent, title: String(localized: "Einstellungen", bundle: .module), onClose: { self.sheet = nil }) {
                MoreScreen(services: services, onReplayOnboarding: onReplayOnboarding)
            }
            .kgGlassSheet()
        case let .station(id):
            if let station = transit.station(id: id) {
                FoldingSheet(detent: $detent, title: station.shortName, onClose: { self.sheet = nil }) {
                    StationPanel(services: services, station: station, onClose: { self.sheet = nil },
                                 onStation: { self.sheet = .station($0) })
                        .padding(.top, KGSpace.large)
                }
            }
        case .notices:
            NoticesPanel(services: services, onStation: { self.sheet = .station($0) }, onClose: { self.sheet = nil })
                .presentationDetents([FoldingSheet<EmptyView>.half, .large])
                .kgGlassSheet()
                .presentationDragIndicator(.visible)
        case let .place(target):
            FoldingSheet(detent: $detent, title: target.name, onClose: { self.sheet = nil }) {
                PlaceSheet(services: services, target: target, saved: placeQuery, onQuery: queryChanged) {
                    self.sheet = nil
                }
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
            case .station, .place, .trip:
                withAnimation(KGMotion.sheet) { detent = FoldingSheet<EmptyView>.folded }
            case .menu, .notices:
                // These aren't about a place on the map: looking at the map ends them.
                sheet = nil
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

    /// Remembers the place sheet's choices; a new "Nach" (or a swap) moves the pin and the map there.
    private func queryChanged(_ query: PlanQuery) {
        placeQuery = query
        guard map.pins.first(where: { $0.id == "place" })?.coordinate != query.to.coordinate else { return }
        map.pins = [MapPin(id: "place", coordinate: query.to.coordinate)]
        map.move(CameraMove(center: query.to.coordinate, zoom: MapRegion.destinationZoom))
    }

    /// Marks what the sheet is about on the map and keeps it in view above the sheet.
    private func sheetChanged(_ new: MapSheet?) {
        let half = height * 0.5
        detent = FoldingSheet<EmptyView>.half
        placeQuery = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            sheetRedraws &+= 1
        }
        switch new {
        case let .station(id):
            map.pins = []
            map.lines = []
            withAnimation(KGMotion.sheet) { map.selectedStationID = id }
            map.insets.bottom = half
            if let station = transit.station(id: id) {
                map.move(CameraMove(center: station.coordinate, zoom: MapRegion.destinationZoom))
            }
        case let .place(target):
            map.selectedStationID = nil
            map.lines = []
            map.pins = [MapPin(id: "place", coordinate: target.coordinate)]
            map.insets.bottom = half
            map.move(CameraMove(center: target.coordinate, zoom: MapRegion.destinationZoom))
        case let .trip(tripID, day, fromStation):
            map.selectedStationID = nil
            if let ride = TripScreen.ride(services: services, tripID: tripID, day: day, fromStation: fromStation) {
                map.lines = Journey(legs: [.ride(ride)]).mapLines
                map.pins = [MapPin(id: "place", coordinate: ride.alighting.platform.coordinate)]
                map.insets.bottom = half
                map.move(.fitting(ride.stops.map(\.platform.coordinate)))
            }
        case .search, .menu, .notices:
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

    private func showUserMessage() {
        guard sheet == nil, let message = services.userMessage else { return }
        services.userMessage = nil
        show(message)
    }

    private func show(_ message: Text) {
        withAnimation(KGMotion.sheet) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}


// MARK: - Controls

extension MapScreen {
    /// Seeri's message over the search bar, and the pill that stays while something's going on.
    fileprivate var noticesLayer: some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            SeeriNoticeBubble(services: services, isSpeaking: $seeriSpeaks, onOpen: openNotices)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KGSpace.screen)
        .padding(.bottom, barSpace + nowSpace + KGSpace.large + 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }

    /// Whether Seeri's police light flashes: there's a notice the user hasn't opened. Nil: nothing going on.
    private var sirenFlashing: Bool? {
        let active = services.live.active
        guard !active.isEmpty else { return nil }
        let opened = Set(openedNotices.split(separator: "\n").map(String.init))
        return active.contains { !opened.contains($0.seenKey) }
    }

    private func openNotices() {
        openedNotices = services.live.active.map(\.seenKey).joined(separator: "\n")
        open(.notices)
    }

    /// One glass bar: magnifier and "Wohin möchtest du?" open the search, the microphone opens it listening,
    /// Seeri at the end tells about notices. Pulled up by its handle (or anywhere), it opens the menu.
    fileprivate var searchBar: some View {
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
            Button(action: openNotices) {
                SeeriAlive(seeriSpeaks || sirenFlashing == true ? .excited : .happy, detail: .compact,
                           sirenFlashing: sirenFlashing)
                    .frame(width: 46, height: 50)
                    .scaleEffect(seeriSpeaks ? 1.12 : 1, anchor: .bottom)
                    .animation(KGMotion.pop, value: seeriSpeaks)
                    .frame(width: 54, height: 54)
                    .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Meldungen", bundle: .module))
            .accessibilityValue(services.live.active.isEmpty ? Text(verbatim: "") : Text(verbatim: "\(services.live.active.count)"))
            .accessibilityIdentifier("seeriMenu")
            .padding(.trailing, KGSpace.xs)
        }
        .frame(height: Self.searchBarHeight)
        .kgGlass(in: Capsule())
        .kgShadow(.search, in: Capsule())
        .overlay(alignment: .top) { moreHandle }
        .offset(y: barLift)
        .simultaneousGesture(pullUp)
    }

    /// The bar's handle, like a sheet's: says it can be pulled up. A tap works too.
    private var moreHandle: some View {
        Button { open(.menu) } label: {
            Capsule().fill(KGColor.ink2).frame(width: 38, height: 5)
                .frame(width: 96, height: 24, alignment: .center)
                .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .offset(y: -12)
        .accessibilityLabel(Text("Einstellungen", bundle: .module))
        .accessibilityHint(Text("Favoriten und Einstellungen", bundle: .module))
        .accessibilityIdentifier("moreHandle")
    }

    /// The bar follows the finger up with some resistance; far enough and the menu rises out of it.
    private var pullUp: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { drag in
                barLift = drag.translation.height < 0 ? -pow(-drag.translation.height, 0.8) : 0
            }
            .onEnded { drag in
                if drag.translation.height < -45 || drag.predictedEndTranslation.height < -140 { open(.menu) }
                withAnimation(KGMotion.pop) { barLift = 0 }
            }
    }

    /// Layers and my location, one glass column.
    fileprivate var controls: some View {
        VStack(spacing: 0) {
            controlButton(.more, label: Text("Einstellungen", bundle: .module), tint: KGColor.ink) { open(.menu) }
                .accessibilityIdentifier("settingsButton")
            Rectangle().fill(KGColor.line).frame(width: 26, height: 1)
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
}

// MARK: - Moving buses and trains

extension MapScreen {
    /// Reads a busy stop and the stops around where the user is looking, a few at a time and in turn, so the buses in
    /// view follow their real delays and a stop opened next already has its real times.
    func followBuses() async {
        let transit = services.transit, live = services.live
        var round = 0
        while !Task.isCancelled {
            if showsVehicles, services.router.path.isEmpty, services.isActive {
                let around = inView(transit)
                let turn = around.isEmpty ? [] : (0..<min(Self.stopsPerRound, around.count)).map {
                    around[(round * Self.stopsPerRound + $0) % around.count]
                }
                await live.warm(stations: [Self.hubs[round % Self.hubs.count]] + turn)
                round += 1
            }
            try? await Task.sleep(for: .seconds(services.config.stopReadSeconds))
        }
    }

    /// The stops nearest the middle of the map, or the user before the map has moved.
    private func inView(_ transit: OfflineTransit) -> [Int] {
        guard let middle = map.centerCoordinate ?? location.coordinate else { return [] }
        return transit.stations(near: middle, within: 1_500, limit: 12).map(\.0.id)
    }

    private static let stopsPerRound = 3

    /// Konstanz Bahnhof and Sternenplatz.
    private static let hubs = [15, 99]

    /// Eight times a second: where every bus and train is by the timetable, so they glide along their routes and
    /// swing through corners, with their indicators going before a turn. Paused while a screen is open over the map.
    func moveVehicles() async {
        let tracker = services.transit.tracker
        var motion = VehicleMotion()
        var glide = DelayGlide()
        var last = ContinuousClock.now
        var lastDelays = ContinuousClock.now
        while !Task.isCancelled {
            if showsVehicles, services.router.path.isEmpty, services.isActive {
                let now = Date.now
                let delays = glide.advance(services.live.tripDelays, after: (ContinuousClock.now - lastDelays) / .seconds(1))
                lastDelays = ContinuousClock.now
                let cancelled = services.live.cancelledTrips
                let found = await Task.detached(priority: .utility) {
                    (try? tracker.positions(at: now, delays: delays, cancelled: cancelled)) ?? []
                }.value
                let only = onlyLine
                let running = found.filter { vehicle in
                    MapRegion.contains(vehicle.coordinate)
                        && (only.isEmpty || vehicle.line.name == only || Line.feedNumber(vehicle.line.name) == only)
                }
                let tick = ContinuousClock.now
                let headings = motion.advance(Dictionary(running.map { ($0.tripID, $0.heading) }) { first, _ in first },
                                              after: (tick - last) / .seconds(1))
                last = tick
                let lit = Int(now.timeIntervalSince1970 * 2.8) % 2 == 0
                map.vehicles = running.map { vehicle in
                    MapVehicle(id: vehicle.tripID, line: vehicle.line.name, coordinate: vehicle.coordinate,
                               heading: headings[vehicle.tripID] ?? vehicle.heading,
                               look: .vehicle(isTrain: vehicle.line.mode == .train, isYellow: vehicle.line.isYellowBus,
                                              isLive: !vehicle.isEstimated),
                               turn: lit ? vehicle.signal : .none)
                }
            } else if !showsVehicles, !map.vehicles.isEmpty {
                map.vehicles = []
            }
            try? await Task.sleep(for: .milliseconds(125))
        }
    }
}

/// What SwiftUI still draws over the map: the selected stop and a dropped pin. In its own view, so their
/// positions, which change with every frame of a move, redraw nothing else.
struct MapOverlays: View {
    let map: MapModel

    var body: some View {
        if let point = map.selectedPoint, let selected = map.selectedStation {
            Group {
                if map.closedStations.contains(selected) {
                    ClosedStopMark(size: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KGColor.white, lineWidth: 3))
                } else {
                    KGStopMarker("", isSelected: true, showsName: false)
                }
            }
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
}

/// The map's top corner: the weather, or orange "Fahrplan endet bald" in the last 14 days of the timetable
/// and "Fahrplan abgelaufen" after it (S4.2). Nothing before the first reading (a first start without internet). Asks for fresh weather while
/// the map is open.
private struct StatusCorner: View {
    let info: TimetableInfo?
    let weather: WeatherModel

    var body: some View {
        ZStack(alignment: .leading) {
            if info?.validity() == .ended {
                KGStatusPill(Text("Fahrplan abgelaufen", bundle: .module), isWarning: true)
            } else if info?.validity() == .endingSoon {
                KGStatusPill(Text("Fahrplan endet bald", bundle: .module), isWarning: true)
            } else if let reading = weather.reading, reading.isFresh(at: .now) {
                WeatherChip(reading: reading)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 1, minHeight: 1)
        .task { await weather.keepFresh() }
    }
}

/// The layers menu (S4.4): stops and vehicles on or off. The app is always dark.
private struct LayersSheet: View {
    @Binding var showsStops: Bool
    @Binding var showsVehicles: Bool
    @Binding var onlyLine: String
    let lines: [String]
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
            Text("Positionen sind aus Fahrplan und Verspätungen berechnet, nicht per GPS gemessen.", bundle: .module)
                .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            if showsVehicles {
                ScrollView(.horizontal) {
                    HStack(spacing: KGSpace.xs) {
                        KGChip(Text("Alle Linien", bundle: .module), isOn: onlyLine.isEmpty) { onlyLine = "" }
                        ForEach(lines, id: \.self) { line in
                            KGChip(Text(verbatim: line), isOn: onlyLine == line) { onlyLine = line }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("onlyLine")
            }
            Spacer(minLength: 0)
        }
        .padding(KGSpace.large)
        .presentationDetents([.height(360)])
        .kgGlassSheet()
        .presentationCornerRadius(KGRadius.card)
    }
}

/// The pin of a picked place or a long press, drawn with its tip on the point: it falls in from above and
/// bounces, its shadow grows as it lands, and a ring spreads from the spot.
struct DroppedPin: View {
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
    /// Einstellungen (with Favoriten), from Seeri.
    case menu
    /// What the operator says is going on.
    case notices
    case station(Int)
    case place(SavedTarget)
    /// A departure picked at a stop: the bus's stops ahead.
    case trip(tripID: Int, day: ServiceDay, fromStation: Int)

    /// The sheet for a saved thing: a stop with its departures. A saved stop that has left the timetable
    /// opens like a place, with the connections to where it was.
    static func opening(_ target: SavedTarget, stationExists: (Int) -> Bool) -> MapSheet {
        if case let .station(id, _, _) = target, stationExists(id) { return .station(id) }
        return .place(target)
    }

    var id: String {
        switch self {
        case .search: "search"
        case .menu: "menu"
        case .notices: "notices"
        case let .station(id): "station-\(id)"
        case let .place(target): "place-\(target.name)-\(target.coordinate.latitude)-\(target.coordinate.longitude)"
        case let .trip(tripID, day, station): "trip-\(tripID)-\(day)-\(station)"
        }
    }
}
