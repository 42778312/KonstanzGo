import KGCore
import KGDesign
import SwiftUI

/// Screen 21 (Route auf Karte): the map fitted to the journey with its bus moving; the sheet with the time,
/// the legs as chips, "Fußweg zum …" and "Los geht's" (plan S12).
struct RouteMapScreen: View {
    let services: AppServices
    let journey: Journey
    let query: PlanQuery

    var body: some View {
        ZStack(alignment: .top) {
            JourneyMap(services: services, journey: journey, bottomInset: 300)
            RouteHeader(title: "\(query.from.name) → \(query.to.name)",
                        subtitle: String(localized: "Heute · ab \(KGStrings.clock(journey.start))", bundle: .module)) {
                services.router.back()
            }
            VStack {
                Spacer()
                KGSheetSurface { sheet }
                    .frame(height: 300)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(journey.minutes) Min.", bundle: .module).kgFont(.titleL).foregroundStyle(KGColor.ink)
                Spacer()
                Text(verbatim: "\(KGStrings.clock(journey.start)) – \(KGStrings.clock(journey.end))")
                    .kgFont(.callout.weighted(KGFont.bold)).monospacedDigit().foregroundStyle(KGColor.ink2)
            }
            KGFlowLayout(spacing: KGSpace.xs, lineSpacing: KGSpace.xs) {
                ForEach(Array(journey.legs.enumerated()), id: \.offset) { _, leg in legChip(leg) }
            }
            .padding(.top, KGSpace.compact)
            if case let .walk(walk) = journey.legs.first, walk.metres > 30 {
                Button { services.router.open(.walk(journey)) } label: {
                    HStack(spacing: KGSpace.compact) {
                        KGIconView(.walk, size: 20).foregroundStyle(KGColor.location)
                        Text("Fußweg zu \(walk.destinationName)", bundle: .module).kgFont(.callout.weighted(KGFont.bold))
                            .foregroundStyle(KGColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        KGIconView(.chevronRight, size: 14).foregroundStyle(KGColor.chevron)
                    }
                    .padding(.horizontal, KGSpace.mediumLarge)
                    .frame(minHeight: 48)
                    .background(KGColor.glassFill, in: .kgRounded(KGRadius.large))
                }
                .buttonStyle(KGPressStyle())
                .padding(.top, KGSpace.medium)
                .accessibilityIdentifier("walkGuide")
            }
            Spacer(minLength: KGSpace.medium)
            KGButton(Text("Los geht's", bundle: .module)) { services.router.open(.journey(journey)) }
                .accessibilityIdentifier("beginJourney")
                .padding(.bottom, KGSpace.compact)
        }
        .padding(.horizontal, KGSpace.large)
    }

    @ViewBuilder private func legChip(_ leg: Leg) -> some View {
        switch leg {
        case .walk:
            HStack(spacing: KGSpace.xxs) {
                KGIconView(.walk, size: 14)
                Text("\(max(1, leg.minutes)) Min.", bundle: .module)
            }
            .kgFont(.caption.weighted(KGFont.extraBold))
            .foregroundStyle(KGColor.location)
            .padding(.horizontal, KGSpace.compact)
            .frame(minHeight: 30)
            .background(KGColor.locationTint, in: .capsule)
            .accessibilityElement(children: .combine)
        case let .ride(ride):
            HStack(spacing: KGSpace.xs) {
                KGLineBadge(ride.line.name, size: .small)
                Text("\(leg.minutes) Min.", bundle: .module)
            }
            .kgFont(.caption.weighted(KGFont.extraBold))
            .foregroundStyle(KGColor.ink)
            .padding(.leading, KGSpace.xs)
            .padding(.trailing, KGSpace.compact)
            .frame(minHeight: 30)
            .background(KGColor.pressed, in: .capsule)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Screen 22 (Fußweg): the walk to the stop on the map with Seeri waiting there, the next step big in blue,
/// and the step list with the current one highlighted; it follows the user (plan S13).
struct WalkScreen: View {
    let services: AppServices
    let journey: Journey

    private var walk: WalkLeg? {
        if case let .walk(walk) = journey.legs.first { return walk }
        return nil
    }

    private var nextRide: RideLeg? { journey.firstRide }

    var body: some View {
        ZStack(alignment: .top) {
            if let walk {
                JourneyMap(services: services, journey: Journey(legs: [.walk(walk)]), bottomInset: 400)
                    .overlay(alignment: .center) {
                        if let platform = nextRide?.boarding.platform.code {
                            KGSpeechBubble(Text("Ich warte an Steig \(platform)", bundle: .module), size: .small)
                                .offset(y: -150)
                        }
                    }
                VStack(spacing: 0) {
                    banner(walk)
                    Spacer()
                    KGSheetSurface { steps(walk) }
                        .frame(height: 400)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    /// The step the user is on: the one whose start is nearest ahead of them.
    private func currentIndex(_ walk: WalkLeg) -> Int {
        guard let here = services.location.coordinate, !walk.steps.isEmpty else { return 0 }
        let distances = walk.steps.map { $0.start.distance(to: here) }
        return distances.indices.min { distances[$0] < distances[$1] } ?? 0
    }

    private func banner(_ walk: WalkLeg) -> some View {
        let index = currentIndex(walk)
        let step = walk.steps.indices.contains(index) ? walk.steps[index] : nil
        return HStack(spacing: KGSpace.compact) {
            Button { services.router.back() } label: {
                KGIconView(.back, size: 22).foregroundStyle(KGColor.ink)
                    .frame(width: 52, height: 52)
                    .background(KGColor.glassFill, in: .circle)
                    .kgShadow(.floating, in: Circle())
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Zurück", bundle: .module))
            if let step {
                HStack(spacing: KGSpace.medium) {
                    KGIconView(WalkWords.icon(step.maneuver), size: 28)
                        .scaleEffect(x: WalkWords.mirrored(step.maneuver) ? -1 : 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: WalkWords.distance(step.metres)).kgFont(.titleL.sized(24)).monospacedDigit()
                        Text(verbatim: WalkWords.instruction(step)).kgFont(.callout.weighted(KGFont.bold)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(KGColor.white)
                .padding(.horizontal, KGSpace.mediumLarge)
                .padding(.vertical, KGSpace.compact)
                .background(KGColor.location, in: .kgRounded(KGRadius.search))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, KGSpace.screen)
        .padding(.top, 11)
    }

    private func steps(_ walk: WalkLeg) -> some View {
        let current = currentIndex(walk)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Fußweg zu \(walk.destinationName)", bundle: .module).kgFont(.titleL.sized(24))
                .foregroundStyle(KGColor.ink).accessibilityAddTraits(.isHeader)
            Text(verbatim: "\(String(localized: "\(max(1, Leg.walk(walk).minutes)) Min.", bundle: .module)) · "
                 + "\(WalkWords.distance(walk.metres)) · \(KGStrings.clock(walk.start)) – \(KGStrings.clock(walk.end))")
                .kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                .padding(.top, 2).padding(.bottom, KGSpace.small)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(walk.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(step, isCurrent: index == current)
                    }
                    arrival(walk)
                }
                .padding(.bottom, KGSpace.xl)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, KGSpace.large)
    }

    private func stepRow(_ step: WalkStep, isCurrent: Bool) -> some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(WalkWords.icon(step.maneuver), size: 18)
                .scaleEffect(x: WalkWords.mirrored(step.maneuver) ? -1 : 1)
                .foregroundStyle(isCurrent ? KGColor.white : KGColor.location)
                .frame(width: 36, height: 36)
                .background(isCurrent ? KGColor.location : KGColor.locationTint, in: .circle)
            Text(verbatim: WalkWords.instruction(step))
                .kgFont(.body.weighted(isCurrent ? KGFont.extraBold : KGFont.bold))
                .foregroundStyle(KGColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: WalkWords.distance(step.metres)).kgFont(.footnote.weighted(KGFont.bold))
                .foregroundStyle(KGColor.ink2)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, isCurrent ? KGSpace.large : 0)
        .background(isCurrent ? KGColor.locationTint.opacity(0.5) : .clear)
        .padding(.horizontal, isCurrent ? -KGSpace.large : 0)
        .overlay(alignment: .bottom) { Rectangle().fill(KGColor.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// "Ankunft Sternenplatz · Steig D · Bus 9A um 14:21" (S13.4).
    private func arrival(_ walk: WalkLeg) -> some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(.arrive, size: 18).foregroundStyle(KGColor.ink)
                .frame(width: 36, height: 36).background(KGColor.pressed, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text("Ankunft \(walk.destinationName)", bundle: .module).kgFont(.body.weighted(KGFont.extraBold))
                if let ride = nextRide {
                    Text(verbatim: [ride.boarding.platform.code.map { String(localized: "Steig \($0)", bundle: .module) },
                                    String(localized: "Bus \(ride.line.name) um \(KGStrings.clock(ride.start))",
                                           bundle: .module)].compactMap { $0 }.joined(separator: " · "))
                        .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                }
            }
            .foregroundStyle(KGColor.ink)
            Spacer()
        }
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }
}
