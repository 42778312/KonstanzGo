import KGCore
import KGDesign
import SwiftUI

/// Screen 11 (Unterwegs): the map with the whole trip, ✕ back to the connections, every bus of it; in the sheet Seeri
/// counting the stops, minutes to arrival, a progress bar and the stops timeline. A tap on the map folds the
/// sheet into a bar so the whole map shows; tapping the bar (or pulling it up) brings the stops back. It moves
/// through the journey's phases (walk, wait, ride, change, arrive) by the clock and, when known, the user's
/// position (plan S15).
struct JourneyScreen: View {
    let services: AppServices
    let journey: Journey
    @State private var now = Date.now
    @State private var savedArrival = false
    @State private var expanded = true

    private static let sheetHeight: CGFloat = 472
    private static let barHeight: CGFloat = 110

    var body: some View {
        ZStack(alignment: .top) {
            // The whole trip in view: walks and every bus.
            JourneyMap(services: services, journey: journey,
                       bottomInset: expanded ? Self.sheetHeight : Self.barHeight) {
                if expanded { withAnimation(KGMotion.sheet) { expanded = false } }
            }
            HStack(spacing: KGSpace.small) {
                KGRoundIconButton(.close, label: Text("Zurück zu den Verbindungen", bundle: .module), action: endTrip)
                .accessibilityIdentifier("endJourney")
                if !journey.rides.isEmpty {
                    // Every bus of the trip, then where it ends: "5 › 12/3  combit GmbH".
                    HStack(spacing: KGSpace.xxs) {
                        ForEach(Array(journey.rides.enumerated()), id: \.offset) { index, ride in
                            if index > 0 {
                                KGIconView(.chevronRight, size: 10).foregroundStyle(KGColor.chevron)
                            }
                            KGLineBadge(ride.line.name, size: .small)
                        }
                        Text(verbatim: destination).kgFont(.callout.weighted(KGFont.bold)).lineLimit(1)
                            .padding(.leading, KGSpace.xxs)
                    }
                    .foregroundStyle(KGColor.ink)
                    .padding(.leading, KGSpace.xs)
                    .padding(.trailing, KGSpace.medium)
                    .frame(minHeight: 34)
                    .background(KGColor.glassFill, in: .capsule)
                    .kgShadow(.floating, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, 11)
            VStack {
                Spacer()
                Group {
                    if expanded {
                        KGSheetSurface { sheet }.frame(height: Self.sheetHeight)
                    } else {
                        bar
                    }
                }
                .gesture(DragGesture(minimumDistance: 16).onEnded { drag in
                    let down = drag.translation.height > 40
                    let up = drag.translation.height < -40
                    if down || up { withAnimation(KGMotion.sheet) { expanded = up } }
                })
            }
            .ignoresSafeArea(edges: expanded ? .bottom : [])
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
                JourneyLegs(journey: journey, now: now)
                    .padding(.top, KGSpace.mediumLarge)
                    .padding(.bottom, KGSpace.large)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, KGSpace.large)
    }

    /// The folded sheet: a glass bar with the route and ✕ (ends the trip); tap it to see the stops again.
    private var bar: some View {
        FoldedBar(title: routeTitle,
                  subtitle: KGMinutesValue(departure: journey.end, now: now).text + Text(verbatim: " · ")
                      + Text("Ankunft ", bundle: .module) + Text(verbatim: KGStrings.clock(journey.end)),
                  onOpen: { withAnimation(KGMotion.sheet) { expanded = true } },
                  onClose: endTrip)
            .padding(.vertical, KGSpace.small)
            .kgGlass(in: .kgRounded(KGRadius.cardLarge))
            .kgShadow(.floating, in: .kgRounded(KGRadius.cardLarge))
            .padding(.horizontal, KGSpace.screen)
            .padding(.bottom, KGSpace.xs)
    }

    /// "Konzilstr./Theater → combit GmbH": where the first bus leaves and where the trip ends.
    private var routeTitle: String {
        [journey.firstRide?.boarding.station.shortName, destination]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " → ")
    }

    /// Where the trip ends: the last walk's target, or the last bus's stop.
    private var destination: String {
        if case let .walk(walk) = journey.legs.last { return walk.destinationName }
        return journey.rides.last?.alighting.station.shortName ?? ""
    }

    /// ✕ goes back to the connections, so another one can be picked.
    private func endTrip() {
        TripActivity.end()
        services.router.back()
    }

    /// What Seeri says in each phase ("Noch 4 Haltestellen").
    private var cheer: Text {
        switch phase {
        case .walkToStop:
            if let ride = journey.firstRide {
                return Text("Ab zu \(ride.boarding.station.shortName). Bus \(ride.line.name) um \(KGStrings.clock(ride.start)).",
                            bundle: .module)
            }
            return Text("Los geht's zu Fuß", bundle: .module)
        case .waiting:
            return Text("Gleich kommt dein Bus", bundle: .module)
        case .riding:
            let left = currentRide.map { TripProgress(ride: $0, at: now, near: services.location.coordinate ?? $0.boarding.platform.coordinate).stopsLeft } ?? 0
            return left == 1 ? Text("Nächste Haltestelle aussteigen", bundle: .module)
                : Text("Noch \(left) Haltestellen", bundle: .module)
        case .changing:
            return Text("Jetzt umsteigen", bundle: .module)
        case .walkToTarget:
            return Text("Nur noch ein Stück zu Fuß", bundle: .module)
        case .arrived:
            return Text("Du bist da", bundle: .module)
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

/// The whole trip in order: each walk as one row, each bus with its line, direction and stops, and
/// "Umsteigen" where one bus follows another.
private struct JourneyLegs: View {
    let journey: Journey
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.medium) {
            ForEach(Array(journey.legs.enumerated()), id: \.offset) { index, leg in
                switch leg {
                case let .walk(walk):
                    walkRow(walk, isChange: index > 0 && index < journey.legs.count - 1)
                case let .ride(ride):
                    if index > 0, case .ride = journey.legs[index - 1] {
                        changeRow(at: ride.boarding.station.shortName)
                    }
                    rideBlock(ride, minutes: leg.minutes)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journeyLegs")
    }

    private func rideBlock(_ ride: RideLeg, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            HStack(spacing: KGSpace.small) {
                KGLineBadge(ride.line.name, size: .small)
                Text(verbatim: ride.headsign).kgFont(.callout.weighted(KGFont.bold)).foregroundStyle(KGColor.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(minutes) Min.", bundle: .module).kgFont(.caption.weighted(KGFont.semiBold))
                    .foregroundStyle(KGColor.ink2)
            }
            StopsTimeline(ride: ride, now: now)
        }
    }

    private func walkRow(_ walk: WalkLeg, isChange: Bool) -> some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(.walk, size: 18).foregroundStyle(KGColor.location)
                .frame(width: 36, height: 36)
                .background(KGColor.locationTint, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                if isChange {
                    Text("Umsteigen", bundle: .module).kgFont(.caption.weighted(KGFont.bold))
                        .foregroundStyle(KGColor.warn)
                }
                Text("Fußweg zu \(walk.destinationName)", bundle: .module)
                    .kgFont(.callout.weighted(KGFont.bold)).foregroundStyle(KGColor.ink).lineLimit(2)
                Text("\(max(1, Leg.walk(walk).minutes)) Min. zu Fuß", bundle: .module)
                    .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func changeRow(at stop: String) -> some View {
        HStack(spacing: KGSpace.small) {
            KGIconView(.swap, size: 16).foregroundStyle(KGColor.warn)
            Text("Umsteigen an \(stop)", bundle: .module).kgFont(.caption.weighted(KGFont.bold))
                .foregroundStyle(KGColor.warn)
        }
        .padding(.leading, KGSpace.xs)
    }
}
