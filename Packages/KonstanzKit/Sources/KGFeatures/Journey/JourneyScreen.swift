import KGCore
import KGDesign
import SwiftUI

/// Screen 11 (Unterwegs): the map with the bus, "Fahrt beenden", where the trip goes; in the sheet Seeri
/// counting the stops, minutes to arrival, a progress bar and the stops timeline. It moves through the
/// journey's phases (walk, wait, ride, change, arrive) by the clock and, when known, the user's position
/// (plan S15).
struct JourneyScreen: View {
    let services: AppServices
    let journey: Journey
    @State private var now = Date.now
    @State private var savedArrival = false
    @State private var activityStarted = false

    var body: some View {
        ZStack(alignment: .top) {
            JourneyMap(services: services, journey: journey, bottomInset: 470,
                       focus: currentRide.map { $0.stops.map(\.platform.coordinate) })
            HStack(spacing: KGSpace.small) {
                KGRoundIconButton(.close, label: Text("Fahrt beenden", bundle: .module)) {
                    TripActivity.end()
                    services.router.home()
                }
                .accessibilityIdentifier("endJourney")
                if let ride = currentRide ?? journey.rides.last {
                    HStack(spacing: KGSpace.xs) {
                        KGLineBadge(ride.line.name, size: .small)
                        Text(verbatim: ride.headsign).kgFont(.callout.weighted(KGFont.bold)).lineLimit(1)
                    }
                    .foregroundStyle(KGColor.ink)
                    .padding(.leading, KGSpace.xs)
                    .padding(.trailing, KGSpace.medium)
                    .frame(minHeight: 34)
                    .background(KGColor.surface, in: .capsule)
                    .kgShadow(.floating, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, 11)
            VStack {
                Spacer()
                KGSheetSurface { sheet }
                    .frame(height: 472)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task {
            while !Task.isCancelled {
                now = .now
                if phase == .arrived, !savedArrival { saveArrival() }
                TripActivity.update(journey: journey, now: now)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: Phase

    enum Phase: Hashable {
        case walkToStop, waiting, riding, changing, walkToTarget, arrived
    }

    /// Where in the journey the user is now (S15.4).
    private var phase: Phase {
        if now >= journey.end { return .arrived }
        guard let current = journey.legs.lastIndex(where: { $0.start <= now }) else {
            return journey.legs.first.map { if case .walk = $0 { .walkToStop } else { .waiting } } ?? .waiting
        }
        switch journey.legs[current] {
        case .ride: return .riding
        case .walk: return current == journey.legs.count - 1 ? .walkToTarget
            : (current == 0 ? .walkToStop : .changing)
        }
    }

    /// The ride that is happening or comes next.
    private var currentRide: RideLeg? {
        journey.rides.first { $0.end > now } ?? journey.rides.last
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KGSpace.compact) {
                SeeriAlive(phase == .arrived ? .joyful : .excited).frame(width: 56, height: 60)
                KGSpeechBubble(cheer, size: .side)
                    .id(phase)
            }
            HStack(alignment: .firstTextBaseline) {
                KGMinutesValue(departure: journey.end, now: now).text
                    .kgFont(.bigMinutes(26)).foregroundStyle(KGColor.ink)
                Spacer()
                (Text("Ankunft ", bundle: .module) + Text(verbatim: KGStrings.clock(journey.end)).bold())
                    .kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .padding(.top, KGSpace.mediumLarge)
            ProgressBar(fraction: overallFraction)
                .padding(.top, KGSpace.small)
                .accessibilityLabel(Text("Fahrtfortschritt", bundle: .module))
                .accessibilityValue(progressValue)
            ScrollView {
                if let ride = currentRide {
                    StopsTimeline(ride: ride, now: now)
                        .padding(.top, KGSpace.mediumLarge)
                }
            }
            .scrollIndicators(.hidden)
            KGButton(activityStarted ? Text("Auf dem Sperrbildschirm", bundle: .module)
                                     : Text("Auf den Sperrbildschirm", bundle: .module),
                     icon: .lockScreen, kind: .secondary) {
                activityStarted = TripActivity.start(journey: journey, now: now)
            }
            .disabled(activityStarted || phase == .arrived)
            .padding(.bottom, KGSpace.compact)
        }
        .padding(.horizontal, KGSpace.large)
    }

    /// What Seeri says in each phase ("Noch 4 Haltestellen!").
    private var cheer: Text {
        switch phase {
        case .walkToStop:
            if let ride = journey.firstRide {
                return Text("Ab zu \(ride.boarding.station.shortName)! Bus \(ride.line.name) um \(KGStrings.clock(ride.start)).",
                            bundle: .module)
            }
            return Text("Los geht's zu Fuß!", bundle: .module)
        case .waiting:
            return Text("Gleich kommt dein Bus!", bundle: .module)
        case .riding:
            let left = currentRide.map { TripProgress(ride: $0, at: now, near: services.location.coordinate ?? $0.boarding.platform.coordinate).stopsLeft } ?? 0
            return left == 1 ? Text("Nächste Haltestelle aussteigen!", bundle: .module)
                : Text("Noch \(left) Haltestellen!", bundle: .module)
        case .changing:
            return Text("Jetzt umsteigen!", bundle: .module)
        case .walkToTarget:
            return Text("Nur noch ein Stück zu Fuß!", bundle: .module)
        case .arrived:
            return Text("Du bist da!", bundle: .module)
        }
    }

    private var overallFraction: Double {
        let total = journey.end.timeIntervalSince(journey.start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(journey.start) / total))
    }

    private var progressValue: Text {
        guard let ride = currentRide else { return Text(verbatim: "") }
        let progress = TripProgress(ride: ride, at: now)
        return Text("\(progress.currentStop + 1) von \(ride.stops.count) Haltestellen", bundle: .module)
    }

    /// Counts the trip for "5 Fahrten diese Woche" (widget, S15.4).
    private func saveArrival() {
        savedArrival = true
        guard let ride = journey.rides.first else { return }
        let trip = FinishedTrip(date: journey.end, lineName: ride.line.name, from: ride.boarding.station.shortName,
                                to: (journey.rides.last ?? ride).alighting.station.shortName)
        services.updateUser { try $0.addFinishedTrip(trip) }
        TripActivity.end()
    }
}

/// The 16 pt progress bar of screens 11 and 14 (the onboarding bar's look, any fraction).
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(KGColor.line)
                Capsule().fill(KGColor.coral)
                    .overlay(alignment: .top) {
                        Capsule().fill(KGColor.white.opacity(0.35)).frame(height: 4)
                            .padding(.horizontal, 7).padding(.top, 3)
                    }
                    .frame(width: max(16, proxy.size.width * fraction))
            }
        }
        .frame(height: 16)
        .animation(KGMotion.progress, value: fraction)
    }
}
