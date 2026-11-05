import SwiftUI

/// The map's right-hand buttons (B27): layers and my location, 48 × 48, radius 14, 12 apart.
public struct KGMapControls: View {
    let isFollowing: Bool
    let onLayers: () -> Void
    let onLocate: () -> Void

    public init(isFollowing: Bool = false, onLayers: @escaping () -> Void, onLocate: @escaping () -> Void) {
        self.isFollowing = isFollowing
        self.onLayers = onLayers
        self.onLocate = onLocate
    }

    public var body: some View {
        VStack(spacing: KGSpace.medium) {
            KGRoundIconButton(.layers, label: Text("Kartenebenen", bundle: .kgDesign), surface: .mapSquare,
                              action: onLayers)
            KGRoundIconButton(.locate, label: Text("Mein Standort", bundle: .kgDesign), surface: .mapSquare,
                              tint: isFollowing ? KGColor.location : KGColor.ink, action: onLocate)
                .accessibilityAddTraits(isFollowing ? [.isSelected] : [])
        }
    }
}

/// A bus on the map (B28): deep-coral capsule with a 2.5 pt white border, a white circle with the bus, the
/// line number, a pulse ring and a 1 pt bob. On the real map buses are drawn by MapLibre from images of this
/// view; this SwiftUI version is for previews, the design-system screen and making those images.
public struct KGBusMarker: View {
    let line: String
    let heading: Angle?
    let animated: Bool
    @State private var phase = false

    public init(line: String, heading: Angle? = nil, animated: Bool = true) {
        self.line = line
        self.heading = heading
        self.animated = animated
    }

    public var body: some View {
        ZStack {
            if animated {
                Circle().fill(KGColor.coral)
                    .frame(width: 30, height: 30)
                    .scaleEffect(phase ? 2.2 : 1)
                    .opacity(phase ? 0 : 0.35)
            }
            if let heading {
                Triangle().fill(KGColor.coralDeep)
                    .frame(width: 12, height: 9)
                    .offset(y: -22)
                    .rotationEffect(heading)
            }
            HStack(spacing: KGSpace.xxs) {
                KGIconView(.bus, size: 13)
                    .foregroundStyle(KGColor.coralDeep)
                    .frame(width: 20, height: 20)
                    .background(KGColor.white, in: .circle)
                Text(verbatim: line).kgFont(.footnote.weighted(KGFont.bold)).foregroundStyle(KGColor.white)
                    .fixedSize()
            }
            .padding(.leading, 3)
            .padding(.trailing, 9)
            .frame(height: 28)
            .background(KGColor.coralDeep, in: .capsule)
            .overlay(Capsule().strokeBorder(KGColor.white, lineWidth: 2.5))
            .kgShadow(.bus, in: Capsule())
            .offset(y: animated && phase ? -1 : 0)
        }
        .kgLoop(.livePulse, phase: $phase)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bus \(line), geschätzte Position", bundle: .kgDesign))
    }

    struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

/// A bus or train on the main map, placed by the timetable: a small capsule with the vehicle and its number
/// (red with white; the Swiss buses to Kreuzlingen yellow with black) and a nose pointing where it heads.
public struct KGVehicleMarker: View {
    let line: String
    let isTrain: Bool
    let isKreuzlingen: Bool
    let heading: Angle?
    let isLive: Bool

    public init(line: String, isTrain: Bool = false, isKreuzlingen: Bool = false, heading: Angle? = nil,
                isLive: Bool = false) {
        self.isLive = isLive
        self.line = line
        self.isTrain = isTrain
        self.isKreuzlingen = isKreuzlingen
        self.heading = heading
    }

    private var fill: Color { isKreuzlingen ? KGColor.kreuzlingen : KGColor.coralDeep }
    private var text: Color { isKreuzlingen ? .black : .white }

    public var body: some View {
        ZStack {
            if let heading {
                Nose().fill(fill)
                    .frame(width: 9, height: 6)
                    .offset(y: -15)
                    .rotationEffect(heading)
            }
            HStack(spacing: 2) {
                KGIconView(isTrain ? .train : .bus, size: 11)
                if !line.isEmpty {
                    Text(verbatim: line).font(.system(size: 12, weight: .heavy, design: .rounded)).fixedSize()
                }
            }
            .foregroundStyle(text)
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 22)
            .background(fill, in: .capsule)
            .overlay(Capsule().strokeBorder(KGColor.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .overlay(alignment: .topTrailing) {
                // The operator reports this bus: its position follows its real delay.
                if isLive {
                    Circle().fill(KGColor.live)
                        .overlay(Circle().strokeBorder(KGColor.white, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isTrain ? Text("Zug \(line), geschätzte Position", bundle: .kgDesign)
                                    : Text("Bus \(line), geschätzte Position", bundle: .kgDesign))
    }

    struct Nose: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

/// The nose of `KGVehicleMarker` alone, for drawing on a map layer that turns it.
public struct KGVehicleNose: View {
    let isYellow: Bool

    public init(isYellow: Bool) { self.isYellow = isYellow }

    public var body: some View {
        KGVehicleMarker.Nose().fill(isYellow ? KGColor.kreuzlingen : KGColor.coralDeep).frame(width: 9, height: 6)
    }
}

/// The nose of `KGBusMarker` alone.
public struct KGBusMarkerNose: View {
    public init() {}

    public var body: some View {
        KGBusMarker.Triangle().fill(KGColor.coralDeep).frame(width: 12, height: 9)
    }
}


/// The user's position (B29): blue 24 pt dot with a 4 pt white border and soft blue shadow, a ring that grows
/// to 3.4× (2.4 s), and a cone when the heading is known.
public struct KGUserDot: View {
    let heading: Angle?
    @State private var pulsing = false

    public init(heading: Angle? = nil) {
        self.heading = heading
    }

    public var body: some View {
        ZStack {
            Circle().fill(KGColor.location)
                .frame(width: 24, height: 24)
                .scaleEffect(pulsing ? 3.4 : 1)
                .opacity(pulsing ? 0 : 0.35)
            if let heading {
                Cone().fill(LinearGradient(colors: [KGColor.location.opacity(0.45), KGColor.location.opacity(0)],
                                           startPoint: .bottom, endPoint: .top))
                    .frame(width: 44, height: 40)
                    .offset(y: -20)
                    .rotationEffect(heading)
            }
            Circle().fill(KGColor.location)
                .overlay(Circle().strokeBorder(KGColor.white, lineWidth: 4))
                .frame(width: 24, height: 24)
                .shadow(color: KGColor.location.opacity(0.4), radius: 5, y: 3)
        }
        .frame(width: 44, height: 44)
        .kgLoop(.locationPulse, phase: $pulsing)
        .accessibilityElement()
        .accessibilityLabel(Text("Mein Standort", bundle: .kgDesign))
    }

    private struct Cone: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                                  control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.25))
                path.closeSubpath()
            }
        }
    }
}

/// A stop on the map (B30): white circle with a 3.5 pt coral ring; selected it becomes the 48 pt coral
/// marker of screen 09 with a white border, the bus icon, a pulse, and the stop's name under it.
public struct KGStopMarker: View {
    let name: String
    let isSelected: Bool
    let showsName: Bool
    @State private var pulsing = false

    /// `showsName: false` when the map draws stop names itself.
    public init(_ name: String, isSelected: Bool = false, showsName: Bool = true) {
        self.name = name
        self.isSelected = isSelected
        self.showsName = showsName
    }

    public var body: some View {
        VStack(spacing: KGSpace.xxs) {
            ZStack {
                if isSelected {
                    Circle().fill(KGColor.coral).frame(width: 40, height: 40)
                        .scaleEffect(pulsing ? 2 : 1).opacity(pulsing ? 0 : 0.4)
                        .kgLoop(.locationPulse, phase: $pulsing)
                    KGIconView(.bus, size: 22)
                        .foregroundStyle(KGColor.white)
                        .frame(width: 48, height: 48)
                        .background(KGColor.coral, in: .circle)
                        .overlay(Circle().strokeBorder(KGColor.white, lineWidth: 4))
                        .shadow(color: KGColor.coral.opacity(0.4), radius: 8, y: 6)
                        .transition(.scale(scale: KGMotion.popStart).combined(with: .opacity))
                } else {
                    Circle().fill(KGColor.white)
                        .overlay(Circle().strokeBorder(KGColor.coral, lineWidth: 3.5))
                        .frame(width: 13, height: 13)
                        .frame(width: KGSize.touch, height: KGSize.touch)
                }
            }
            if isSelected, showsName {
                Text(verbatim: name)
                    .kgFont(.caption.weighted(KGFont.extraBold))
                    .foregroundStyle(KGColor.ink)
                    .padding(.horizontal, KGSpace.small)
                    .padding(.vertical, 2)
                    .background(KGColor.surface.opacity(0.9), in: .capsule)
            }
        }
        .animation(KGMotion.pop, value: isSelected)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Haltestelle \(name)", bundle: .kgDesign))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview("Map") {
    ZStack {
        KGColor.mapLand
        VStack(spacing: 40) {
            HStack(spacing: 40) {
                KGBusMarker(line: "9A", heading: .degrees(60))
                KGUserDot(heading: .degrees(20))
            }
            HStack(spacing: 40) {
                KGStopMarker("Sternenplatz")
                KGStopMarker("Sternenplatz", isSelected: true)
            }
            KGMapControls(onLayers: {}, onLocate: {})
        }
    }
}
