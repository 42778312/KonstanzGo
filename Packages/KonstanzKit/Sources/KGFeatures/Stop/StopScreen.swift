import KGCore
import KGDesign
import SwiftUI

/// Screen 09 (Haltestelle): map strip with the stop, back and favourite; name, walk and lines; "Abfahrten |
/// Linien"; departures that tick and slide out; "Alarm stellen" (plan S6).
struct StopScreen: View {
    let services: AppServices
    let stationID: Int
    @State private var view = 0
    @State private var departures: [Departure] = []
    @State private var directions: [LineDirection] = []
    @State private var lines: [Line] = []
    @State private var now = Date.now
    @State private var choosingAlarm = false
    @State private var alarm: Alarm?
    @State private var alarmFailed = false

    private var station: Station? { services.transit.station(id: stationID) }

    var body: some View {
        if let station {
            content(station)
        } else {
            KGEmptyState(.sleepy, title: Text("Haltestelle nicht gefunden", bundle: .module),
                         message: Text("Sie ist nicht im aktuellen Fahrplan.", bundle: .module)) {
                KGButton(Text("Zurück", bundle: .module), kind: .secondary) { services.router.back() }
            }
        }
    }

    private func content(_ station: Station) -> some View {
        ZStack(alignment: .top) {
            MapStrip(services: services, center: station.coordinate)
                .frame(height: 250)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                Color.clear.frame(height: 222 - 47)
                panel(station)
            }
            HStack {
                KGRoundIconButton(.back, label: Text("Zurück", bundle: .module)) { services.router.back() }
                Spacer()
                FavoriteButton(services: services, target: target(station))
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, 11)
        }
        .background(KGColor.surface.ignoresSafeArea())
        .task(id: stationID) { await refreshLoop() }
        .confirmationDialog(Text("Wann soll ich dich erinnern?", bundle: .module), isPresented: $choosingAlarm,
                            titleVisibility: .visible) {
            ForEach([1, 2, 5, 10], id: \.self) { minutes in
                Button { Task { await setAlarm(minutes: minutes, station: station) } } label: {
                    Text("\(minutes) Min. vorher", bundle: .module)
                }
            }
        } message: {
            if let next = departures.first {
                Text("Für Linie \(next.line.name) nach \(next.headsign) um \(KGStrings.clock(next.expected))",
                     bundle: .module)
            }
        }
        .alert(Text("Mitteilungen sind aus", bundle: .module), isPresented: $alarmFailed) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text("Erlaube Mitteilungen in den Einstellungen, dann kann ich dich erinnern.", bundle: .module)
        }
    }

    private func panel(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: station.shortName)
                .kgFont(.display.sized(30))
                .tracking(-0.3)
                .foregroundStyle(KGColor.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: KGSpace.small) {
                subtitle(station).kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                Spacer(minLength: KGSpace.small)
                HStack(spacing: KGSpace.xxs) {
                    ForEach(lines.prefix(5), id: \.id) { KGLineBadge($0.name, size: .small) }
                }
            }
            .padding(.top, KGSpace.xs)
            KGSegmentedControl(selection: $view, options: [(0, Text("Abfahrten", bundle: .module)),
                                                         (1, Text("Linien", bundle: .module))])
                .padding(.top, 18)
            ScrollView {
                if view == 0 { departureList(station) } else { lineList }
            }
            .scrollIndicators(.hidden)
            alarmButton(station)
                .padding(.bottom, KGSpace.compact)
        }
        .padding(.top, 22)
        .padding(.horizontal, KGSpace.large)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KGColor.surface, in: UnevenRoundedRectangle(topLeadingRadius: KGRadius.card,
                                                                topTrailingRadius: KGRadius.card,
                                                                style: .continuous))
    }

    private func subtitle(_ station: Station) -> Text {
        let metres = station.coordinate.distance(to: services.anchor)
        if services.here != nil {
            let minutes = max(1, Int((metres * 1.25 / 80).rounded(.up)))
            return Text("Haltestelle · \(minutes) Min. zu Fuß", bundle: .module)
        }
        return Text("Haltestelle", bundle: .module)
    }

    // MARK: Lists

    @ViewBuilder private func departureList(_ station: Station) -> some View {
        if departures.isEmpty {
            KGEmptyState(.sleepy, title: Text("Heute fährt hier nichts mehr", bundle: .module),
                         message: firstBusText)
                .padding(.top, KGSpace.xl)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(departures.enumerated()), id: \.element.id) { index, departure in
                    Button {
                        services.router.open(.trip(tripID: departure.tripID, day: ServiceDay(departure.scheduled),
                                                   fromStation: station.id))
                    } label: {
                        KGDepartureRow(line: departure.line.name, destination: departure.headsign,
                                       platform: departure.platform.code, departure: departure.expected, now: now,
                                       isLive: departure.status.isLive, style: .large)
                            .contentShape(.rect)
                    }
                    .buttonStyle(KGRowPressStyle())
                    .overlay(alignment: .bottom) {
                        if index < departures.count - 1 { Rectangle().fill(KGColor.line).frame(height: 1) }
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .padding(.top, KGSpace.small)
            .animation(KGMotion.slide, value: departures.map(\.id))
        }
    }

    private var firstBusText: Text {
        Text("Der Fahrplan hat für die nächsten Stunden keine Abfahrt mehr.", bundle: .module)
    }

    private var lineList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(directions.enumerated()), id: \.element.id) { index, direction in
                HStack(spacing: KGSpace.medium) {
                    KGLineBadge(direction.line.name, size: .large)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Richtung \(direction.headsign)", bundle: .module)
                            .kgFont(.bodyMedium).foregroundStyle(KGColor.ink)
                        Text(verbatim: direction.departures.prefix(3).map { KGStrings.clock($0.expected) }
                            .joined(separator: " · "))
                            .kgFont(.caption.weighted(KGFont.regular)).monospacedDigit().foregroundStyle(KGColor.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 72)
                .overlay(alignment: .bottom) {
                    if index < directions.count - 1 { Rectangle().fill(KGColor.line).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, KGSpace.small)
    }

    // MARK: Alarm (S6.5)

    @ViewBuilder private func alarmButton(_ station: Station) -> some View {
        if let alarm, alarm.departure > now {
            KGButton(Text("Alarm \(alarm.minutesBefore) Min. vorher", bundle: .module), icon: .bellFilled,
                     kind: .secondary) {
                AlarmScheduler.cancel(alarm)
                services.updateUser { try $0.removeAlarm(id: alarm.id) }
                self.alarm = nil
            }
            .accessibilityHint(Text("Tippen nimmt den Alarm zurück", bundle: .module))
        } else if !departures.isEmpty {
            KGButton(Text("Alarm stellen", bundle: .module), icon: .bell) { choosingAlarm = true }
                .accessibilityIdentifier("setAlarm")
        }
    }

    private func setAlarm(minutes: Int, station: Station) async {
        guard let next = departures.first(where: {
            $0.expected.addingTimeInterval(TimeInterval(-minutes * 60)) > .now
        }) else { return }
        let new = Alarm(stationID: station.id, stationName: station.shortName, tripID: next.tripID,
                        lineName: next.line.name, headsign: next.headsign, platformCode: next.platform.code,
                        departure: next.expected, minutesBefore: minutes)
        if await AlarmScheduler.schedule(new) {
            services.updateUser { try $0.addAlarm(new) }
            withAnimation(KGMotion.pop) { alarm = new }
        } else {
            alarmFailed = true
        }
    }

    // MARK: Data

    private func target(_ station: Station) -> SavedTarget {
        .station(id: station.id, name: station.shortName, coordinate: station.coordinate)
    }

    /// Loads now and every 30 s; departed rows slide out (S6.3).
    private func refreshLoop() async {
        lines = (try? services.transit.lines(at: stationID)) ?? []
        alarm = (try? services.user?.upcomingAlarms())?.first { $0.stationID == stationID }
        while !Task.isCancelled {
            now = .now
            departures = (try? services.transit.departures(at: stationID, from: now, limit: 12)) ?? []
            directions = (try? services.transit.departuresByLine(at: stationID, from: now)) ?? []
            try? await Task.sleep(for: .seconds(30))
        }
    }
}

/// The white round star button over a map: hollow, or yellow when saved (pops in).
struct FavoriteButton: View {
    let services: AppServices
    let target: SavedTarget

    var body: some View {
        let saved = services.isFavorite(target)
        Button {
            withAnimation(KGMotion.pop) { services.toggleFavorite(target) }
        } label: {
            ZStack {
                if saved {
                    KGIconView(.star, size: 22, fill: KGColor.lineFill).foregroundStyle(KGColor.lineText)
                        .transition(.scale(scale: KGMotion.popStart).combined(with: .opacity))
                } else {
                    KGIconView(.star, size: 22).foregroundStyle(KGColor.ink)
                }
            }
            .frame(width: KGSize.touch, height: KGSize.touch)
            .background(KGColor.surface, in: .circle)
            .kgShadow(.floating, in: Circle())
        }
        .buttonStyle(KGPressStyle())
        .accessibilityLabel(Text("Favorit", bundle: .module))
        .accessibilityAddTraits(saved ? .isSelected : [])
        .sensoryFeedback(KGHaptic.success, trigger: saved)
    }
}
