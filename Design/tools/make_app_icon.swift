// Draws the app icons from the brand board (Design/Source/SeerotBrand.dc.html, "APP-ICONS") at 1024 px:
// light = coral, dark = black, tinted = white artwork on transparent (iOS 18+ tints it).
//
//     swift Design/tools/make_app_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// iOS rounds the corners itself, so the images are full squares. The artwork fills 70/80 of the tile.
import AppKit
import CoreGraphics

struct Style {
    var background: CGColor?
    var roof: CGColor
    var face: CGColor
    var features: CGColor?   // eyes and smile; nil = cut out of the face (tinted)
    var wave: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let styles: [(String, Style)] = [
    ("AppIcon-Light.png", Style(background: rgb(0xF05A62), roof: rgb(0xFFFFFF, 0.7), face: rgb(0xFFFFFF),
                                features: rgb(0x000000), wave: rgb(0xFFFFFF))),
    ("AppIcon-Dark.png", Style(background: rgb(0x000000), roof: rgb(0xFF8A90, 0.6), face: rgb(0xFF8A90),
                               features: rgb(0x000000), wave: rgb(0xFFFFFF))),
    ("AppIcon-Tinted.png", Style(background: nil, roof: rgb(0xFFFFFF, 0.6), face: rgb(0xFFFFFF),
                                 features: nil, wave: rgb(0xFFFFFF))),
]

/// The lake's wave: "M 16 79 q 8.5 -8 17 0 t 17 0 t 17 0 t 17 0" (each t mirrors the previous control point).
func wave() -> CGPath {
    let path = CGMutablePath()
    var point = CGPoint(x: 16, y: 79)
    var control = CGPoint(x: point.x + 8.5, y: point.y - 8)
    path.move(to: point)
    for index in 0..<4 {
        let end = CGPoint(x: point.x + 17, y: point.y)
        if index > 0 { control = CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y) }
        path.addQuadCurve(to: end, control: control)
        point = end
    }
    return path
}

func draw(_ style: Style, size: Int) -> Data? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // The App Store rejects an app icon with an alpha channel; only the tinted one needs transparency.
    let alpha = style.background == nil ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: alpha.rawValue) else {
        return nil
    }
    let side = CGFloat(size)
    if let background = style.background {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    // The 100 × 100 artwork, 70/80 of the tile, centred; SVG y points down.
    let art = side * 70 / 80
    context.translateBy(x: (side - art) / 2, y: side - (side - art) / 2)
    context.scaleBy(x: art / 100, y: -art / 100)

    context.setFillColor(style.roof)
    context.addPath(CGPath(roundedRect: CGRect(x: 36, y: 11, width: 28, height: 7), cornerWidth: 3.5,
                           cornerHeight: 3.5, transform: nil))
    context.fillPath()
    context.setFillColor(style.face)
    context.addPath(CGPath(roundedRect: CGRect(x: 20, y: 22, width: 60, height: 42), cornerWidth: 15,
                           cornerHeight: 15, transform: nil))
    context.fillPath()

    // Eyes and smile: drawn in black, or cut out of the face for the tinted icon.
    if let features = style.features {
        context.setFillColor(features)
        context.setStrokeColor(features)
    } else {
        context.setBlendMode(.clear)
    }
    for x in [40.0, 60.0] {
        context.fillEllipse(in: CGRect(x: x - 6, y: 35, width: 12, height: 12))
    }
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: 43, y: 52))
    smile.addQuadCurve(to: CGPoint(x: 57, y: 52), control: CGPoint(x: 50, y: 58))
    context.setLineWidth(3.5)
    context.setLineCap(.round)
    context.addPath(smile)
    context.strokePath()
    context.setBlendMode(.normal)

    context.setStrokeColor(style.wave)
    context.setLineWidth(7)
    context.addPath(wave())
    context.strokePath()

    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for (name, style) in styles {
    guard let png = draw(style, size: 1024) else { fatalError("could not draw \(name)") }
    try png.write(to: folder.appendingPathComponent(name))
    print("wrote \(name)")
}
