import KGCore
import KGDesign
import SwiftUI

/// Screen 17 (Abfahrtsdetails): the bus from the stop it was picked at: line and direction, the departure
/// card ("Abfahrt Sternenplatz 14:35 · Steig D · laut Fahrplan · in 4 Min. · 17 Min. Fahrt"), the stops
/// ahead on a timeline with the estimated position (plan S8).
struct TripScreen: View {
    let services: AppServices
    let tripID: Int
    let day: ServiceDay
    let fromStation: Int
    @State private var ride: RideLeg?
    @State private var now = Date.now

    var body: some View {
        VStack(spacing: 0) {
            header
            if let ride {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DepartureCard(ride: ride, now: now).riseIn(after: 0)
                        KGSectionHeader(Text("Haltestellen", bundle: .module))
                            .padding(.horizontal, KGSpace.xxs)
                            .padding(.top, KGSpace.xl)
                            .padding(.bottom, KGSpace.small)
                        StopsTimeline(ride: ride, now: now).riseIn(after: 0.15)
                    }
                    .padding(.horizontal, KGSpace.screen)
                    .padding(.bottom, KGSpace.large)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(KGGlassBackdrop().ignoresSafeArea())
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button { services.router.back() } label: {
                HStack(spacing: 2) {
                    KGIconView(.back, size: 22)
                    Text(verbatim: services.transit.station(id: fromStation)?.shortName ?? "")
                        .kgFont(.bodyMedium).lineLimit(1)
                }
                .foregroundStyle(KGColor.location)
                .frame(minHeight: KGSize.touch)
                .padding(.horizontal, KGSpace.small)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Zurück", bundle: .module))
            Spacer()
        }
        .padding(.horizontal, KGSpace.small)
        .padding(.top, KGSpace.xxs)
    }

    private func load() async {
        ride = Self.ride(services: services, tripID: tripID, day: day, fromStation: fromStation)
        while !Task.isCancelled {
            now = .now
            try? await Task.sleep(for: .seconds(20))
        }
    }
}

/// The white card: big badge, "Bus 9A", direction; departure time and platform big; status and duration.
extension TripScreen {
    /// The trip from the chosen stop to its end. Trips after midnight belong to the day before, so that day is
    /// tried too.
    static func ride(services: AppServices, tripID: Int, day: ServiceDay, fromStation: Int) -> RideLeg? {
        for candidate in [day, day.adding(days: -1)] {
            guard let trip = try? services.transit.trip(id: tripID, on: candidate),
                  let start = trip.stops.firstIndex(where: { $0.station.id == fromStation }),
                  trip.stops.count - start >= 2 else { continue }
            return RideLeg(tripID: trip.id, line: trip.line, headsign: trip.headsign,
                           stops: Array(trip.stops[start...]), path: trip.shape)
        }
        return nil
    }
}

struct DepartureCard: View {
    let ride: RideLeg
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KGSpace.medium) {
                KGLineBadge(ride.line.name, size: .big)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bus \(ride.line.name)", bundle: .module).kgFont(.headline.weighted(KGFont.extraBold))
                        .foregroundStyle(KGColor.ink)
                    Text("Richtung \(ride.headsign)", bundle: .module).kgFont(.footnote.weighted(KGFont.regular))
                        .foregroundStyle(KGColor.ink2)
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Abfahrt \(ride.boarding.station.shortName)", bundle: .module)
                        .kgFont(.caption.weighted(KGFont.bold)).foregroundStyle(KGColor.ink2)
                    Text(verbatim: KGStrings.clock(ride.start)).kgFont(.bigMinutes(44).weighted(KGFont.bold))
                        .foregroundStyle(KGColor.ink)
                }
                Spacer()
                if let platform = ride.boarding.platform.code {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Steig", bundle: .module).kgFont(.caption.weighted(KGFont.bold))
                            .foregroundStyle(KGColor.ink2)
                        Text(verbatim: platform).kgFont(.bigMinutes(34).weighted(KGFont.bold)).foregroundStyle(KGColor.ink)
                    }
                }
            }
            .padding(.top, KGSpace.mediumLarge)
            HStack(spacing: KGSpace.small) {
                // "Pünktlich" only with live data (plan 0.3).
                switch ride.status {
                case .cancelled: KGTag(Text("Fällt aus", bundle: .module), tone: .line)
                case let .live(minutes) where minutes > 0: KGTag(Text("+\(minutes) Min.", bundle: .module), tone: .line)
                case let .live(minutes) where minutes < 0:
                    KGTag(Text("\(-minutes) Min. früher", bundle: .module), tone: .line)
                case .live: KGTag(Text("Pünktlich", bundle: .module), tone: .live)
                case .scheduled, .stopClosed: KGTag(Text("Laut Fahrplan", bundle: .module), tone: .neutral)
                }
                (Text(verbatim: KGMinutesValue(departure: ride.start, now: now).spoken + " · ")
                    + Text("\(Leg.ride(ride).minutes) Min. Fahrt", bundle: .module))
                    .kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.ink2)
            }
            .padding(.top, KGSpace.compact)
        }
        .padding(.vertical, KGSpace.screen)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kgGlassCard(in: .kgRounded(KGRadius.cardLarge))
        .accessibilityElement(children: .combine)
    }
}

/// The stops ahead with times; passed ones grey, the estimated position marked "jetzt".
struct StopsTimeline: View {
    let ride: RideLeg
    let now: Date
    @Environment(\.stopClosures) private var closures

    var body: some View {
        let progress = TripProgress(ride: ride, at: now)
        KGTimeline(progress: progress.fraction) {
            VStack(spacing: 0) {
                ForEach(Array(ride.stops.enumerated()), id: \.offset) { index, stop in
                    KGTimelineStop(stop.station.shortName, time: index == 0 ? stop.departure : stop.arrival,
                                   state: state(index, progress: progress),
                                   isSkipped: closures.isClosed(station: stop.station.id, line: ride.line.name))
                }
            }
        }
        .padding(.horizontal, KGSpace.screen)
        .padding(.vertical, KGSpace.xs)
        .kgGlassCard(in: .kgRounded(KGRadius.cardLarge))
    }

    private func state(_ index: Int, progress: TripProgress) -> KGTimelineStop.State {
        let last = ride.stops.count - 1
        if progress.phase == .waiting { return index == 0 ? .first : (index == last ? .last : .coming) }
        if index == progress.currentStop, progress.phase != .arrived { return .current }
        if index < progress.currentStop { return .past }
        return index == last ? .last : .coming
    }
}
