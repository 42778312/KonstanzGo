import KGDesign
import SwiftUI

/// Screen 01: coral, Seeri drives onto a white plate, the wordmark rises, the tagline fades in, three dots
/// pulse while the app gets ready. Tapping skips ahead (plan S1).
public struct StartScreen: View {
    /// Shorter on later launches (S1.4).
    let short: Bool
    let onDone: () -> Void
    @State private var plate = false
    @State private var drive = false
    @State private var title = false
    @State private var tagline = false
    @State private var dots = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(short: Bool = false, onDone: @escaping () -> Void) {
        self.short = short
        self.onDone = onDone
    }

    /// The design's full sequence ends with the dots at 1.6 s; we leave a beat later.
    static let fullLength = 2.2
    static let shortLength = 0.9

    public var body: some View {
        GeometryReader { proxy in
            // The design's frame is the whole 844 pt screen, safe areas included.
            let scale = (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) / 844
            ZStack(alignment: .top) {
                KGColor.coral.ignoresSafeArea()
                StartSea()
                    .frame(height: 144 * scale)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(KGColor.white)
                            .frame(width: 180, height: 180)
                            .scaleEffect(plate ? 1 : 0)
                        Seeri(.excited, sign: "GO!")
                            .frame(width: 160, height: 170)
                            .offset(x: drive ? 0 : -260)
                            .rotationEffect(.degrees(drive ? 0 : -6))
                            .padding(.top, 8)
                    }
                    .frame(height: 180)
                    .padding(.top, 228 * scale - proxy.safeAreaInsets.top)
                    Wordmark(size: 44, on: .coral)
                        .padding(.top, 32 * scale)
                        .opacity(title ? 1 : 0)
                        .offset(y: title ? 0 : KGMotion.riseDistance)
                    Text("Dein Bus durch Konstanz", bundle: .module)
                        .kgFont(.primaryButton)
                        .foregroundStyle(KGColor.white)
                        .padding(.top, KGSpace.large)
                        .opacity(tagline ? 1 : 0)
                    Spacer()
                    LoadingDots()
                        .opacity(dots ? 1 : 0)
                        .padding(.bottom, 64 * scale - proxy.safeAreaInsets.bottom)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(.rect)
        .onTapGesture { onDone() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("KonstanzGo. Dein Bus durch Konstanz", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Tippen zum Überspringen", bundle: .module))
        .task {
            if short || reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) {
                    plate = true; drive = true; title = true; tagline = true; dots = true
                }
            } else {
                // The design's timings (SeerotLaunch): plate 0.1 s, drive 0.45 s, title 1.2 s, tagline 1.45 s,
                // dots 1.6 s.
                withAnimation(KGMotion.progress.delay(0.1)) { plate = true }
                withAnimation(KGMotion.drive.delay(0.45)) { drive = true }
                withAnimation(KGMotion.rise.delay(1.2)) { title = true }
                withAnimation(.easeOut(duration: 0.5).delay(1.45)) { tagline = true }
                withAnimation(.easeOut(duration: 0.4).delay(1.6)) { dots = true }
            }
            try? await Task.sleep(for: .seconds(short ? Self.shortLength : Self.fullLength))
            onDone()
        }
    }

}

/// The darker sea band at the bottom of screen 01 with a moving wave.
private struct StartSea: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(&context, size: size, time: reduceMotion ? 0 : time)
            }
        }
        .accessibilityHidden(true)
    }
}

extension StartSea {
    static func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(KGColor.startSea))
        let shift = -CGFloat((time / 3).truncatingRemainder(dividingBy: 1)) * 80
        context.fill(Wave.path(width: size.width, amplitude: 10, shift: shift, closed: true),
                     with: .color(KGColor.startSea))
        let lineShift = -CGFloat((time / 4.5).truncatingRemainder(dividingBy: 1)) * 80
        let line = Wave.path(width: size.width, amplitude: 6, shift: lineShift, closed: false)
        context.stroke(line.offsetBy(dx: 0, dy: 40), with: .color(KGColor.white.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

/// The design's wave line: "q 20 −a 40 0 t 40 0 …", repeating every 80 pt, starting 80 pt off screen.
enum Wave {
    static func path(width: CGFloat, amplitude: CGFloat, shift: CGFloat, closed: Bool) -> Path {
        Path { path in
            var x = -80 + shift
            path.move(to: pt(x, 0))
            var up = true
            while x < width + 80 {
                path.addQuadCurve(to: pt(x + 40, 0), control: pt(x + 20, up ? -amplitude : amplitude))
                x += 40
                up.toggle()
            }
            if closed {
                path.addLine(to: pt(x, 20))
                path.addLine(to: pt(-80 + shift, 20))
                path.closeSubpath()
            }
        }
    }
}

/// Three white dots pulsing one after the other (k-dots, 1.2 s).
private struct LoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: KGSpace.small) {
                ForEach(0..<3) { index in
                    let value = reduceMotion ? 1 : Self.pulse((time - Double(index) * 0.15) / 1.2)
                    Circle().fill(KGColor.white)
                        .frame(width: 10, height: 10)
                        .scaleEffect(0.6 + 0.4 * value)
                        .opacity(0.4 + 0.6 * value)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 0 → 1 → 0 between 0 % and 80 % of a cycle, resting after.
    static func pulse(_ cycles: Double) -> Double {
        let phase = cycles - cycles.rounded(.down)
        guard phase < 0.8 else { return 0 }
        return 1 - abs(phase / 0.4 - 1)
    }
}
