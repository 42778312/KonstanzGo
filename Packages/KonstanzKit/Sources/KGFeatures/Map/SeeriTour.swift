import KGCore
import KGDesign
import SwiftUI

/// The parts of the map screen the tour points at.
enum TourSpot: Hashable, Sendable { case search, mic, seeri, controls, more }

/// Where each part is on screen, for the tour's spotlight.
struct TourAnchors: PreferenceKey {
    static var defaultValue: [TourSpot: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [TourSpot: Anchor<CGRect>], nextValue: () -> [TourSpot: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as a stop of Seeri's tour.
    func tourSpot(_ spot: TourSpot) -> some View {
        anchorPreference(key: TourAnchors.self, value: .bounds) { [spot: $0] }
    }
}

/// Seeri's tour of the map: the screen dims, a spotlight moves from the search bar to the microphone, a stop,
/// a long press, the moving buses, the map buttons and Seeri's own menu, and Seeri drives along with a speech
/// bubble at each, tilting and bouncing as it goes. "Überspringen" ends it any time; a tap anywhere goes on.
/// Starts by itself after onboarding, and again from Mehr › "Tour mit Seeri".
struct SeeriTour: View {
    let anchors: [TourSpot: Anchor<CGRect>]
    let onEnd: () -> Void
    @State private var step = 0
    @State private var tilt = 0.0
    @State private var leaving = false
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A demonstration drawn in the spotlight where there is no button to point at.
    enum Demo { case tapStop, longPress, vehicles }

    struct Step {
        var spot: TourSpot?
        var demo: Demo?
        var seeri: Seeri.Expression
        var text: Text
    }

    static let steps: [Step] = [
        Step(seeri: .excited,
             text: Text("Hallo, ich bin Seeri, dein Bus. Komm, ich zeig dir schnell, wie alles geht.", bundle: .module)),
        Step(spot: .search, seeri: .looking,
             text: Text("Tippe hier und such dein Ziel: Haltestelle, Straße oder Ort.", bundle: .module)),
        Step(spot: .mic, seeri: .happy,
             text: Text("Keine Lust zu tippen? Sag's mir einfach. Klappt sogar ohne Internet.", bundle: .module)),
        Step(demo: .tapStop, seeri: .curious,
             text: Text("Tipp auf eine Haltestelle, dann siehst du, wann welcher Bus fährt.", bundle: .module)),
        Step(demo: .longPress, seeri: .focused,
             text: Text("Halte die Karte gedrückt – zack, da ist dein Ziel", bundle: .module)),
        Step(demo: .vehicles, seeri: .joyful,
             text: Text("Die roten Busse fahren nach Fahrplan mit. Die gelben fahren nach Kreuzlingen.", bundle: .module)),
        Step(spot: .controls, seeri: .happy,
             text: Text("Hier findest du dich selbst und schaltest Busse und Haltestellen an und aus.", bundle: .module)),
        Step(spot: .seeri, seeri: .excited,
             text: Text("Und hier wohne ich. Wenn mein Blaulicht blinkt, ist was los: Tipp mich an für die Meldungen.", bundle: .module)),
        Step(spot: .more, seeri: .joyful,
             text: Text("Zieh die Suchleiste nach oben: Favoriten und Einstellungen.", bundle: .module)),
        Step(seeri: .joyful, text: Text("Fertig. Gute Fahrt durch Konstanz.", bundle: .module)),
    ]

    private var current: Step { Self.steps[step] }
    private var isLast: Bool { step == Self.steps.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let hole = hole(in: proxy)
            ZStack(alignment: .topLeading) {
                Spotlight(hole: hole ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0),
                          radius: current.demo == nil ? 24 : 120)
                    .fill(.black.opacity(0.62), style: FillStyle(eoFill: true))
                if let hole {
                    RoundedRectangle(cornerRadius: current.demo == nil ? 24 : 120, style: .continuous)
                        .stroke(KGColor.coral, lineWidth: 3)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .modifier(Breathing(active: !reduceMotion))
                    if let demo = current.demo {
                        DemoView(demo: demo)
                            .frame(width: hole.width, height: hole.height)
                            .position(x: hole.midX, y: hole.midY)
                            .id(step)
                    }
                }
                guide
                    .frame(width: min(size.width - 32, 330))
                    .position(guidePoint(size: size, hole: hole))
                // Level with the weather, clear of the status bar (the overlay ignores the safe area).
                skip
                    .position(x: size.width - 80, y: 72)
            }
            .contentShape(.rect)
            .onTapGesture { next() }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .onAppear {
            withAnimation(Self.drive(reduceMotion)) { arrived = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Parts

    /// Seeri with its speech bubble and the buttons, driving between the stops of the tour.
    private var guide: some View {
        VStack(spacing: KGSpace.xs) {
            KGSpeechBubble(current.text, size: .small)
                .id(step)
                .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                .accessibilityIdentifier("tourText")
            HStack(alignment: .bottom, spacing: KGSpace.medium) {
                SeeriAlive(current.seeri, detail: .full, shadow: true)
                    .frame(width: 74, height: 80)
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .offset(x: leaving ? 500 : (arrived ? 0 : -400))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: KGSpace.small) {
                    dots
                    KGButton(isLast ? Text("Los geht's", bundle: .module) : Text("Weiter", bundle: .module)) { next() }
                        .accessibilityIdentifier("tourNext")
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Self.steps.indices, id: \.self) { index in
                Capsule().fill(index == step ? KGColor.coral : KGColor.white.opacity(0.35))
                    .frame(width: index == step ? 16 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.3), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text("Schritt \(step + 1) von \(Self.steps.count)", bundle: .module))
    }

    private var skip: some View {
        Button(action: finish) {
            Text("Überspringen", bundle: .module)
                .kgFont(.callout.weighted(KGFont.bold))
                .foregroundStyle(KGColor.white)
                .padding(.horizontal, KGSpace.mediumLarge)
                .frame(minHeight: 40)
                .background(.white.opacity(0.18), in: .capsule)
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(KGPressStyle())
        .accessibilityIdentifier("tourSkip")
    }

    // MARK: Layout

    /// The spotlight: around the part the step is about, or a circle in the map for the demonstrations.
    private func hole(in proxy: GeometryProxy) -> CGRect? {
        if let spot = current.spot, let anchor = anchors[spot] {
            return proxy[anchor].insetBy(dx: -8, dy: -8)
        }
        guard current.demo != nil else { return nil }
        let size = proxy.size
        return CGRect(x: size.width / 2 - 110, y: size.height * 0.3 - 110, width: 220, height: 220)
    }

    /// Seeri parks above the spotlight when it is low on the screen, below it when it is high.
    private func guidePoint(size: CGSize, hole: CGRect?) -> CGPoint {
        guard let hole else { return CGPoint(x: size.width / 2, y: size.height * 0.5) }
        if hole.midY > size.height * 0.55 {
            return CGPoint(x: size.width / 2, y: max(170, hole.minY - 130))
        }
        return CGPoint(x: size.width / 2, y: min(size.height - 170, hole.maxY + 140))
    }

    // MARK: Actions

    private func next() {
        guard !isLast else { return finish() }
        // A little lean into the drive, then upright again.
        withAnimation(.easeOut(duration: 0.18)) { tilt = -9 }
        withAnimation(Self.drive(reduceMotion)) { step += 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { tilt = 0 }
        }
    }

    /// Seeri drives off to the right, then the tour fades away.
    private func finish() {
        withAnimation(.easeIn(duration: reduceMotion ? 0 : 0.45)) { leaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 400))
            onEnd()
        }
    }

    private static func drive(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.72)
    }
}

/// The dim layer with a rounded hole that moves smoothly from one part to the next.
private struct Spotlight: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let corner = min(radius, hole.width / 2, hole.height / 2)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        return path
    }
}

/// The spotlight's ring breathes a little.
private struct Breathing: ViewModifier {
    let active: Bool
    @State private var out = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(out ? 1.04 : 1)
            .opacity(out ? 0.7 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { out = true }
            }
    }
}

/// What happens in the map, acted out: a finger tapping a stop, a finger holding until a pin drops, and a red
/// and a yellow bus driving past.
private struct DemoView: View {
    let demo: SeeriTour.Demo
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch demo {
            case .tapStop:
                KGStopMarker("", isSelected: phase, showsName: false)
                finger.offset(x: 18, y: phase ? 22 : 40)
            case .longPress:
                Circle().trim(from: 0, to: phase ? 1 : 0)
                    .stroke(KGColor.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                KGIconView(.pinFilled, size: 40).foregroundStyle(KGColor.coral)
                    .offset(y: phase ? -24 : -90)
                    .opacity(phase ? 1 : 0)
                finger.offset(x: 14, y: 30)
            case .vehicles:
                VStack(spacing: 26) {
                    KGVehicleMarker(line: "5", heading: .degrees(90)).offset(x: phase ? 70 : -70)
                    KGVehicleMarker(line: "908", isKreuzlingen: true, heading: .degrees(270)).offset(x: phase ? -70 : 70)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return phase = true }
            let animation: Animation = switch demo {
            case .tapStop: .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
            case .longPress: .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
            case .vehicles: .linear(duration: 2.6).repeatForever(autoreverses: true)
            }
            withAnimation(animation) { phase = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A fingertip: a white dot with a soft ring.
    private var finger: some View {
        Circle().fill(.white.opacity(0.9))
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 8).scaleEffect(1.5))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
