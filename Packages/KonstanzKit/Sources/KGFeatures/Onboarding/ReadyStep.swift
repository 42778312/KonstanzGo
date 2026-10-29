import KGDesign
import SwiftUI

/// Screen 06: confetti, Seeri jumping for joy, "Alles bereit!", what is done, "Losfahren".
struct ReadyStep: View {
    let notificationsOn: Bool
    let onFinish: () -> Void
    @State private var entered = false
    @State private var burst = false
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Confetti().ignoresSafeArea()
            OnboardingPage {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(KGColor.pressed)
                            .frame(width: 200, height: 200)
                            .scaleEffect(burst ? 2.6 : 0.4)
                            .opacity(burst ? 0 : 0.5)
                        JumpingSeeri(start: start)
                            .frame(width: 200, height: 212)
                            .scaleEffect(entered ? 1 : 0.2)
                            .offset(y: entered ? 0 : 60)
                            .opacity(entered ? 1 : 0)
                    }
                    .padding(.top, 155)
                    Text("Alles bereit!", bundle: .module)
                        .kgFont(.display.sized(34))
                        .tracking(-0.34)
                        .foregroundStyle(KGColor.ink)
                        .padding(.top, 48)
                        .popIn(after: 0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text("Gute Fahrt durch Konstanz.", bundle: .module)
                        .kgFont(.bodyMedium.weighted(KGFont.regular))
                        .foregroundStyle(KGColor.ink2)
                        .padding(.top, KGSpace.small)
                        .riseIn(after: 1)
                    HStack(spacing: KGSpace.compact) {
                        DoneChip(title: Text("Offline gespeichert", bundle: .module)).popIn(after: 1.2)
                        if notificationsOn {
                            DoneChip(title: Text("Alarme an", bundle: .module)).popIn(after: 1.35)
                        }
                    }
                    .padding(.top, KGSpace.xl)
                }
                .frame(maxWidth: .infinity)
            } buttons: {
                KGButton(Text("Losfahren", bundle: .module), action: onFinish)
                    .accessibilityIdentifier("finishOnboarding")
            }
        }
        .onAppear {
            start = .now
            let quick = reduceMotion
            withAnimation(quick ? .easeOut(duration: 0.2) : KGMotion.pop) { entered = true }
            if !quick { withAnimation(.easeOut(duration: 0.8).delay(0.1)) { burst = true } }
        }
    }
}

/// Green check in a grey capsule: "Offline gespeichert", "Alarme an".
private struct DoneChip: View {
    let title: Text

    var body: some View {
        HStack(spacing: KGSpace.small) {
            KGIconView(.check, size: 12)
                .foregroundStyle(KGColor.white)
                .frame(width: 24, height: 24)
                .background(KGColor.live, in: .circle)
            title.kgFont(.callout).foregroundStyle(KGColor.ink)
        }
        .padding(.leading, KGSpace.compact)
        .padding(.trailing, KGSpace.mediumLarge)
        .frame(minHeight: 40)
        .background(KGColor.card, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Seeri with the "GO!" sign jumping (k-jump, 1.3 s from 1 s) over a shadow that shrinks while in the air.
private struct JumpingSeeri: View {
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start) - 0.4
            let t = reduceMotion || elapsed < 0 ? 0 : (elapsed / 1.3).truncatingRemainder(dividingBy: 1)
            let pose = Self.pose(t)
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color.black.opacity(pose.shadowOpacity))
                    .frame(width: 120 * pose.shadowScale, height: 15 * pose.shadowScale)
                    .offset(y: -4)
                SeeriAlive(.joyful, sign: "GO!")
                    .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
                    .offset(y: pose.lift)
            }
        }
        .accessibilityHidden(true)
    }

    struct Pose {
        var lift: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation: Double = 0
        var shadowScale: CGFloat = 1
        var shadowOpacity: Double = 0.14
    }

    /// The design's keyframes: squash, stretch, up 34 pt tilting −4° then 4°, land with a squash.
    static func pose(_ t: Double) -> Pose {
        let keys: [(t: Double, pose: Pose)] = [
            (0, Pose(scaleX: 1.05, scaleY: 0.95)),
            (0.15, Pose(scaleX: 0.95, scaleY: 1.06)),
            (0.45, Pose(lift: -34, rotation: -4, shadowScale: 0.6, shadowOpacity: 0.06)),
            (0.6, Pose(lift: -34, rotation: 4, shadowScale: 0.6, shadowOpacity: 0.06)),
            (0.85, Pose(scaleX: 1.06, scaleY: 0.94)),
            (1, Pose(scaleX: 1.05, scaleY: 0.95)),
        ]
        for index in 1..<keys.count where t <= keys[index].t {
            let (a, b) = (keys[index - 1], keys[index])
            let f = CGFloat((t - a.t) / (b.t - a.t))
            let smooth = f * f * (3 - 2 * f)
            func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * smooth }
            return Pose(lift: mix(a.pose.lift, b.pose.lift), scaleX: mix(a.pose.scaleX, b.pose.scaleX),
                        scaleY: mix(a.pose.scaleY, b.pose.scaleY),
                        rotation: Double(mix(CGFloat(a.pose.rotation), CGFloat(b.pose.rotation))),
                        shadowScale: mix(a.pose.shadowScale, b.pose.shadowScale),
                        shadowOpacity: Double(mix(CGFloat(a.pose.shadowOpacity), CGFloat(b.pose.shadowOpacity))))
        }
        return Pose()
    }
}

/// 14 pieces of confetti falling and spinning (k-confetti), each with its own size, colour and timing from
/// the design. Nothing falls with Reduce Motion.
private struct Confetti: View {
    struct Piece {
        var x: CGFloat
        var size: CGSize
        var color: Color
        var duration: Double
        var delay: Double
        /// Square pieces are drawn as dots, the others as rounded strips.
        var round: Bool { size.width == size.height }

        init(_ x: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color, _ duration: Double, _ delay: Double) {
            self.x = x
            size = CGSize(width: width, height: height)
            self.color = color
            self.duration = duration
            self.delay = delay
        }
    }

    static let pieces: [Piece] = [
        Piece(31, 10, 16, KGColor.coral, 3.2, 0.5),
        Piece(70, 12, 12, KGColor.lineFill, 3.8, 0.9),
        Piece(105, 8, 18, KGColor.live, 3.4, 0.2),
        Piece(140, 12, 10, KGColor.location, 4, 1.3),
        Piece(179, 10, 16, KGColor.seeriCheek, 3.6, 0.7),
        Piece(214, 12, 12, KGColor.coral, 3.3, 1.6),
        Piece(250, 8, 18, KGColor.lineFill, 3.9, 0.4),
        Piece(285, 12, 10, KGColor.live, 3.5, 1.1),
        Piece(320, 10, 16, KGColor.location, 3.7, 0.6),
        Piece(355, 12, 12, KGColor.coral, 3.1, 1.4),
        Piece(51, 8, 14, KGColor.location, 4.2, 2),
        Piece(160, 10, 10, KGColor.lineFill, 3.6, 2.3),
        Piece(269, 8, 16, KGColor.seeriCheek, 4.1, 1.8),
        Piece(339, 10, 14, KGColor.live, 3.4, 2.6),
    ]

    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    Self.draw(&context, size: size, elapsed: timeline.date.timeIntervalSince(start))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { start = .now }
        }
    }

    static func draw(_ context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let scale = size.width / 390
        for piece in pieces {
            let time = elapsed - piece.delay
            guard time > 0 else { continue }
            let t = (time / piece.duration).truncatingRemainder(dividingBy: 1)
            let opacity = t < 0.1 ? t / 0.1 : 1 - (t - 0.1) / 0.9
            var layer = context
            layer.opacity = opacity
            layer.translateBy(x: piece.x * scale + piece.size.width / 2, y: 38 - 60 + 560 * t + piece.size.height / 2)
            layer.rotate(by: .degrees(620 * t))
            let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                              width: piece.size.width, height: piece.size.height)
            let path = piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 3)
            layer.fill(path, with: .color(piece.color))
        }
    }
}
