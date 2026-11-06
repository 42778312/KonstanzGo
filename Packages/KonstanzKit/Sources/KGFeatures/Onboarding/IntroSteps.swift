import KGCore
import KGDesign
import SwiftUI

/// The intro: the real app, one feature per step, moving on only when asked. The map, its buses, the stop's
/// list, the notice and the rescue are the app's own views on live data, shown but not touchable, with Seeri
/// explaining underneath.
struct IntroSteps: View {
    enum Page: Int, CaseIterable { case map, search, stop, notices, rescue, offline }

    let services: AppServices
    let onDone: () -> Void
    @State private var page = Page.map
    @State private var map = MapModel()
    @State private var typed = ""
    @State private var journey: Journey?
    @State private var option: RescueOption?
    @State private var rescued = false
    @State private var height: CGFloat = 800
    /// When the intro began, and the moment it shows: now, or midday when it's night and no buses run.
    @State private var opened = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var transit: OfflineTransit { services.transit }
    private func stop(_ name: String) -> Station? { transit.stations.first { $0.shortName == name } }
    private var sternenplatz: Station? { stop("Sternenplatz") }

    /// Stands in for the clock: buses and departures have to be there whenever the app is first opened.
    private var demoStart: Date {
        let hour = Calendar.konstanz.component(.hour, from: opened)
        guard !(7...21).contains(hour) else { return opened }
        return Calendar.konstanz.date(bySettingHour: 12, minute: 0, second: 0, of: opened) ?? opened
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            #if canImport(MapLibre) && canImport(UIKit)
            KGMapView(data: services.data, model: map)
                .ignoresSafeArea()
            #else
            KGColor.mapLand
            #endif
            MapOverlays(map: map)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: KGSpace.small) {
                panel
                    .id(page)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                guide
            }
            .padding(.horizontal, KGSpace.small)
            .padding(.bottom, KGSpace.xs)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDone) {
                Text("Überspringen", bundle: .module).kgFont(.footnote).foregroundStyle(KGColor.ink)
                    .padding(.horizontal, KGSpace.compact)
                    .frame(minHeight: 36)
                    .kgGlass(in: Capsule())
                    .frame(minHeight: KGSize.touch)
                    .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .padding(.trailing, KGSpace.screen)
            .accessibilityIdentifier("introSkip")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
            if drag.translation.width < -60 { next() } else if drag.translation.width > 60 { back() }
        })
        .onAppear {
            map.stations = transit.stations
            show(.map)
        }
        .task { await moveBuses() }
        .task { await followLive() }
        .task { await planRescue() }
        .task(id: page) { await play() }
    }

    // MARK: Seeri

    private var guide: some View {
        VStack(spacing: KGSpace.compact) {
            HStack(alignment: .top, spacing: KGSpace.compact) {
                SeeriAlive(seeri, detail: .compact, sirenFlashing: page == .notices ? true : nil)
                    .frame(width: 58, height: 62)
                    .padding(.top, 6)
                    .id(page)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).kgFont(.headline).foregroundStyle(KGColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: speech).kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(page)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            HStack(spacing: KGSpace.medium) {
                HStack(spacing: 6) {
                    ForEach(Page.allCases, id: \.self) { item in
                        Capsule().fill(item == page ? KGColor.coral : KGColor.ink.opacity(0.25))
                            .frame(width: item == page ? 18 : 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Schritt \(page.rawValue + 1) von \(Page.allCases.count)", bundle: .module))
                KGButton(page == .offline ? Text("Los geht's", bundle: .module) : Text("Weiter", bundle: .module), action: next)
                    .accessibilityIdentifier("introNext")
            }
        }
        .padding(KGSpace.compact)
        .kgGlass(in: .kgRounded(KGRadius.card))
        .kgShadow(.floating, in: .kgRounded(KGRadius.card))
    }

    private var seeri: Seeri.Expression {
        switch page {
        case .map: .excited
        case .search: .looking
        case .stop: .focused
        case .notices: .excited
        case .rescue: .curious
        case .offline: .joyful
        }
    }

    private var title: String {
        switch page {
        case .map: String(localized: "Hallo, ich bin Seeri", bundle: .module)
        case .search: String(localized: "Sag mir, wohin du willst", bundle: .module)
        case .stop: String(localized: "Echte Zeiten an jeder Haltestelle", bundle: .module)
        case .notices: String(localized: "Mein Blaulicht warnt dich", bundle: .module)
        case .rescue: String(localized: "Anschluss verpasst?", bundle: .module)
        case .offline: String(localized: "Läuft auch ohne Netz", bundle: .module)
        }
    }

    private var speech: String {
        switch page {
        case .map: String(localized: "Das hier ist deine Karte. Alle Busse fahren mit, ein grüner Punkt heißt: live.", bundle: .module)
        case .search: String(localized: "Tippen oder ins Mikro sprechen. Die Suche ist unten auf der Karte.", bundle: .module)
        case .stop: String(localized: "Tipp auf eine Haltestelle. Orange heißt: Der Bus kommt später als geplant.", bundle: .module)
        case .notices: String(localized: "Blinke ich, tipp mich an. Das X zeigt gesperrte Haltestellen, ich sage dir die Alternativen.", bundle: .module)
        case .rescue: String(localized: "Auf deiner Fahrt warne ich dich. Ein Tipp, und du hast einen neuen Weg zum selben Ziel.", bundle: .module)
        case .offline: String(localized: "Fahrplan und Karte sind immer dabei. Mit Internet kommen Verspätungen und Meldungen dazu.", bundle: .module)
        }
    }

    // MARK: The real thing, for each step

    @ViewBuilder private var panel: some View {
        Group {
            switch page {
            case .map: EmptyView()
            case .search: searchPanel
            case .stop:
                if let sternenplatz {
                    StationPanel(services: services, station: sternenplatz, onClose: {}, start: demoStart)
                        .padding(.top, KGSpace.medium)
                        .frame(height: min(height * 0.42, 340))
                        .kgGlass(in: .kgRounded(KGRadius.card))
                        .clipShape(.kgRounded(KGRadius.card))
                }
            case .notices:
                VStack(alignment: .leading, spacing: KGSpace.xs) {
                    KGTag(Text("Beispiel", bundle: .module), tone: .neutral)
                    NoticeCard(services: services, notice: exampleNotice, now: opened, onStation: { _ in })
                }
                .padding(KGSpace.small)
                .kgGlass(in: .kgRounded(KGRadius.card))
            case .rescue: rescuePanel
            case .offline:
                OfflineCard(info: transit.timetableInfo) {}
                    .padding(KGSpace.small)
                    .kgGlass(in: .kgRounded(KGRadius.card))
            }
        }
        .allowsHitTesting(false)
    }

    private var searchPanel: some View {
        VStack(spacing: KGSpace.xs) {
            HStack(spacing: KGSpace.small) {
                KGIconView(.search, size: 20).foregroundStyle(KGColor.ink2)
                Text(verbatim: typed.isEmpty ? String(localized: "Wohin möchtest du?", bundle: .module) : typed)
                    .kgFont(.bodyMedium).foregroundStyle(typed.isEmpty ? KGColor.ink2 : KGColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                KGIconView(.mic, size: 20).foregroundStyle(KGColor.ink2)
            }
            .padding(.horizontal, KGSpace.medium)
            .frame(height: 50)
            .kgGlassCard(in: Capsule())
            ForEach(Array(transit.search(typed, near: MapRegion.center).prefix(2))) { result in
                ResultRow(result: result, query: typed)
            }
        }
        .padding(KGSpace.small)
        .kgGlass(in: .kgRounded(KGRadius.card))
        .animation(KGMotion.pop, value: typed)
    }

    @ViewBuilder private var rescuePanel: some View {
        VStack(spacing: KGSpace.small) {
            if let ride = journey?.firstRide {
                RescuePrompt(risk: .cancelled(ride), isSearching: false) {}
            }
            if rescued, let option {
                RescueCard(option: option, isBest: true) {}
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(KGSpace.small)
        .kgGlass(in: .kgRounded(KGRadius.card))
    }

    /// The closure shown in the notices step. Marked as an example: it isn't necessarily going on today.
    private var exampleNotice: ServiceNotice {
        let closed = ["Brüelstraße", "Schulthaißstraße"].compactMap { stop($0)?.id }
        let instead = ["Döbelestraße", "Gartenstraße"].compactMap { stop($0)?.id }
        let text = String(localized: "Wegen eines Wasserrohrbruchs werden diese Haltestellen nicht angefahren. Bitte nutze eine der anderen.",
                          bundle: .module)
        return ServiceNotice(id: "intro", text: text, lines: ["1", "5", "9"], stations: closed, closesStops: true, alternatives: instead,
                             periods: [.init(from: opened.addingTimeInterval(-3600), to: opened.addingTimeInterval(2 * 86_400))])
    }

    // MARK: Moving between steps

    private func next() {
        guard let following = Page(rawValue: page.rawValue + 1) else { return onDone() }
        move(to: following)
    }

    private func back() {
        if let previous = Page(rawValue: page.rawValue - 1) { move(to: previous) }
    }

    private func move(to new: Page) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.15)) { page = new }
        show(new)
    }

    /// Takes the map where the step is, keeping that place clear of the panels.
    private func show(_ new: Page) {
        map.pins = []
        map.lines = []
        map.selectedStationID = nil
        map.closedStations = []
        typed = ""
        rescued = false
        let guideSpace: CGFloat = 170
        switch new {
        case .map:
            map.insets = MapInsets(top: 60, bottom: guideSpace)
            map.move(CameraMove(center: MapRegion.center, zoom: 13.6))
        case .search:
            map.insets = MapInsets(top: 60, bottom: guideSpace + 180)
            map.move(CameraMove(center: MapRegion.center, zoom: 13.6))
        case .stop:
            map.insets = MapInsets(top: 60, bottom: guideSpace + min(height * 0.42, 340))
            map.selectedStationID = sternenplatz?.id
            if let sternenplatz { map.move(CameraMove(center: sternenplatz.coordinate, zoom: MapRegion.destinationZoom)) }
        case .notices:
            let closed = exampleNotice.stations.compactMap { transit.station(id: $0) }
            map.closedStations = closed
            map.insets = MapInsets(top: 60, bottom: guideSpace + 300)
            if let first = closed.first { map.move(CameraMove(center: first.coordinate, zoom: 14.2)) }
        case .rescue:
            map.insets = MapInsets(top: 60, bottom: guideSpace + 150)
            if let journey {
                map.lines = journey.mapLines
                map.move(.fitting(journey.allPoints))
            }
        case .offline:
            map.insets = MapInsets(top: 60, bottom: guideSpace + 120)
            map.move(CameraMove(center: MapRegion.center, zoom: 12.4))
        }
    }

    /// What happens within a step, once it's open.
    private func play() async {
        switch page {
        case .search:
            try? await Task.sleep(for: .seconds(0.5))
            for letter in "Sternenplatz" {
                guard !Task.isCancelled else { return }
                typed.append(letter)
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 80))
            }
            if let sternenplatz {
                map.pins = [MapPin(id: "place", coordinate: sternenplatz.coordinate)]
                map.move(CameraMove(center: sternenplatz.coordinate, zoom: MapRegion.destinationZoom))
            }
        case .rescue:
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let option else { return }
            withAnimation(KGMotion.pop) { rescued = true }
            map.lines = option.journey.mapLines
            map.move(.fitting(option.journey.allPoints))
        default:
            break
        }
    }

    // MARK: Live

    private func moveBuses() async {
        let tracker = transit.tracker, begin = demoStart, live = services.live
        while !Task.isCancelled {
            let moment = begin.addingTimeInterval(Date.now.timeIntervalSince(opened))
            let delays = live.tripDelays, cancelled = live.cancelledTrips
            let found = await Task.detached(priority: .utility) {
                (try? tracker.positions(at: moment, delays: delays, cancelled: cancelled)) ?? []
            }.value
            map.vehicles = found.filter { MapRegion.contains($0.coordinate) }.map { vehicle in
                MapVehicle(id: vehicle.tripID, line: vehicle.line.name, coordinate: vehicle.coordinate, heading: vehicle.heading,
                           look: .vehicle(isTrain: vehicle.line.mode == .train, isYellow: vehicle.line.isYellowBus,
                                          isLive: !vehicle.isEstimated))
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// The same reports as on the map, for the green dots: most buses pass Konstanz Bahnhof.
    private func followLive() async {
        guard demoStart == opened, let hub = stop("Bahnhof")?.id else { return }
        let store = transit.store, live = services.live
        while !Task.isCancelled {
            let now = Date.now
            let departures = await Task.detached(priority: .utility) {
                (try? store.departures(at: hub, from: now, limit: 60, within: 2)) ?? []
            }.value
            await live.followHub(station: hub, departures: departures, at: now)
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// A real journey and a real way out of it, for the rescue step.
    private func planRescue() async {
        guard let from = sternenplatz, let to = stop("Universität") else { return }
        let planner = transit.planner, time = demoStart
        let found = await Task.detached(priority: .userInitiated) { () -> (Journey?, RescueOption?) in
            let request = PlanRequest(from: Endpoint(name: from.shortName, coordinate: from.coordinate),
                                      to: Endpoint(name: to.shortName, coordinate: to.coordinate), time: time)
            guard let journey = try? planner.plan(request).first(where: { !$0.rides.isEmpty }),
                  let first = journey.firstRide else { return (nil, nil) }
            let live = LiveState(cancelled: [first.tripID])
            return (journey, try? planner.rescue(journey, at: first.start.addingTimeInterval(-60), live: live).first)
        }.value
        journey = found.0
        option = found.1
    }
}
