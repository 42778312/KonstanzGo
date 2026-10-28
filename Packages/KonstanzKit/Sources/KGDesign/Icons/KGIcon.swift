import SwiftUI

/// How one icon is drawn on the 24 × 24 grid: filled or stroked by default, its stroke width, its parts.
struct KGIconDrawing {
    /// Parts that say neither fill nor stroke are filled when true, stroked when false.
    var filled: Bool
    var lineWidth: Double
    var elements: [KGIconElement]
}

struct KGIconElement {
    enum Shape {
        case path(String)
        case circle(cx: Double, cy: Double, radius: Double)
        case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
        case rect(x: Double, y: Double, width: Double, height: Double, radius: Double)
    }

    enum Paint { case inherit, fill, stroke }

    var shape: Shape
    var paint: Paint
    var lineWidth: Double?

    init(shape: Shape, paint: Paint, lineWidth: Double? = nil) {
        self.shape = shape
        self.paint = paint
        self.lineWidth = lineWidth
    }

    var path: Path {
        switch shape {
        case let .path(data):
            (try? SVGPath.path(data)) ?? Path()
        case let .circle(cx, cy, radius):
            Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: 2 * radius, height: 2 * radius))
        case let .ellipse(cx, cy, rx, ry):
            Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        case let .rect(x, y, width, height, radius):
            Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
        }
    }
}

extension KGIcon {
    /// Whether the drawing reads; every icon must (checked by a test).
    var isValid: Bool {
        drawing.elements.allSatisfy { element in
            if case let .path(data) = element.shape { return (try? SVGPath.path(data)) != nil }
            return true
        }
    }
}

/// One of the design's icons at a size (default 24 pt), in the current foreground style, like an SF Symbol.
/// Strokes scale with the size and keep the design's round caps and joins. Hidden from VoiceOver by default:
/// give the control around it a label instead.
public struct KGIconView: View {
    let icon: KGIcon
    let size: CGFloat
    let insideFill: Color?

    /// `fill` paints the inside of stroked shapes first, as the design's selected tab icons do
    /// (`fill="#FFCDD0" stroke="#F05A62"`).
    public init(_ icon: KGIcon, size: CGFloat = 24, fill: Color? = nil) {
        self.icon = icon
        self.size = size
        insideFill = fill
    }

    public var body: some View {
        Canvas { context, canvas in
            let drawing = icon.drawing
            let scale = canvas.width / 24
            context.scaleBy(x: scale, y: scale)
            for element in drawing.elements {
                let fill = element.paint == .fill || (element.paint == .inherit && drawing.filled)
                if fill {
                    context.fill(element.path, with: .foreground)
                } else {
                    if let insideFill { context.fill(element.path, with: .color(insideFill)) }
                    context.stroke(element.path, with: .foreground,
                                   style: StrokeStyle(lineWidth: element.lineWidth ?? drawing.lineWidth,
                                                      lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// All icons in a grid, for the design-system screen.
public struct IconGallery: View {
    public init() {}

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: KGSpace.small)], spacing: KGSpace.medium) {
            ForEach(KGIcon.allCases, id: \.self) { icon in
                VStack(spacing: KGSpace.xs) {
                    KGIconView(icon).foregroundStyle(KGColor.ink)
                    Text(verbatim: icon.rawValue).kgFont(.caption).foregroundStyle(KGColor.ink3)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(KGSpace.screen)
        .background(KGColor.surface)
    }
}

#Preview("Icons") {
    ScrollView { IconGallery() }
}
