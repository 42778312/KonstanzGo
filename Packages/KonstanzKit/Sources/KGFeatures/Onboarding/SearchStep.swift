import KGDesign
import SwiftUI

/// Screen 04: "Sag mir, wohin du willst." A search field types "Universität", the result pops up and is
/// tapped, then a bus rides along a line towards it while the minutes count down.
struct SearchStep: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                SeeriSays(expression: .looking, text: Text("Sag mir, wohin du willst.", bundle: .module))
                SearchDemo()
                    .padding(.horizontal, KGSpace.xxl)
                    .padding(.top, 24)
                Spacer(minLength: KGSpace.xl)
                FeatureList(rows: [
                    FeatureRow(icon: .search, title: Text("Schnell finden", bundle: .module),
                               detail: Text("Haltestellen, Straßen und Orte", bundle: .module)),
                    // "Live-Abfahrten" in the design; there is no live feed, so the honest wording (plan 0.3).
                    FeatureRow(icon: .clock, title: Text("Abfahrten auf einen Blick", bundle: .module),
                               detail: Text("Sieh, wann dein Bus kommt", bundle: .module)),
                ], delay: 1.2)
                Spacer(minLength: KGSpace.large)
            }
        } buttons: {
            KGButton(Text("Weiter", bundle: .module), action: onNext)
        }
    }
}

/// The animated search of screen 04, following the design's timings (SeerotSearch.dc.html).
private struct SearchDemo: View {
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let query = "Universität"

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 4 : timeline.date.timeIntervalSince(start)
            VStack(spacing: KGSpace.medium) {
                field(elapsed)
                    .riseIn(after: 0.6)
                result(elapsed)
                    .popIn(after: 2.1)
                RideLine(elapsed: elapsed)
                    .padding(.top, 14)
                    .opacity(elapsed > 3.1 ? min((elapsed - 3.1) / 0.5, 1) : 0)
            }
        }
        .onAppear { start = .now }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Beispiel: Suche nach Universität, Linie 9A", bundle: .module))
    }

    /// k-type: one letter every 1/11 s from 1 s; the coral caret blinks every second.
    private func field(_ elapsed: Double) -> some View {
        let letters = min(max(Int((elapsed - 1) * 11), 0), Self.query.count)
        let caretOn = Int(elapsed * 2).isMultiple(of: 2)
        return HStack(spacing: KGSpace.small) {
            KGIconView(.search, size: 18).foregroundStyle(KGColor.ink3)
            Text(verbatim: String(Self.query.prefix(letters)))
                .kgFont(.bodyMedium.weighted(KGFont.regular))
                .foregroundStyle(KGColor.ink)
            Capsule().fill(KGColor.coral)
                .frame(width: 2, height: 22)
                .opacity(caretOn ? 1 : 0)
                .padding(.leading, -6)
            Spacer()
        }
        .padding(.horizontal, KGSpace.medium)
        .frame(height: 44)
        .background(KGColor.card, in: .kgRounded(KGRadius.medium))
    }

    /// The result card, with a coral ripple when it is "tapped" at 2.9 s.
    private func result(_ elapsed: Double) -> some View {
        let tap = min(max((elapsed - 2.9) / 0.7, 0), 1)
        return HStack(spacing: KGSpace.medium) {
            KGIconView(.bus, size: 22)
                .foregroundStyle(KGColor.white)
                .frame(width: 40, height: 40)
                .background(KGColor.coral, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: Self.query).kgFont(.bodyMedium).foregroundStyle(KGColor.ink)
                Text("Haltestelle", bundle: .module).kgFont(.footnote.weighted(KGFont.regular))
                    .foregroundStyle(KGColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            KGLineBadge("9A")
        }
        .padding(.horizontal, KGSpace.mediumLarge)
        .frame(height: 64)
        .background {
            ZStack {
                KGColor.card
                Circle().fill(KGColor.coral)
                    .frame(width: 40, height: 40)
                    .scaleEffect(1 + 5 * tap)
                    .opacity(tap > 0 && tap < 1 ? 0.35 * (1 - tap) : 0)
            }
        }
        .clipShape(.kgRounded(KGRadius.option))
    }
}

/// A line from here to Universität: the bus drives along it (4.5 s loop from 3.2 s), the coral trail
/// follows, and a black chip counts the minutes down 5 → "jetzt".
private struct RideLine: View {
    let elapsed: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let loop = max(elapsed - 3.2, 0).truncatingRemainder(dividingBy: 4.5) / 4.5
            let progress = Self.ease(min(loop / 0.85, 1))
            let travel = width - 72
            ZStack(alignment: .topLeading) {
                Capsule().fill(KGColor.line).frame(height: 8)
                    .padding(.horizontal, KGSpace.screen).offset(y: 62)
                Capsule().fill(KGColor.trail).frame(width: max(0, (width - 32) * progress), height: 8)
                    .offset(x: KGSpace.screen, y: 62)
                stop.offset(x: 7, y: 57)
                stop.offset(x: width / 2 - 9, y: 57)
                Circle().fill(KGColor.ink)
                    .overlay(Circle().strokeBorder(KGColor.surface, lineWidth: 5))
                    .padding(-2)
                    .background(Circle().fill(KGColor.coral).padding(-2))
                    .frame(width: 24, height: 24)
                    .offset(x: width - 28, y: 54)
                MiniBus().offset(x: travel * progress, y: 36)
                etaChip.frame(maxWidth: .infinity, alignment: .trailing)
                Text(verbatim: "Universität")
                    .kgFont(.caption.weighted(KGFont.semiBold))
                    .foregroundStyle(KGColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 84)
            }
        }
        .frame(height: 100)
    }

    private var stop: some View {
        Circle().fill(KGColor.surface)
            .overlay(Circle().strokeBorder(KGColor.coral, lineWidth: 4))
            .frame(width: 18, height: 18)
    }

    /// Counts 5, 4 … 1 Min., "jetzt", once every 0.75 s, like the design.
    private var etaChip: some View {
        let tick = Int(max(elapsed - 3.1, 0) / 0.75) % 6
        let minutes = 5 - tick
        return Group {
            if minutes == 0 {
                Text("jetzt", bundle: .module)
            } else {
                Text("\(minutes) Min.", bundle: .module)
            }
        }
        .kgFont(.callout.weighted(KGFont.bold))
        .monospacedDigit()
        .foregroundStyle(KGColor.white)
        .contentTransition(.numericText(countsDown: true))
        .padding(.horizontal, KGSpace.medium)
        .frame(height: 30)
        .background(Color.black, in: .capsule)
        .animation(.default, value: minutes)
    }

    /// cubic-bezier(.45, 0, .3, 1), close enough as a smoothstep.
    static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

/// The 46 × 26 bus of the ride line, bobbing.
private struct MiniBus: View {
    @State private var bob = false

    var body: some View {
        Canvas { context, _ in
            context.fill(Path(roundedRect: CGRect(x: 1, y: 2, width: 44, height: 18), cornerRadius: 6),
                         with: .color(KGColor.coral))
            for (x, width, height) in [(5.0, 8.0, 6.0), (15, 8, 6), (25, 7, 6), (35, 8, 9)] {
                context.fill(Path(roundedRect: CGRect(x: x, y: 5, width: width, height: height), cornerRadius: 1.5),
                             with: .color(KGColor.seeriFace))
            }
            context.fill(Path(roundedRect: CGRect(x: 1, y: 15, width: 44, height: 5), cornerRadius: 2.5),
                         with: .color(KGColor.seeriDark))
            for x in [11.0, 35] {
                let wheel = CGRect(x: x - 3.6, y: 17.4, width: 7.2, height: 7.2)
                context.fill(Path(ellipseIn: wheel), with: .color(.black))
            }
        }
        .frame(width: 46, height: 26)
        .offset(y: bob ? -1.5 : 0)
        .kgLoop(.busBob, phase: $bob)
    }
}
