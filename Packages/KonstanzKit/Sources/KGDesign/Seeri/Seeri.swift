import SwiftUI

/// Seeri, the little red bus: the app's mascot and the face of the logo. Drawn from the design's own
/// coordinates on its 160 × 170 grid (Design/Source: SeerotLaunch, SeerotWelcome, AppNoRoute, AppHalloween …).
public struct Seeri: View {
    /// The faces Seeri makes in the design.
    public enum Expression: String, CaseIterable, Sendable {
        /// Dot eyes with highlights and a smile (most screens).
        case happy
        /// Open mouth, talking (02 Willkommen).
        case excited
        /// Closed happy eyes and a big laugh with tongue (06 Alles bereit, widgets).
        case joyful
        /// Raised brows and a small "o" (05 Standort & Mitteilungen).
        case curious
        /// Eyes to the side, brows set: busy finding a connection (20 Suche läuft).
        case focused
        /// Glancing to the right (04 Suchen).
        case looking
        /// Eyes closed, face dimmed, headlights off (23 Keine Verbindung).
        case sleepy
        /// Fanged grin (29 Halloween).
        case spooky
    }

    /// How much of Seeri is drawn, as at different sizes in the design.
    public enum Detail: Sendable {
        /// Everything: mirrors, cheeks, the wave, headlights, grille, wheels (start screen, onboarding, empty states).
        case full
        /// Mirrors, body and face only, for peeking over an edge (07 Karte).
        case peek
        /// Body, roof, face and bumper: small sizes in lists and cards.
        case compact
    }

    public enum Hat: Sendable { case none, witch }

    let expression: Expression
    let detail: Detail
    let hat: Hat
    let shadow: Bool
    /// 0 eyes open … 1 closed, for blinking.
    let blink: Double
    /// Text on the roof sign: "GO!" on the start, welcome and ready screens; empty elsewhere.
    let sign: String?

    public init(_ expression: Expression = .happy, detail: Detail = .full, hat: Hat = .none,
                shadow: Bool = false, blink: Double = 0, sign: String? = nil) {
        self.expression = expression
        self.detail = detail
        self.hat = hat
        self.shadow = shadow
        self.blink = blink
        self.sign = sign
    }

    /// The drawing's grid: 160 × 170, plus 40 above for a hat.
    var viewBox: CGRect {
        hat == .none ? CGRect(x: 0, y: 0, width: 160, height: 170) : CGRect(x: 0, y: -40, width: 160, height: 210)
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width / viewBox.width, size.height / viewBox.height)
            context.translateBy(x: (size.width - viewBox.width * scale) / 2,
                                y: (size.height - viewBox.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
            SeeriDrawing(expression: expression, detail: detail, hat: hat, shadow: shadow, blink: blink)
                .draw(in: &context)
            if let sign, hat == .none {
                // 10 pt ExtraBold yellow, centred at (80, 19) on the grid like the design's <text>.
                KGFont.registerOnce()
                let text = Text(verbatim: sign).font(.custom(KGFont.extraBold, fixedSize: 10))
                    .foregroundStyle(KGColor.lineFill)
                context.draw(text, at: CGPoint(x: 80, y: 15.5), anchor: .center)
            }
        }
        .aspectRatio(viewBox.width / viewBox.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The drawing itself, part by part in the design's order (back to front).
struct SeeriDrawing {
    let expression: Seeri.Expression
    let detail: Seeri.Detail
    let hat: Seeri.Hat
    let shadow: Bool
    let blink: Double

    private var full: Bool { detail == .full }

    func draw(in context: inout GraphicsContext) {
        if shadow, full {
            context.fill(ellipse(80, 164, 48, 6), with: .color(.black.opacity(0.12)))
        }
        if detail != .compact {
            rect(&context, 8, 44, 10, 26, 5, KGColor.seeriDark)    // mirrors
            rect(&context, 142, 44, 10, 26, 5, KGColor.seeriDark)
        }
        rect(&context, 20, 16, 120, 136, 30, KGColor.seeriBody)    // body
        if hat == .witch {
            drawHat(&context)
        } else {
            rect(&context, 50, 6, 60, 18, 6, KGColor.seeriDark)    // roof sign
        }
        rect(&context, 32, 32, 96, 60, 18, expression == .sleepy ? KGColor.seeriFaceDim : KGColor.seeriFace)
        drawEyes(&context)
        if full { drawCheeks(&context) }  // the design shows cheeks only on the full drawing
        drawMouth(&context)
        if full {
            if hat == .none {
                stroke(&context, "M 20 104 q 10 -5 20 0 t 20 0 t 20 0 t 20 0 t 20 0 t 20 0", KGColor.white, 3)
            }
            drawFront(&context)
        }
        if detail != .peek {
            rect(&context, 20, 134, 120, 18, 9, KGColor.seeriDark)    // bumper
        }
        if full {
            let wheel = hat == .witch ? KGColor.halloweenTown : Color.black
            rect(&context, 32, 148, 22, 14, 5, wheel)
            rect(&context, 106, 148, 22, 14, 5, wheel)
        }
    }

    // MARK: Face

    private func drawEyes(_ context: inout GraphicsContext) {
        switch expression {
        case .joyful:
            stroke(&context, "M 52 62 Q 62 50 72 62 M 88 62 Q 98 50 108 62", .black, 5)
        case .sleepy:
            stroke(&context, "M 52 60 Q 62 68 72 60 M 88 60 Q 98 68 108 60", .black, 4.5)
        case .curious:
            stroke(&context, "M 52 44 Q 62 38 70 44 M 90 44 Q 98 38 108 44", .black, 3)
            dotEyes(&context, left: 62, right: 98, y: 62)
        case .focused:
            stroke(&context, "M 52 44 L 72 48 M 108 48 L 124 44", .black, 3.5)
            dotEyes(&context, left: 70, right: 106, y: 58)
        case .looking:
            dotEyes(&context, left: 66, right: 102, y: 58)
        case .happy, .excited, .spooky:
            dotEyes(&context, left: 62, right: 98, y: 60)
        }
    }

    /// Two eyes (9 × 11 ellipses) with highlights; `blink` squashes them shut.
    private func dotEyes(_ context: inout GraphicsContext, left: Double, right: Double, y: Double) {
        let open = max(0.08, 1 - blink)
        for x in [left, right] {
            context.fill(ellipse(x, y, 9, 11 * open), with: .color(.black))
            if open > 0.6 {  // highlights, hidden while blinking
                context.fill(ellipse(x + 3, y - 4, 3, 3), with: .color(.white))
            }
        }
    }

    private func drawCheeks(_ context: inout GraphicsContext) {
        let big = expression == .joyful
        let y: Double = expression == .sleepy || big ? 78 : 80
        let radius: Double = big ? 7 : 6
        let cheek = KGColor.seeriCheek.opacity(big ? 0.85 : 0.8)
        context.fill(ellipse(46, y, radius, radius), with: .color(cheek))
        context.fill(ellipse(114, y, radius, radius), with: .color(cheek))
    }

    private func drawMouth(_ context: inout GraphicsContext) {
        switch expression {
        case .happy:
            stroke(&context, "M 70 78 Q 80 88 90 78", .black, 4)
        case .looking:
            stroke(&context, "M 72 78 Q 82 86 92 78", .black, 4)
        case .focused:
            stroke(&context, "M 76 78 Q 88 86 98 78", .black, 4)
        case .excited:
            fillAndStroke(&context, "M 68 77 Q 80 92 92 77", .black, 3)
        case .joyful:
            fillAndStroke(&context, "M 66 74 Q 80 94 94 74 Z", .black, 3)
            fill(&context, "M 72 82 Q 80 88 88 82", KGColor.lineFill)    // tongue
        case .curious:
            context.fill(ellipse(80, 82, 6, 5), with: .color(.black))
        case .sleepy:
            context.fill(ellipse(80, 80, 5, 4), with: .color(.black))
        case .spooky:
            fill(&context, "M 66 76 Q 80 92 94 76 Z", .black)
            fill(&context, "M 72 77 L 75 82 L 78 77 M 82 77 L 85 82 L 88 77", .white)    // fangs
        }
    }

    // MARK: Front and hat

    private func drawFront(_ context: inout GraphicsContext) {
        let light: Color = switch (expression, hat) {
        case (.sleepy, _): KGColor.seeriHeadlightOff
        case (_, .witch): KGColor.halloweenMoon
        default: KGColor.seeriHeadlight
        }
        for x in [42.0, 118.0] {
            let lamp = ellipse(x, 120, 9, 9)
            context.fill(lamp, with: .color(light))
            context.stroke(lamp, with: .color(KGColor.seeriTrim), lineWidth: 3)
        }
        rect(&context, 62, 114, 36, 12, 6, KGColor.seeriTrim)    // grille
    }

    private func drawHat(_ context: inout GraphicsContext) {
        context.fill(ellipse(80, 14, 58, 9), with: .color(KGColor.witchHat))
        fill(&context, "M 48 12 L 84 -38 L 100 -30 L 112 12 Z", KGColor.witchHat)
        context.fill(Path(CGRect(x: 50, y: 2, width: 60, height: 9)), with: .color(KGColor.halloweenMoon))
    }

    // MARK: Helpers

    private func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    }

    // swiftlint:disable:next function_parameter_count
    private func rect(_ context: inout GraphicsContext, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                      _ radius: Double, _ color: Color) {
        let shape = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
        context.fill(shape, with: .color(color))
    }

    private func path(_ data: String) -> Path { (try? SVGPath.path(data)) ?? Path() }

    private func stroke(_ context: inout GraphicsContext, _ data: String, _ color: Color, _ width: Double) {
        context.stroke(path(data), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func fill(_ context: inout GraphicsContext, _ data: String, _ color: Color) {
        context.fill(path(data), with: .color(color))
    }

    private func fillAndStroke(_ context: inout GraphicsContext, _ data: String, _ color: Color, _ width: Double) {
        let shape = path(data)
        context.fill(shape, with: .color(color))
        context.stroke(shape, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
    }
}
