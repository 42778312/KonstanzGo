// Renders the map's buses and trains: real 3D models, seen from the map's fixed angle, at every 10° of heading.
// The map shows the picture for each vehicle's direction, which looks 3D and costs no more than an icon.
//
//     swift Design/tools/make_vehicle_sprites.swift Packages/KonstanzKit/Sources/KGDesign/Resources/Vehicles [contact-sheet.png]
//
// Forward is -Z (north, up the screen), left is -X. One scene metre is 2 points on screen.
import AppKit
import Metal
import SceneKit

let frames = 36, points = 46, pixelScale = 3, supersample = 2
let elevation = 40.0 * .pi / 180

/// The colour mixed towards white, for a roof that catches the light without losing the vehicle's colour.
func lighter(_ hex: UInt32, _ share: Double) -> UInt32 {
    func mix(_ shift: UInt32) -> UInt32 {
        let channel = Double(hex >> shift & 0xFF)
        return UInt32(channel + (255 - channel) * share) << shift
    }
    return mix(16) | mix(8) | mix(0)
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func material(_ hex: UInt32, shine: CGFloat = 0.25, glow: Bool = false) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .blinn
    material.diffuse.contents = color(hex)
    material.specular.contents = NSColor(white: shine, alpha: 1)
    material.shininess = 0.6
    if glow { material.emission.contents = color(hex) }
    return material
}

@discardableResult
func box(_ parent: SCNNode, x: CGFloat = 0, y: CGFloat, z: CGFloat = 0, width: CGFloat, height: CGFloat, length: CGFloat,
         chamfer: CGFloat = 0.08, _ paint: SCNMaterial) -> SCNNode {
    let shape = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
    shape.chamferSegmentCount = 3
    shape.materials = [paint]
    let node = SCNNode(geometry: shape)
    node.position = SCNVector3(x, y, z)
    parent.addChildNode(node)
    return node
}

func wheels(_ parent: SCNNode, at places: [CGFloat], halfWidth: CGFloat) {
    let tyre = material(0x15181D, shine: 0.05), hub = material(0xC9CED6)
    for z in places {
        for side: CGFloat in [-1, 1] {
            let shape = SCNCylinder(radius: 0.62, height: 0.5)
            shape.materials = [tyre]
            let node = SCNNode(geometry: shape)
            node.eulerAngles.z = .pi / 2
            node.position = SCNVector3(side * halfWidth, 0.62, z)
            parent.addChildNode(node)
            let cap = SCNCylinder(radius: 0.28, height: 0.54)
            cap.materials = [hub]
            let capNode = SCNNode(geometry: cap)
            capNode.eulerAngles.z = .pi / 2
            capNode.position = node.position
            parent.addChildNode(capNode)
        }
    }
}

func lamps(_ parent: SCNNode, side: CGFloat, name: String, front: CGFloat, back: CGFloat, halfWidth: CGFloat) {
    let amber = material(0xFFB300, glow: true)
    for z in [front, back] {
        let shape = SCNSphere(radius: 0.62)
        shape.materials = [amber]
        let node = SCNNode(geometry: shape)
        node.name = name
        node.position = SCNVector3(side * halfWidth, 2.9, z)
        parent.addChildNode(node)
    }
}

/// A low-floor city bus, a little wider and taller than life so it reads at this size.
func bus(_ body: UInt32) -> SCNNode {
    let root = SCNNode(), length: CGFloat = 12, width: CGFloat = 3.6
    let paint = material(body, shine: 0.35), glass = material(0x101A28, shine: 0.9), roof = material(lighter(body, 0.14), shine: 0.2)
    let skirt = material(0x262B33, shine: 0.1), white = material(0xFFFFFF, glow: true), red = material(0xFF2A2A, glow: true)
    wheels(root, at: [-3.6, 3.4], halfWidth: width / 2 - 0.1)
    box(root, y: 0.95, width: width - 0.1, height: 0.7, length: length - 0.3, chamfer: 0.2, skirt)
    box(root, y: 2.15, width: width, height: 2.5, length: length, chamfer: 0.55, paint)
    box(root, y: 2.75, z: 0.5, width: width + 0.06, height: 1.05, length: length - 2.7, chamfer: 0.12, glass)
    box(root, y: 2.45, z: -length / 2 + 0.1, width: width - 0.5, height: 1.55, length: 0.3, chamfer: 0.12, glass)
    box(root, y: 2.8, z: length / 2 - 0.1, width: width - 0.9, height: 0.8, length: 0.25, chamfer: 0.1, glass)
    box(root, y: 3.42, width: width - 0.6, height: 0.2, length: length - 1.4, chamfer: 0.1, roof)
    box(root, y: 3.62, z: 1.6, width: width - 1.6, height: 0.34, length: 3, chamfer: 0.14, material(lighter(body, 0.32)))
    for side: CGFloat in [-1, 1] {
        box(root, x: side * (width / 2 - 0.55), y: 1.35, z: -length / 2 + 0.02, width: 0.6, height: 0.34, length: 0.2, white)
        box(root, x: side * (width / 2 - 0.45), y: 1.5, z: length / 2 - 0.02, width: 0.5, height: 0.5, length: 0.2, red)
    }
    lamps(root, side: -1, name: "left", front: -length / 2 + 0.5, back: length / 2 - 0.5, halfWidth: width / 2)
    lamps(root, side: 1, name: "right", front: -length / 2 + 0.5, back: length / 2 - 0.5, halfWidth: width / 2)
    return root
}

/// A regional train: long, low, with a sloped nose and a band of windows.
func train(_ body: UInt32) -> SCNNode {
    let root = SCNNode(), length: CGFloat = 17, width: CGFloat = 3.5, top: CGFloat = 3.7, floor: CGFloat = 0.8
    let paint = material(body, shine: 0.4), glass = material(0x0E1726, shine: 0.95), roof = material(lighter(body, 0.14), shine: 0.2)
    let white = material(0xFFFFFF, glow: true), red = material(0xFF2A2A, glow: true)
    // The side view, extruded across the train.
    func profile(_ inset: CGFloat) -> NSBezierPath {
        let half = length / 2 - inset, path = NSBezierPath()
        path.move(to: CGPoint(x: -half + 0.6, y: floor))
        path.line(to: CGPoint(x: half - 0.1, y: floor))
        path.curve(to: CGPoint(x: half - 3.1, y: top - inset), controlPoint1: CGPoint(x: half + 0.3, y: floor + 1.5),
                   controlPoint2: CGPoint(x: half - 1.5, y: top - inset))
        path.line(to: CGPoint(x: -half + 0.9, y: top - inset))
        path.curve(to: CGPoint(x: -half + 0.6, y: floor), controlPoint1: CGPoint(x: -half, y: top - inset),
                   controlPoint2: CGPoint(x: -half, y: floor + 1))
        path.close()
        path.flatness = 0.02
        return path
    }
    let shape = SCNShape(path: profile(0), extrusionDepth: width)
    shape.chamferRadius = 0.12
    shape.materials = [paint]
    let holder = SCNNode(geometry: shape)
    holder.eulerAngles.y = .pi / 2   // Its +X (the nose) points to -Z.
    root.addChildNode(holder)
    // The windscreen, lying on the slope of the nose.
    let screen = box(root, y: 2.75, z: -length / 2 + 1.75, width: width - 0.5, height: 1.75, length: 0.16, chamfer: 0.06, glass)
    screen.eulerAngles.x = -0.85
    box(root, y: 2.75, z: 1.25, width: width + 0.08, height: 0.95, length: length - 5.2, chamfer: 0.1, glass)
    box(root, y: 1.3, z: 1.4, width: width + 0.08, height: 0.22, length: length - 3.6, chamfer: 0.04, material(0xFFFFFF))
    box(root, y: top + 0.03, z: 1.3, width: width - 0.7, height: 0.14, length: length - 5, chamfer: 0.06, roof)
    box(root, y: top + 0.2, z: 3, width: 1.6, height: 0.3, length: 2.6, chamfer: 0.12, material(lighter(body, 0.32)))
    box(root, y: top + 0.2, z: -1.6, width: 1.6, height: 0.3, length: 2.6, chamfer: 0.12, material(lighter(body, 0.32)))
    box(root, y: 0.5, z: -4.8, width: width - 0.5, height: 0.7, length: 3.2, chamfer: 0.1, material(0x20242B))
    box(root, y: 0.5, z: 4.8, width: width - 0.5, height: 0.7, length: 3.2, chamfer: 0.1, material(0x20242B))
    for side: CGFloat in [-1, 1] {
        box(root, x: side * 1.1, y: 1.3, z: -length / 2 + 0.2, width: 0.55, height: 0.3, length: 0.3, white)
        box(root, x: side * 1.2, y: 1.6, z: length / 2 - 0.1, width: 0.4, height: 0.4, length: 0.2, red)
    }
    return root
}

let device = MTLCreateSystemDefaultDevice()!
let renderer = SCNRenderer(device: device, options: nil)

func render(_ model: SCNNode, heading: Double) -> CGImage {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let holder = SCNNode()
    holder.addChildNode(model.clone())
    holder.eulerAngles.y = CGFloat(-heading * .pi / 180)
    scene.rootNode.addChildNode(holder)

    let camera = SCNCamera()
    camera.usesOrthographicProjection = true
    camera.orthographicScale = Double(points) / 2 / 2
    camera.zNear = 1
    camera.zFar = 200
    let eye = SCNNode()
    eye.camera = camera
    eye.position = SCNVector3(0, 60 * sin(elevation) + 1.6, 60 * cos(elevation))
    eye.look(at: SCNVector3(0, 1.6, 0))
    scene.rootNode.addChildNode(eye)

    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 480
    scene.rootNode.addChildNode(ambient)
    for (x, y, power) in [(-0.7, -0.75, 620.0), (0.8, -0.25, 170.0)] {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = power
        sun.eulerAngles = SCNVector3(CGFloat(y * .pi / 2), CGFloat(x * .pi / 2), 0)
        scene.rootNode.addChildNode(sun)
    }
    renderer.scene = scene
    let size = CGFloat(points * pixelScale * supersample)
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

/// The picture with a soft ground shadow and a glow in the vehicle's colour, so it lifts off the dark map.
func finish(_ image: CGImage, glow: UInt32?, name: String, to folder: URL) -> CGImage {
    let side = points * pixelScale
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    if let glow {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 15, color: color(glow).withAlphaComponent(0.8).cgColor)
        context.draw(image, in: rect)
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: NSColor.black.withAlphaComponent(0.55).cgColor)
        context.draw(image, in: rect)
        context.restoreGState()
    } else {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 10, color: color(0xFFB300).cgColor)
        context.draw(image, in: rect)
        context.restoreGState()
    }
    context.draw(image, in: rect)
    let output = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: output)
    rep.size = NSSize(width: points, height: points)
    try! rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(name)@3x.png"))
    return output
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var sheet: [CGImage] = []

func walk(_ node: SCNNode, _ body: (SCNNode) -> Void) {
    body(node)
    node.childNodes.forEach { walk($0, body) }
}

for (kind, model, glow) in [("bus-red", bus(0xD93A44), UInt32(0xF05A62)), ("bus-yellow", bus(0xFFCC00), 0xFFCC00), ("train", train(0x5457E0), 0x7B7EFF)] {
    let plain = model.clone()
    walk(plain) { if $0.name != nil { $0.isHidden = true } }
    for frame in 0..<frames {
        let image = finish(render(plain, heading: Double(frame * 10)), glow: glow, name: String(format: "\(kind)-%02d", frame), to: folder)
        if frame % 3 == 0 { sheet.append(image) }
    }
}

// The indicators alone, hidden by the bus where it stands in front of them, laid over the plain bus when it turns.
for side in ["left", "right"] {
    let model = bus(0xD93A44)
    walk(model) { node in
        if let name = node.name {
            node.isHidden = name != side
        } else {
            node.geometry?.materials.forEach { $0.colorBufferWriteMask = [] }
        }
    }
    for frame in 0..<frames {
        let image = finish(render(model, heading: Double(frame * 10)), glow: nil, name: String(format: "blink-\(side)-%02d", frame), to: folder)
        if side == "left", frame % 3 == 0 { sheet.append(image) }
    }
}

if CommandLine.arguments.count > 2 {
    let cell = points * pixelScale, columns = 12, rows = sheet.count / columns
    let context = CGContext(data: nil, width: cell * columns, height: cell * rows, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(color(0x22304A).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: cell * columns, height: cell * rows))
    for (index, image) in sheet.enumerated() {
        context.draw(image, in: CGRect(x: index % columns * cell, y: (rows - 1 - index / columns) * cell, width: cell, height: cell))
    }
    try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
