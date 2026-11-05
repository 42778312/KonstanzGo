import KGCore
import KGDesign
import SwiftUI

/// The intro: a short motion graphic with Seeri, six scenes of three seconds that play by themselves, joined by
/// a circular wipe. All drawn live from one clock, so it's sharp on every phone. "Überspringen" skips it.
struct IntroFilm: View {
    let onDone: () -> Void
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let sceneLength = 3.0
    static let scenes = 6
    private static var length: Double { sceneLength * Double(scenes) }

    var body: some View {
        Group {
            if reduceMotion {
                // No movement: each scene in its finished state, one after the other.
                TimelineView(.periodic(from: start, by: 3.5)) { context in
                    let index = min(Int(context.date.timeIntervalSince(start) / 3.5), Self.scenes - 1)
                    stage(time: Double(index + 1) * Self.sceneLength - 0.3)
                }
            } else {
                TimelineView(.animation) { context in
                    stage(time: context.date.timeIntervalSince(start))
                }
            }
        }
        .onAppear { start = .now }
    }

    private func stage(time: Double) -> some View {
        let index = min(Int(time / Self.sceneLength), Self.scenes - 1)
        let local = time - Double(index) * Self.sceneLength
        return ZStack {
            scene(index, at: local)
            if time < Self.length {
                CircleWipe(local: local, isFirst: index == 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if time < Self.length {
                Button(action: onDone) {
                    Text("Überspringen", bundle: .module).kgFont(.footnote).foregroundStyle(KGColor.white)
                        .padding(.horizontal, KGSpace.compact)
                        .frame(minHeight: 34)
                        .background(.black.opacity(0.28), in: Capsule())
                        .frame(minHeight: KGSize.touch)
                        .contentShape(.rect)
                }
                .buttonStyle(KGPressStyle())
                .padding(.trailing, KGSpace.screen)
                .accessibilityIdentifier("introSkip")
            }
        }
        .overlay(alignment: .bottom) {
            if time >= Self.length - 0.4 {
                KGButton(Text("Los geht's", bundle: .module), action: onDone)
                    .padding(.horizontal, KGSpace.large)
                    .padding(.bottom, KGSpace.small)
                    .opacity(Motion.rise(time, Self.length - 0.4, Self.length))
                    .offset(y: (1 - Motion.rise(time, Self.length - 0.4, Self.length)) * 24)
                    .accessibilityIdentifier("introNext")
            }
        }
    }

    @ViewBuilder private func scene(_ index: Int, at time: Double) -> some View {
        switch index {
        case 0: HelloScene(time: time)
        case 1: BusesScene(time: time)
        case 2: OfflineScene(time: time)
        case 3: SearchScene(time: time)
        case 4: SirenScene(time: time)
        default: RescueScene(time: time)
        }
    }
}

// MARK: - Timing

enum Motion {
    /// 0 before `from`, 1 after `to`, easing out in between.
    static func rise(_ time: Double, _ from: Double, _ to: Double) -> Double {
        let part = min(max((time - from) / (to - from), 0), 1)
        return 1 - pow(1 - part, 3)
    }

    /// Like `rise`, overshooting a little before it settles.
    static func pop(_ time: Double, _ from: Double, _ duration: Double = 0.45) -> Double {
        let part = min(max((time - from) / duration, 0), 1)
        guard part > 0 else { return 0 }
        let back = 1.9
        let moved = part - 1
        return 1 + (back + 1) * pow(moved, 3) + back * pow(moved, 2)
    }
}

// MARK: - Parts every scene uses

/// A coral circle closes over the end of a scene and opens onto the next.
private struct CircleWipe: View {
    let local: Double
    let isFirst: Bool

    var body: some View {
        Canvas { context, size in
            let reach = hypot(size.width, size.height) / 2 + 20
            let middle = CGPoint(x: size.width / 2, y: size.height * 0.4)
            func circle(_ radius: Double) -> Path {
                Path(ellipseIn: CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2))
            }
            let closing = Motion.rise(local, IntroFilm.sceneLength - 0.3, IntroFilm.sceneLength)
            if closing > 0 {
                context.fill(circle(reach * closing), with: .color(KGColor.coral))
            } else if !isFirst, local < 0.32 {
                var hole = Path(CGRect(origin: .zero, size: size))
                hole.addPath(circle(reach * Motion.rise(local, 0, 0.32)))
                context.fill(hole, with: .color(KGColor.coral), style: FillStyle(eoFill: true))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A title whose words rise into place one after the other, with a line under it.
private struct KineticTitle: View {
    let title: String
    let detail: String
    let time: Double
    var delay = 0.28

    private var lines: [[String]] {
        var lines: [[String]] = [[]]
        for word in title.split(separator: " ").map(String.init) {
            if (lines[lines.count - 1] + [word]).joined(separator: " ").count > 15, !lines[lines.count - 1].isEmpty {
                lines.append([])
            }
            lines[lines.count - 1].append(word)
        }
        return lines
    }

    var body: some View {
        var order = 0.0
        return VStack(spacing: KGSpace.small) {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 9) {
                        ForEach(Array(line.enumerated()), id: \.offset) { _, word in
                            let start = delay + order * 0.09
                            let _ = order += 1
                            let part = Motion.rise(time, start, start + 0.45)
                            Text(verbatim: word)
                                .kgFont(.display.sized(38))
                                .foregroundStyle(KGColor.white)
                                .offset(y: (1 - part) * 34)
                                .opacity(part)
                        }
                    }
                }
            }
            Text(verbatim: detail)
                .kgFont(.bodyMedium.weighted(KGFont.regular))
                .foregroundStyle(KGColor.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .opacity(Motion.rise(time, delay + 0.5, delay + 0.95))
                .offset(y: (1 - Motion.rise(time, delay + 0.5, delay + 0.95)) * 12)
        }
        .padding(.horizontal, KGSpace.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title). \(detail)"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// What the scenes stand on: the title in the lower part, the picture above it.
private struct SceneLayout<Picture: View>: View {
    let title: String
    let detail: String
    let time: Double
    @ViewBuilder let picture: Picture

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                picture
                LinearGradient(colors: [.clear, KGColor.filmNight.opacity(0.94)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                KineticTitle(title: title, detail: detail, time: time)
                    .frame(width: proxy.size.width)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.74)
            }
        }
        .background(KGColor.filmNight)
    }
}

/// The night map, drawn: water, a park and streets. No inputs, so it's only ever drawn once.
private struct FilmMap: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width, height = size.height
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * width, y: y * height) }
            var water = Path()
            water.move(to: point(0, 0.19))
            water.addCurve(to: point(1, 0.27), control1: point(0.35, 0.1), control2: point(0.66, 0.36))
            water.addLine(to: point(1, 0.04))
            water.addCurve(to: point(0, 0.08), control1: point(0.6, 0.1), control2: point(0.3, 0.0))
            water.closeSubpath()
            context.fill(water, with: .color(KGColor.filmWater))
            for park in [CGRect(x: 0.08, y: 0.31, width: 0.26, height: 0.12), CGRect(x: 0.66, y: 0.5, width: 0.3, height: 0.1)] {
                context.fill(Path(roundedRect: CGRect(x: park.minX * width, y: park.minY * height, width: park.width * width,
                                                      height: park.height * height), cornerRadius: 14),
                             with: .color(KGColor.filmPark))
            }
            var streets = Path()
            for index in 0...13 {
                let across = Double(index) / 13
                streets.move(to: point(across - 0.25, 1))
                streets.addLine(to: point(across + 0.25, 0.22))
                streets.move(to: point(0, 0.26 + across * 0.72))
                streets.addLine(to: point(1, 0.2 + across * 0.8))
            }
            context.stroke(streets, with: .color(KGColor.filmRoad.opacity(0.45)), lineWidth: 1)
            for route in FilmRoute.background {
                context.stroke(route.path(in: size), with: .color(KGColor.filmRoad),
                               style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A smooth line through points given as parts of the screen, walkable from 0 to 1.
struct FilmRoute {
    private let samples: [CGPoint]

    init(_ points: [CGPoint]) {
        var out: [CGPoint] = []
        for index in 0..<(points.count - 1) {
            let before = points[max(index - 1, 0)], from = points[index]
            let to = points[index + 1], after = points[min(index + 2, points.count - 1)]
            for step in 0..<24 {
                let t = Double(step) / 24, t2 = t * t, t3 = t2 * t
                func spline(_ one: Double, _ two: Double, _ three: Double, _ four: Double) -> Double {
                    0.5 * (2 * two + (three - one) * t + (2 * one - 5 * two + 4 * three - four) * t2
                        + (3 * two - one - 3 * three + four) * t3)
                }
                out.append(CGPoint(x: spline(before.x, from.x, to.x, after.x), y: spline(before.y, from.y, to.y, after.y)))
            }
        }
        out.append(points[points.count - 1])
        samples = out
    }

    func path(in size: CGSize) -> Path {
        var path = Path()
        path.addLines(samples.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
        return path
    }

    func point(at part: Double, in size: CGSize) -> CGPoint {
        let spot = samples[min(Int(max(part, 0) * Double(samples.count - 1)), samples.count - 1)]
        return CGPoint(x: spot.x * size.width, y: spot.y * size.height)
    }

    /// Compass degrees at this part of the way.
    func heading(at part: Double, in size: CGSize) -> Double {
        let here = point(at: part, in: size), ahead = point(at: min(part + 0.02, 1), in: size)
        return atan2(ahead.x - here.x, here.y - ahead.y) * 180 / .pi
    }

    static let first = FilmRoute([CGPoint(x: -0.1, y: 0.56), CGPoint(x: 0.24, y: 0.5), CGPoint(x: 0.46, y: 0.3),
                                  CGPoint(x: 0.78, y: 0.34), CGPoint(x: 1.1, y: 0.24)])
    static let second = FilmRoute([CGPoint(x: 0.3, y: -0.04), CGPoint(x: 0.42, y: 0.2), CGPoint(x: 0.56, y: 0.42),
                                   CGPoint(x: 0.6, y: 0.7)])
    static let third = FilmRoute([CGPoint(x: 1.1, y: 0.52), CGPoint(x: 0.74, y: 0.46), CGPoint(x: 0.42, y: 0.46),
                                  CGPoint(x: 0.12, y: 0.32), CGPoint(x: -0.1, y: 0.3)])
    static let background = [first, second, third]
}

private struct FilmRouteLine: View {
    let route: FilmRoute
    let drawn: Double
    var color = KGColor.coral

    var body: some View {
        GeometryReader { proxy in
            route.path(in: proxy.size).trimmedPath(from: 0, to: drawn)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.6), radius: 7)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Scene 1: Seeri lands

private struct HelloScene: View {
    let time: Double

    var body: some View {
        let landed = Motion.rise(time, 0.1, 0.55)
        let squash = time > 0.5 ? exp(-(time - 0.5) * 7) * cos((time - 0.5) * 18) * 0.14 : 0
        SceneLayout(title: String(localized: "Hallo, ich bin Seeri", bundle: .module),
                    detail: String(localized: "Dein Bus durch Konstanz", bundle: .module), time: time - 0.4) {
            GeometryReader { proxy in
                let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.38)
                ForEach(0..<3, id: \.self) { ring in
                    let part = Motion.rise(time, 0.5 + Double(ring) * 0.16, 1.5 + Double(ring) * 0.16)
                    Circle().strokeBorder(KGColor.coral.opacity((1 - part) * 0.8), lineWidth: 3)
                        .frame(width: 130 + part * 340, height: 130 + part * 340)
                        .position(middle)
                }
                SeeriAlive(.joyful, shadow: true)
                    .frame(width: 180, height: 192)
                    .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
                    .position(x: middle.x, y: middle.y - (1 - landed) * proxy.size.height * 0.62)
            }
        }
    }
}

// MARK: - Scene 2: every bus, live

private struct BusesScene: View {
    let time: Double

    var body: some View {
        SceneLayout(title: String(localized: "Jeder Bus. Live.", bundle: .module),
                    detail: String(localized: "Auf der Karte, wo er gerade wirklich ist", bundle: .module), time: time) {
            ZStack {
                FilmMap().scaleEffect(1 + time * 0.012)
                FilmRouteLine(route: .first, drawn: Motion.rise(time, 0.1, 1.2))
                FilmRouteLine(route: .second, drawn: Motion.rise(time, 0.25, 1.35), color: KGColor.kreuzlingen)
                FilmRouteLine(route: .third, drawn: Motion.rise(time, 0.4, 1.5))
                GeometryReader { proxy in
                    bus(.first, "5", part: 0.14 + time * 0.13, popAt: 0.5, liveAt: 1.3, in: proxy.size)
                    bus(.second, "700", part: 0.1 + time * 0.14, popAt: 0.65, liveAt: 1.5, yellow: true, in: proxy.size)
                    bus(.third, "9", part: 0.12 + time * 0.12, popAt: 0.8, liveAt: 1.7, in: proxy.size)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func bus(_ route: FilmRoute, _ line: String, part: Double, popAt: Double, liveAt: Double, yellow: Bool = false,
                     in size: CGSize) -> some View {
        KGVehicleMarker(line: line, isKreuzlingen: yellow, heading: .degrees(route.heading(at: part, in: size)),
                        isLive: time > liveAt)
            .scaleEffect(1.5 * Motion.pop(time, popAt))
            .position(route.point(at: part, in: size))
    }
}

// MARK: - Scene 3: no signal, no problem

private struct OfflineScene: View {
    let time: Double
    private static let stops = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.42, y: 0.3), CGPoint(x: 0.78, y: 0.34),
                                CGPoint(x: 0.56, y: 0.42), CGPoint(x: 0.74, y: 0.46), CGPoint(x: 0.12, y: 0.32)]

    var body: some View {
        let solved = Motion.pop(time, 1.25)
        SceneLayout(title: String(localized: "Auch ohne Netz", bundle: .module),
                    detail: String(localized: "Fahrplan und Karte sind immer dabei", bundle: .module), time: time) {
            ZStack {
                FilmMap().opacity(0.35 + 0.65 * Motion.rise(time, 1.2, 1.8))
                GeometryReader { proxy in
                    ForEach(Array(Self.stops.enumerated()), id: \.offset) { index, stop in
                        ClosedFreeStop()
                            .scaleEffect(Motion.pop(time, 1.35 + Double(index) * 0.07))
                            .position(x: stop.x * proxy.size.width, y: stop.y * proxy.size.height)
                    }
                    ZStack {
                        Circle().fill(.ultraThinMaterial).frame(width: 136, height: 136)
                        Image(systemName: "wifi.slash")
                            .resizable().scaledToFit().frame(width: 62)
                            .foregroundStyle(KGColor.white)
                            .scaleEffect(max(0, 1 - solved))
                        Image(systemName: "checkmark")
                            .resizable().scaledToFit().frame(width: 58)
                            .fontWeight(.bold)
                            .foregroundStyle(KGColor.live)
                            .scaleEffect(solved)
                    }
                    .scaleEffect(Motion.pop(time, 0.2))
                    .offset(x: time < 1.2 && time > 0.7 ? sin(time * 34) * 5 : 0)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.38)
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct ClosedFreeStop: View {
    var body: some View {
        KGIconView(.bus, size: 15).foregroundStyle(KGColor.white)
            .frame(width: 30, height: 30)
            .background(KGColor.coral, in: .kgRounded(8))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(KGColor.white, lineWidth: 2))
    }
}

// MARK: - Scene 4: just say where

private struct SearchScene: View {
    let time: Double
    private static let target = "Sternenplatz"

    var body: some View {
        let typed = Int(min(max((time - 0.65) / 0.75, 0), 1) * Double(Self.target.count))
        SceneLayout(title: String(localized: "Sag einfach, wohin", bundle: .module),
                    detail: String(localized: "Tippen oder sprechen, auch ohne Internet", bundle: .module), time: time) {
            ZStack {
                FilmMap().opacity(0.55)
                GeometryReader { proxy in
                    VStack(spacing: KGSpace.small) {
                        HStack(spacing: KGSpace.small) {
                            KGIconView(.search, size: 22).foregroundStyle(KGColor.white)
                            Text(verbatim: String(Self.target.prefix(typed)) + (Int(time * 3) % 2 == 0 ? "|" : " "))
                                .kgFont(.headline).foregroundStyle(KGColor.white).lineLimit(1)
                            Spacer(minLength: 0)
                            HStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { bar in
                                    Capsule().fill(KGColor.coral)
                                        .frame(width: 4, height: 8 + abs(sin(time * 9 + Double(bar) * 1.1)) * 24)
                                }
                            }
                            .frame(height: 34)
                        }
                        .padding(.horizontal, KGSpace.large)
                        .frame(height: 66)
                        .background(.ultraThinMaterial, in: Capsule())
                        .scaleEffect(x: Motion.pop(time, 0.15), y: 1)
                        .opacity(Motion.rise(time, 0.1, 0.3))
                        HStack(spacing: KGSpace.compact) {
                            ClosedFreeStop()
                            Text(verbatim: Self.target).kgFont(.bodyStrong).foregroundStyle(KGColor.white)
                            Spacer()
                            KGLineBadge("5", size: .small)
                            KGLineBadge("9", size: .small)
                        }
                        .padding(KGSpace.medium)
                        .background(.ultraThinMaterial, in: .kgRounded(KGRadius.card))
                        .opacity(Motion.rise(time, 1.4, 1.65))
                        .offset(y: (1 - Motion.rise(time, 1.4, 1.75)) * 20)
                    }
                    .padding(.horizontal, KGSpace.large)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.33)
                }
            }
        }
    }
}

// MARK: - Scene 5: the siren

private struct SirenScene: View {
    let time: Double
    private static let closed = [CGPoint(x: 0.17, y: 0.2), CGPoint(x: 0.83, y: 0.26), CGPoint(x: 0.14, y: 0.5),
                                 CGPoint(x: 0.86, y: 0.52)]

    var body: some View {
        let red = time.truncatingRemainder(dividingBy: 0.6) < 0.3
        SceneLayout(title: String(localized: "Ich warne dich", bundle: .module),
                    detail: String(localized: "Bei Baustellen und gesperrten Haltestellen", bundle: .module), time: time) {
            ZStack {
                FilmMap().opacity(0.4)
                GeometryReader { proxy in
                    RadialGradient(colors: [(red ? Color.red : Color.blue).opacity(0.55), .clear],
                                   center: UnitPoint(x: red ? 0.2 : 0.8, y: 0.34), startRadius: 10, endRadius: 330)
                    ForEach(Array(Self.closed.enumerated()), id: \.offset) { index, spot in
                        ClosedStopMark(size: 40)
                            .scaleEffect(Motion.pop(time, 0.6 + Double(index) * 0.17))
                            .position(x: spot.x * proxy.size.width, y: spot.y * proxy.size.height)
                    }
                    SeeriAlive(.excited, shadow: true, sirenFlashing: true)
                        .frame(width: 160, height: 171)
                        .scaleEffect(Motion.pop(time, 0.15))
                        .offset(x: sin(time * 22) * 2.5)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.37)
                }
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Scene 6: a new way

private struct RescueScene: View {
    let time: Double
    private static let planned = FilmRoute([CGPoint(x: -0.1, y: 0.5), CGPoint(x: 0.28, y: 0.46), CGPoint(x: 0.56, y: 0.3),
                                            CGPoint(x: 0.84, y: 0.2)])
    private static let better = FilmRoute([CGPoint(x: 0.3, y: 0.45), CGPoint(x: 0.42, y: 0.53), CGPoint(x: 0.68, y: 0.48),
                                           CGPoint(x: 0.84, y: 0.2)])
    private static let stopAt = 0.47

    var body: some View {
        let tap = Motion.pop(time, 0.85, 0.35)
        let drawn = Motion.rise(time, 1.35, 2.3)
        SceneLayout(title: String(localized: "Bus verpasst? Ein Tipp.", bundle: .module),
                    detail: String(localized: "Ich finde sofort einen anderen Weg", bundle: .module), time: time - 0.3) {
            ZStack {
                FilmMap().opacity(0.8)
                FilmRouteLine(route: Self.planned, drawn: Motion.rise(time, 0, 0.6), color: KGColor.white.opacity(0.35))
                FilmRouteLine(route: Self.better, drawn: drawn)
                GeometryReader { proxy in
                    let size = proxy.size
                    ClosedStopMark(size: 38)
                        .scaleEffect(Motion.pop(time, 0.55))
                        .position(Self.planned.point(at: Self.stopAt + 0.08, in: size))
                    KGIconView(.pinFilled, size: 34).foregroundStyle(KGColor.coral)
                        .position(Self.planned.point(at: 1, in: size))
                    HStack(spacing: KGSpace.xs) {
                        KGIconView(.swap, size: 16)
                        Text("Andere Route", bundle: .module).kgFont(.callout)
                    }
                    .foregroundStyle(KGColor.white)
                    .padding(.horizontal, KGSpace.large)
                    .frame(height: 46)
                    .background(KGColor.coral, in: Capsule())
                    .scaleEffect(tap * (time > 1.2 && time < 1.4 ? 0.9 : 1))
                    .opacity(1 - Motion.rise(time, 1.6, 1.9))
                    .overlay {
                        Circle().strokeBorder(KGColor.white.opacity(1 - Motion.rise(time, 1.2, 1.7)), lineWidth: 3)
                            .frame(width: 20 + Motion.rise(time, 1.2, 1.7) * 90, height: 20 + Motion.rise(time, 1.2, 1.7) * 90)
                            .opacity(time > 1.2 ? 1 : 0)
                    }
                    .position(x: size.width / 2, y: size.height * 0.16)
                    SeeriAlive(.happy, detail: .compact)
                        .frame(width: 56, height: 60)
                        .scaleEffect(Motion.pop(time, 0.2))
                        .position(time < 1.35 ? Self.planned.point(at: min(Motion.rise(time, 0.1, 0.9) * 0.33, 0.33), in: size)
                                              : Self.better.point(at: drawn, in: size))
                }
                .ignoresSafeArea()
            }
        }
    }
}
