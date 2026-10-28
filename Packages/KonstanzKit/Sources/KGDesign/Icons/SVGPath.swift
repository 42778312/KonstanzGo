import SwiftUI

/// Reads SVG path data ("M20.5 3.5 3.8 10.6c-.8.4-.7 1.5.1 1.7z") into a SwiftUI `Path`.
/// Supports every command (M L H V C S Q T A Z, absolute and relative), repeated parameters, and the compact
/// number forms SVG allows ("-.8.4" is −0.8, 0.4). Used for the design's icons.
public enum SVGPath {
    public enum Failure: Error, Equatable { case unknownCommand(Character), missingNumber }

    public static func path(_ data: String) throws -> Path {
        var builder = Builder(scanner: Scanner(Array(data)))
        var command: Character = "M"
        while builder.scanner.skipSeparators() {
            if let letter = builder.scanner.letter() {
                command = letter
            } else if command == "M" || command == "m" {
                // Numbers after a move are implicit line-tos.
                command = command == "M" ? "L" : "l"
            }
            try builder.apply(command)
        }
        return builder.path
    }

    /// The path drawn so far, the pen position and the last curve control point (for S and T).
    private struct Builder {
        var scanner: Scanner
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var relative = false

        mutating func point() throws -> CGPoint {
            let x = try scanner.number(), y = try scanner.number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        mutating func apply(_ command: Character) throws {
            relative = command.isLowercase
            var control: CGPoint?
            switch command.uppercased().first ?? command {
            case "M": current = try point(); start = current; path.move(to: current)
            case "L": current = try point(); path.addLine(to: current)
            case "H": try horizontal()
            case "V": try vertical()
            case "C", "S": control = try cubic(smooth: command.uppercased() == "S")
            case "Q", "T": control = try quadratic(smooth: command.uppercased() == "T")
            case "A": try arc()
            case "Z": path.closeSubpath(); current = start
            default: throw Failure.unknownCommand(command)
            }
            lastControl = control
        }

        mutating func horizontal() throws {
            let x = try scanner.number()
            current.x = relative ? current.x + x : x
            path.addLine(to: current)
        }

        mutating func vertical() throws {
            let y = try scanner.number()
            current.y = relative ? current.y + y : y
            path.addLine(to: current)
        }

        /// C, or S with the first control point mirrored from the previous curve. Returns the second control.
        mutating func cubic(smooth: Bool) throws -> CGPoint {
            let first = smooth ? reflect(lastControl, around: current) : try point()
            let second = try point(), end = try point()
            path.addCurve(to: end, control1: first, control2: second)
            current = end
            return second
        }

        /// Q, or T with the control point mirrored from the previous curve. Returns the control.
        mutating func quadratic(smooth: Bool) throws -> CGPoint {
            let middle = smooth ? reflect(lastControl, around: current) : try point()
            let end = try point()
            path.addQuadCurve(to: end, control: middle)
            current = end
            return middle
        }

        mutating func arc() throws {
            let radii = CGSize(width: try scanner.number(), height: try scanner.number())
            let rotation = try scanner.number()
            let large = try scanner.flag(), sweep = try scanner.flag()
            let end = try point()
            SVGPath.addArc(to: &path, from: current, to: end, radii: radii, rotation: rotation,
                           largeArc: large, sweep: sweep)
            current = end
        }
    }

    private static func reflect(_ control: CGPoint?, around point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    // Variable names follow the SVG 1.1 spec's formulas (appendix F.6), so the code can be checked against it.
    // swiftlint:disable identifier_name function_parameter_count
    /// SVG's endpoint arc as a center arc (SVG 1.1, appendix F.6), drawn on a unit circle transformed to the ellipse.
    private static func addArc(to path: inout Path, from start: CGPoint, to end: CGPoint, radii: CGSize,
                               rotation degrees: Double, largeArc: Bool, sweep: Bool) {
        var rx = abs(radii.width), ry = abs(radii.height)
        guard rx > 0, ry > 0, start != end else { path.addLine(to: end); return }
        let phi = degrees * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let scale = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if scale > 1 { rx *= scale.squareRoot(); ry *= scale.squareRoot() }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let center = CGPoint(x: cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2,
                             y: sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2)
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let value = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return value
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi } else if sweep, delta < 0 { delta += 2 * .pi }
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: phi).scaledBy(x: rx, y: ry)
        path.addRelativeArc(center: .zero, radius: 1, startAngle: .radians(theta), delta: .radians(delta),
                            transform: transform)
    }

    // swiftlint:enable identifier_name function_parameter_count

    /// Reads numbers, flags and command letters from path data.
    private struct Scanner {
        let characters: [Character]
        var index = 0

        init(_ characters: [Character]) { self.characters = characters }

        /// Skips spaces and commas; false at the end.
        mutating func skipSeparators() -> Bool {
            while index < characters.count, characters[index] == " " || characters[index] == ","
                || characters[index].isNewline || characters[index] == "\t" { index += 1 }
            return index < characters.count
        }

        mutating func letter() -> Character? {
            _ = skipSeparators()
            guard index < characters.count, characters[index].isLetter, characters[index] != "e",
                  characters[index] != "E" else { return nil }
            defer { index += 1 }
            return characters[index]
        }

        /// A number: sign, digits, one decimal point, exponent. "-.8.4" reads as −0.8 then 0.4.
        mutating func number() throws -> Double {
            _ = skipSeparators()
            let first = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            var seenDot = false, seenDigit = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    seenDigit = true
                } else if character == ".", !seenDot {
                    seenDot = true
                } else if character == "e" || character == "E", seenDigit {
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
                    continue
                } else {
                    break
                }
                index += 1
            }
            guard seenDigit, let value = Double(String(characters[first..<index])) else { throw Failure.missingNumber }
            return value
        }

        /// Arc flags may be written without separators ("a8 8 0 1 1-2.3-5.6" or "011").
        mutating func flag() throws -> Bool {
            _ = skipSeparators()
            guard index < characters.count, characters[index] == "0" || characters[index] == "1" else {
                throw Failure.missingNumber
            }
            defer { index += 1 }
            return characters[index] == "1"
        }
    }
}
