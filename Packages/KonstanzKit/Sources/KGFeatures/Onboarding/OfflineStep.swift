import KGDesign
import SwiftUI

/// Screen 03: "Kein Netz? Kein Problem!" with a little map that draws its roads, buses driving on them, and
/// a "no signal" badge with a green check.
struct OfflineStep: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                SeeriSays(expression: .happy, text: Text("Kein Netz? Kein Problem!", bundle: .module))
                Spacer(minLength: KGSpace.large)
                OfflineMapCard()
                    .frame(width: 310, height: 270)
                Spacer(minLength: KGSpace.xl)
                FeatureList(rows: [
                    FeatureRow(icon: .map, title: Text("Offline-Karte", bundle: .module),
                               detail: Text("Ganz Konstanz, auch ohne Internet", bundle: .module)),
                    FeatureRow(icon: .pin, title: Text("Alle Haltestellen", bundle: .module),
                               detail: Text("Jede Linie, jeder Fahrplan", bundle: .module)),
                ], delay: 1.9)
                Spacer(minLength: KGSpace.large)
            }
        } buttons: {
            KGButton(Text("Weiter", bundle: .module), action: onNext)
        }
    }
}

/// The map card of screen 03 (310 × 270, radius 36): land, lake and Rhine, two parks, white roads that draw
/// themselves, stops that pop in, and two buses driving.
struct OfflineMapCard: View {
    @State private var appeared = false
    @State private var roads = false
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let elapsed = reduceMotion ? 10 : Tempo.clock(timeline.date.timeIntervalSince(start), intro: 2.6)
                Canvas { context, _ in
                    Self.drawMap(&context, elapsed: elapsed)
                }
            }
            .clipShape(.rect(cornerRadius: 36, style: .continuous))
            OfflineBadge()
                .offset(x: 14, y: -18)
                .popIn(after: 1.3)
        }
        .scaleEffect(appeared ? 1 : 0.85)
        .rotationEffect(.degrees(appeared ? 0 : -3))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            start = .now
            withAnimation(KGMotion.animation(KGMotion.pop, reduceMotion: reduceMotion)?.delay(0.1)) { appeared = true }
        }
        .accessibilityHidden(true)
    }

    /// Draws the card at `elapsed` seconds after it appeared, following the design's timings.
    static func drawMap(_ context: inout GraphicsContext, elapsed: Double) {
        drawGround(&context)
        drawRoads(&context, elapsed: elapsed)
        drawTraffic(&context, elapsed: elapsed)
    }

    /// Land, the lake and the Rhine, two parks.
    private static func drawGround(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 310, height: 270)), with: .color(KGColor.mapLand))
        let water = KGColor.mapWater
        context.fill(Path { path in
            path.move(to: pt(180, 0))
            path.addLine(to: pt(310, 0))
            path.addLine(to: pt(310, 170))
            path.addCurve(to: pt(225, 122), control1: pt(280, 150), control2: pt(250, 130))
            path.addCurve(to: pt(180, 0), control1: pt(200, 114), control2: pt(188, 70))
            path.closeSubpath()
        }, with: .color(water))
        context.fill(Path { path in
            path.move(to: pt(225, 122))
            path.addCurve(to: pt(0, 150), control1: pt(180, 140), control2: pt(120, 140))
            path.addLine(to: pt(0, 172))
            path.addCurve(to: pt(240, 140), control1: pt(120, 164), control2: pt(190, 160))
            path.closeSubpath()
        }, with: .color(water))
        for park in [CGRect(x: 22, y: 24, width: 72, height: 52), CGRect(x: 210, y: 236, width: 80, height: 50)] {
            context.fill(Path(roundedRect: park, cornerRadius: 16), with: .color(KGColor.mapPark))
        }
    }

    /// A road that draws itself (k-draw) from `delay` over `duration` seconds.
    private struct Road {
        var path: Path
        var width: CGFloat
        var delay: Double
        var duration: Double
    }

    private static let roads = [
        Road(path: Path { path in
            path.move(to: pt(120, 0))
            path.addCurve(to: pt(138, 150), control1: pt(126, 70), control2: pt(130, 110))
            path.addLine(to: pt(150, 270))
        }, width: 10, delay: 0.9, duration: 1),
        Road(path: line(0, 218, 310, 218), width: 10, delay: 1.0, duration: 1),
        Road(path: line(70, 172, 70, 270), width: 7, delay: 1.1, duration: 0.8),
        Road(path: Path { path in
            path.move(to: pt(0, 96))
            path.addCurve(to: pt(124, 92), control1: pt(60, 100), control2: pt(100, 96))
        }, width: 7, delay: 1.2, duration: 0.8),
    ]

    private static func drawRoads(_ context: inout GraphicsContext, elapsed: Double) {
        for road in roads {
            let progress = easeInOut(min(max((elapsed - road.delay) / road.duration, 0), 1))
            guard progress > 0 else { continue }
            context.stroke(road.path.trimmedPath(from: 0, to: progress), with: .color(KGColor.mapRoad),
                           style: StrokeStyle(lineWidth: road.width, lineCap: .round))
        }
    }

    /// Buses, stops and the lake's name.
    private static func drawTraffic(_ context: inout GraphicsContext, elapsed: Double) {
        // A bus along the bottom road (k-lane, 5 s from 1.8 s) and one up the side road (k-lanev, 6 s from 2.6 s).
        if elapsed > 1.8 {
            let x = -40 + 380 * ((elapsed - 1.8) / 5).truncatingRemainder(dividingBy: 1)
            drawBus(&context, at: pt(x, 210), vertical: false)
        }
        if elapsed > 2.6 {
            let y = 300 - 340 * ((elapsed - 2.6) / 6).truncatingRemainder(dividingBy: 1)
            drawBus(&context, at: pt(62, y), vertical: true)
        }

        // Stops pop in.
        for (index, center) in [pt(140, 218), pt(70, 218), pt(250, 218),
                                pt(124, 92)].enumerated() {
            let t = min(max((elapsed - 1.5 - Double(index) * 0.1) / 0.4, 0), 1)
            guard t > 0 else { continue }
            let scale = t < 0.65 ? 0.3 + 0.85 * t / 0.65 : 1.15 - 0.15 * (t - 0.65) / 0.35
            let rect = CGRect(x: center.x - 9 * scale, y: center.y - 9 * scale, width: 18 * scale, height: 18 * scale)
            context.fill(Path(ellipseIn: rect), with: .color(KGColor.white))
            context.stroke(Path(ellipseIn: rect), with: .color(KGColor.coral), lineWidth: 4)
        }

        if elapsed > 1.2 {
            var label = context
            label.opacity = min((elapsed - 1.2) / 0.5, 1)
            label.draw(Text("Bodensee", bundle: .module)
                .font(KGTextStyle.caption.weighted(KGFont.semiBold).font).italic()
                .foregroundStyle(KGColor.mapWaterLabel),
                       at: pt(252, 52), anchor: .leading)
        }
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        Path { path in
            path.move(to: pt(x1, y1))
            path.addLine(to: pt(x2, y2))
        }
    }

    /// The tiny red buses of the illustration, with their windows.
    private static func drawBus(_ context: inout GraphicsContext, at origin: CGPoint, vertical: Bool) {
        let window = KGColor.seeriFace
        if vertical {
            context.fill(Path(roundedRect: CGRect(x: origin.x, y: origin.y, width: 16, height: 28), cornerRadius: 6),
                         with: .color(KGColor.coral))
            context.fill(Path(roundedRect: CGRect(x: origin.x + 3, y: origin.y + 4, width: 10, height: 6),
                              cornerRadius: 1.5), with: .color(window))
        } else {
            context.fill(Path(roundedRect: CGRect(x: origin.x, y: origin.y, width: 30, height: 16), cornerRadius: 6),
                         with: .color(KGColor.coral))
            for (x, width, height) in [(4.0, 7.0, 5.0), (13, 7, 5), (22, 5, 7)] {
                context.fill(Path(roundedRect: CGRect(x: origin.x + x, y: origin.y + 3, width: width, height: height),
                                  cornerRadius: 1.5), with: .color(window))
            }
        }
    }

    private static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
}

/// White 64 pt circle with the "no signal" icon and a green check, bobbing over the map's corner.
private struct OfflineBadge: View {
    @State private var bob = false

    var body: some View {
        KGIconView(.noSignal, size: 30)
            .foregroundStyle(KGColor.ink3)
            .frame(width: 64, height: 64)
            .background(KGColor.surface, in: .circle)
            .kgShadow(.floating, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                KGIconView(.check, size: 12)
                    .foregroundStyle(KGColor.white)
                    .frame(width: 20, height: 20)
                    .background(KGColor.live, in: .circle)
                    .overlay(Circle().strokeBorder(KGColor.surface, lineWidth: 3).padding(-3))
                    .offset(x: 4, y: 4)
                    .popIn(after: 2.1)
            }
            .offset(y: bob ? -7 : 0)
            .kgLoop(.seeriPeek, phase: $bob)
    }
}
