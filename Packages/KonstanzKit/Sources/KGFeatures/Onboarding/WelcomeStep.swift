import KGDesign
import SwiftUI

/// Screen 02: Seeri drives in over the lake with a "GO" sign and says hello.
struct WelcomeStep: View {
    let onNext: () -> Void
    @State private var drive = false
    @State private var bubble = false
    @State private var title = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage {
            GeometryReader { proxy in
                // The design places everything on its 844 pt frame; the header above takes 55 of it.
                let scale = min(1, proxy.size.height / 690)
                ZStack(alignment: .top) {
                    LakeScene()
                        .frame(height: 300)
                        .offset(y: 194 * scale)
                    if bubble {
                        KGSpeechBubble(Text("Hallo, ich bin Seeri und bring dich durch ganz Konstanz.",
                                            bundle: .module))
                            .padding(.horizontal, 40)
                            .padding(.top, 48 * scale)
                    }
                    SeeriAlive(.excited, sign: "GO")
                        .frame(width: 200, height: 212)
                        .offset(x: drive ? 0 : 320)
                        .rotationEffect(.degrees(drive ? 0 : 6))
                        .offset(y: 198 * scale)
                    Text("Willkommen bei KonstanzGo", bundle: .module)
                        .kgFont(.display.sized(28))
                        .tracking(-0.28)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(KGColor.ink)
                        .padding(.horizontal, KGSpace.xl)
                        .opacity(title ? 1 : 0)
                        .offset(y: 534 * scale + (title ? 0 : KGMotion.riseDistance))
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
            }
        } buttons: {
            KGButton(Text("Los geht's", bundle: .module), action: onNext)
        }
        .onAppear {
            let quick = reduceMotion
            withAnimation(quick ? .easeOut(duration: 0.2) : KGMotion.drive.speed(2).delay(0.05)) { drive = true }
            withAnimation(quick ? nil : .default.delay(0.35)) { bubble = true }
            withAnimation(quick ? .easeOut(duration: 0.2) : KGMotion.rise.delay(0.4)) { title = true }
        }
    }
}

/// The lake behind Seeri on screen 02: town silhouette (church, tower, houses), two gulls, the water with
/// two moving wave lines. Drawn on the design's 390 × 300 grid.
struct LakeScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            // The town rises in on its own (k-sky, 0.8 s from 0.2 s).
            Canvas { context, size in
                context.scaleBy(x: size.width / 390, y: size.width / 390)
                context.fill(Self.town, with: .color(KGColor.sceneTown))
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 30)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    Self.draw(&context, size: size, time: time)
                }
            }
        }
        .onAppear {
            withAnimation(KGMotion.animation(KGMotion.rise, reduceMotion: reduceMotion)?.delay(0)) { shown = true }
        }
        .accessibilityHidden(true)
    }

    /// Gulls, water and waves at `time`.
    static func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let scale = size.width / 390
        context.scaleBy(x: scale, y: scale)
        let gulls = [Gull(start: pt(300, 40), phase: 0, cycle: 4, wing: 6),
                     Gull(start: pt(110, 70), phase: 1, cycle: 5, wing: 5)]
        for gull in gulls {
            let cycle = ((time + gull.phase) / gull.cycle).truncatingRemainder(dividingBy: 1)
            let bob = CGFloat(sin(cycle * .pi))
            let path = Self.gull(at: pt(gull.start.x + 14 * bob, gull.start.y - 8 * bob), wing: gull.wing)
            context.stroke(path, with: .color(KGColor.sceneGull), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        context.fill(Path(CGRect(x: 0, y: 200, width: 390, height: 100)), with: .color(KGColor.mapWater))
        for wave in [WaveLine(y: 236, cycle: 4, opacity: 1), WaveLine(y: 268, cycle: 6, opacity: 0.7)] {
            let shift = -CGFloat((time / wave.cycle).truncatingRemainder(dividingBy: 1)) * 80
            let path = Wave.path(width: 390, amplitude: 6, shift: shift, closed: false)
            context.stroke(path.offsetBy(dx: 0, dy: wave.y), with: .color(KGColor.white.opacity(wave.opacity)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// A gull bobbing from `start` (k-gull): `cycle` seconds, `phase` seconds late.
    struct Gull {
        var start: CGPoint
        var phase: Double
        var cycle: Double
        var wing: CGFloat
    }

    /// A white wave line across the water, moving left 80 pt every `cycle` seconds.
    struct WaveLine {
        var y: CGFloat
        var cycle: Double
        var opacity: Double
    }

    /// The silhouette from SeerotWelcome, one path.
    static let town: Path = Path { path in
        path.addLines([pt(40, 200), pt(52, 200), pt(50, 128), pt(42, 128)])
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: 39, y: 114, width: 14, height: 14), cornerSize: CGSize(width: 3, height: 3))
        path.addLines([pt(38, 114), pt(46, 104), pt(54, 114)])
        path.closeSubpath()
        path.addLines([pt(66, 164), pt(170, 164), pt(154, 134), pt(82, 134)])
        path.closeSubpath()
        path.addRect(CGRect(x: 72, y: 164, width: 92, height: 36))
        path.addRect(CGRect(x: 250, y: 96, width: 30, height: 104))
        path.addLines([pt(250, 96), pt(265, 36), pt(280, 96)])
        path.closeSubpath()
        path.addRect(CGRect(x: 280, y: 150, width: 42, height: 50))
        path.addLines([pt(280, 150), pt(301, 136), pt(322, 150)])
        path.closeSubpath()
        path.addLines([pt(330, 200), pt(330, 160), pt(346, 146),
                       pt(362, 160), pt(362, 200)])
        path.closeSubpath()
    }

    /// "M x y q w −w 2w 0 q w −w 2w 0": a gull as two arcs.
    static func gull(at start: CGPoint, wing: CGFloat) -> Path {
        Path { path in
            path.move(to: start)
            path.addQuadCurve(to: pt(start.x + 2 * wing, start.y),
                              control: pt(start.x + wing, start.y - wing))
            path.addQuadCurve(to: pt(start.x + 4 * wing, start.y),
                              control: pt(start.x + 3 * wing, start.y - wing))
        }
    }
}
