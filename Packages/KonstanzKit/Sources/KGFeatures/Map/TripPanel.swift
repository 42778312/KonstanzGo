import KGCore
import KGDesign
import SwiftUI

/// A departure picked at a stop, in the map's sheet like the stop itself: back to the stop, the departure
/// card, a reminder, and the stops ahead. The map behind shows the bus's way (plan S8, moved into the map's
/// sheet so every list folds, swipes and closes the same).
struct TripPanel: View {
    let services: AppServices
    let ride: RideLeg
    let onBack: () -> Void
    let onClose: () -> Void
    @State private var now = Date.now
    @State private var alarm: Alarm?
    @State private var choosingAlarm = false
    @State private var alarmFailed = false

    /// The ride with what's known about it right now.
    private var shownRide: RideLeg {
        var shown = ride
        shown.status = services.live.status(ofTrip: ride.tripID, at: now)
        return shown
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 2) {
                            KGIconView(.back, size: 20)
                            Text(verbatim: ride.boarding.station.shortName).kgFont(.bodyMedium).lineLimit(1)
                        }
                        .foregroundStyle(KGColor.location)
                        .frame(minHeight: KGSize.touch)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Zurück", bundle: .module))
                    .accessibilityIdentifier("tripBack")
                    Spacer()
                    KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain,
                                      action: onClose)
                        .accessibilityIdentifier("closeTrip")
                }
                DepartureCard(ride: shownRide, now: now)
                if ride.isDiverted(closures: services.live.closures) {
                    Text("Umleitung, Weg unbekannt. Die Linie auf der Karte zeigt nicht die echte Strecke.", bundle: .module)
                        .kgFont(.callout.weighted(KGFont.medium)).foregroundStyle(KGColor.warn)
                        .accessibilityIdentifier("divertedRide")
                }
                alarmButton
                KGSectionHeader(Text("Haltestellen", bundle: .module))
                    .padding(.horizontal, KGSpace.xxs)
                StopsTimeline(ride: ride, now: now)
                Text("Die Position auf der Karte ist aus Fahrplan und Verspätung berechnet, nicht per GPS gemessen.", bundle: .module)
                    .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    .accessibilityIdentifier("calculatedPosition")
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, KGSpace.medium)
            .padding(.bottom, KGSpace.xl)
        }
        .scrollIndicators(.hidden)
        .task {
            alarm = (try? services.user?.upcomingAlarms())?.first {
                // With the time too: trip numbers change when a new timetable arrives.
                $0.tripID == ride.tripID && $0.departure == ride.start
            }
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .alert(Text("Mitteilungen sind aus", bundle: .module), isPresented: $alarmFailed) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text("Erlaube Mitteilungen in den Einstellungen, dann kann ich dich erinnern.", bundle: .module)
        }
    }

    /// "Alarm stellen" before the bus leaves; once set, it says when and takes it back on a tap (S6.5).
    @ViewBuilder private var alarmButton: some View {
        if let alarm, alarm.departure > now {
            KGButton(Text("Alarm \(alarm.minutesBefore) Min. vorher", bundle: .module), icon: .bellFilled,
                     kind: .secondary) {
                AlarmScheduler.cancel(alarm)
                services.updateUser { try $0.removeAlarm(id: alarm.id) }
                self.alarm = nil
            }
            .accessibilityHint(Text("Tippen nimmt den Alarm zurück", bundle: .module))
        } else if ride.start.addingTimeInterval(-60) > now {
            KGButton(Text("Alarm stellen", bundle: .module), icon: .bell) { choosingAlarm = true }
                .accessibilityIdentifier("setAlarm")
                .kgGlassMenu(isPresented: $choosingAlarm, title: Text("Wann soll ich dich erinnern?", bundle: .module),
                             message: Text("Für Linie \(ride.line.name) nach \(ride.headsign) um \(KGStrings.clock(ride.start))",
                                           bundle: .module),
                             items: [1, 2, 5, 10].map { minutes in
                                 KGGlassMenuItem(Text("\(minutes) Min. vorher", bundle: .module)) {
                                     Task { await setAlarm(minutes: minutes) }
                                 }
                             })
        }
    }

    private func setAlarm(minutes: Int) async {
        guard ride.start.addingTimeInterval(TimeInterval(-minutes * 60)) > .now else { return }
        let new = Alarm(stationID: ride.boarding.station.id, stationName: ride.boarding.station.shortName,
                        tripID: ride.tripID, lineName: ride.line.name, headsign: ride.headsign,
                        platformCode: ride.boarding.platform.code, departure: ride.start, minutesBefore: minutes)
        if await AlarmScheduler.schedule(new) {
            services.updateUser { try $0.addAlarm(new) }
            withAnimation(KGMotion.pop) { alarm = new }
        } else {
            alarmFailed = true
        }
    }
}
