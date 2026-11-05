import KGCore
import KGDesign
import SwiftUI

/// On the trip: tells the user when a change won't work, with the way out one tap away. While all is well
/// it's a small button, for "I'm not going to make it" moments the app can't know about.
struct RescuePrompt: View {
    let risk: JourneyRisk
    let isSearching: Bool
    let onFind: () -> Void

    var body: some View {
        switch risk {
        case .fine:
            HStack {
                Spacer()
                Button(action: onFind) {
                    HStack(spacing: KGSpace.xs) {
                        KGIconView(.swap, size: 14)
                        Text("Andere Route", bundle: .module).kgFont(.footnote)
                    }
                    .foregroundStyle(KGColor.ink)
                    .padding(.horizontal, KGSpace.compact)
                    .frame(minHeight: 36)
                    .background(KGColor.glassFill, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(KGPressStyle())
                .accessibilityIdentifier("anotherRoute")
            }
        case .tight, .missed, .cancelled, .stopClosed:
            VStack(alignment: .leading, spacing: KGSpace.small) {
                HStack(alignment: .top, spacing: KGSpace.small) {
                    KGIconView(.bell, size: 18).foregroundStyle(KGColor.warn).padding(.top, 2)
                    RescueReason(risk: risk).kgFont(.callout).foregroundStyle(KGColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rescueReason")
                }
                KGButton(isSearching ? Text("Suche …", bundle: .module) : Text("Andere Route finden", bundle: .module),
                         icon: .swap, kind: risk.isBroken ? .primary : .secondary, action: onFind)
                    .accessibilityIdentifier("rescueButton")
            }
            .padding(KGSpace.compact)
            .background(KGColor.warn.opacity(0.14), in: .kgRounded(KGRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: KGRadius.card, style: .continuous)
                    .strokeBorder(KGColor.warn.opacity(0.55), lineWidth: 1)
            }
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }
}

/// In words: what's wrong with the journey.
struct RescueReason: View {
    let risk: JourneyRisk

    var body: some View { text }

    var text: Text {
        switch risk {
        case .fine:
            Text("Alles läuft nach Plan", bundle: .module)
        case let .tight(next, seconds):
            Text("Wird knapp: nur \(max(0, seconds)) Sek. bis Linie \(next.line.name).", bundle: .module)
        case let .missed(next, _):
            Text("Linie \(next.line.name) um \(KGStrings.clock(next.start)) schaffst du nicht.", bundle: .module)
        case let .cancelled(ride):
            Text("Linie \(ride.line.name) um \(KGStrings.clock(ride.start)) fällt aus.", bundle: .module)
        case let .stopClosed(ride, stop):
            Text("Linie \(ride.line.name) hält gerade nicht an \(stop).", bundle: .module)
        }
    }
}

/// The ways out, best first. One tap takes it.
struct RescueSheet: View {
    let risk: JourneyRisk
    let options: [RescueOption]
    let onTake: (RescueOption) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Andere Wege", bundle: .module).kgFont(.title).foregroundStyle(KGColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        if risk != .fine {
                            RescueReason(risk: risk).kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        }
                    }
                    Spacer()
                    KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain, action: onClose)
                }
                if options.isEmpty {
                    KGEmptyState(.sleepy, title: Text("Gerade kein anderer Weg", bundle: .module),
                                 message: Text("Bis zum Ziel fährt jetzt nichts anderes. Der aktuelle Weg bleibt dein bester.",
                                               bundle: .module))
                        .accessibilityIdentifier("noRescue")
                } else {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        RescueCard(option: option, isBest: index == 0) { onTake(option) }
                    }
                }
            }
            .padding(KGSpace.large)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }
}

private struct RescueCard: View {
    let option: RescueOption
    let isBest: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KGSpace.small) {
                HStack(alignment: .firstTextBaseline, spacing: KGSpace.small) {
                    Text("Ankunft \(KGStrings.clock(option.arrival))", bundle: .module)
                        .kgFont(.title).foregroundStyle(KGColor.ink)
                    if isBest { KGTag(Text("Beste", bundle: .module), tone: .live) }
                    Spacer()
                    difference.kgFont(.caption).foregroundStyle(option.minutesLater > 0 ? KGColor.warn : KGColor.live)
                }
                HStack(spacing: KGSpace.xs) {
                    ForEach(Array(option.journey.legs.enumerated()), id: \.offset) { index, leg in
                        if index > 0 { KGIconView(.chevronRight, size: 10).foregroundStyle(KGColor.chevron) }
                        switch leg {
                        case .ride(let ride): KGLineBadge(ride.line.name, size: .small)
                        case .walk: KGIconView(.walk, size: 15).foregroundStyle(KGColor.ink2)
                        }
                    }
                }
                instruction.kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(KGSpace.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
            .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityIdentifier("rescueOption")
    }

    private var difference: Text {
        let minutes = option.minutesLater
        if minutes > 0 { return Text("\(minutes) Min. später", bundle: .module) }
        if minutes < 0 { return Text("\(-minutes) Min. früher", bundle: .module) }
        return Text("Gleich schnell", bundle: .module)
    }

    /// The one thing to do next: "Steig an Sternenplatz aus, dann Linie 4 um 20:05."
    private var instruction: Text {
        let onward = option.getOffAt == nil ? option.journey.rides.first : option.journey.rides.dropFirst().first
        if let stop = option.getOffAt {
            if let onward {
                return Text("Steig an \(stop.shortName) aus, dann Linie \(onward.line.name) um \(KGStrings.clock(onward.start)).",
                            bundle: .module)
            }
            return Text("Steig an \(stop.shortName) aus und geh zu Fuß weiter.", bundle: .module)
        }
        if let onward {
            return Text("Linie \(onward.line.name) um \(KGStrings.clock(onward.start)) ab \(onward.boarding.station.shortName).",
                        bundle: .module)
        }
        return Text("Zu Fuß, \(option.journey.walkingMinutes) Min.", bundle: .module)
    }
}
