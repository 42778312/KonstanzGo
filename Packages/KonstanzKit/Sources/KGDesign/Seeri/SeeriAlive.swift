import SwiftUI

/// Seeri with a bit of life: blinks every few seconds and bounces gently (k-bounce), only while on screen and
/// never with Reduce Motion (plan A6.2, A4.2).
public struct SeeriAlive: View {
    let seeri: (Double) -> Seeri
    /// Nil: no police light on the roof.
    let siren: Bool?
    @State private var bouncing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Blinks happen at these points of a 4.2 s cycle (seconds); a blink lasts 0.16 s.
    nonisolated static let blinkCycle = 4.2
    nonisolated static let blinkLength = 0.16

    public init(_ expression: Seeri.Expression = .happy, detail: Seeri.Detail = .full, hat: Seeri.Hat = .none,
                shadow: Bool = false, sign: String? = nil, sirenFlashing: Bool? = nil) {
        siren = sirenFlashing
        seeri = { blink in Seeri(expression, detail: detail, hat: hat, shadow: shadow, blink: blink, sign: sign) }
    }

    /// How closed the eyes are at `time` (0 open … 1 shut), a quick close-and-open once per cycle.
    nonisolated static func blink(at time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: blinkCycle)
        guard phase < blinkLength else { return 0 }
        return 1 - abs(phase / blinkLength * 2 - 1)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            seeri(reduceMotion ? 0 : Self.blink(at: timeline.date.timeIntervalSinceReferenceDate))
        }
        .overlay(alignment: .top) {
            if let siren {
                GeometryReader { proxy in
                    SeeriSiren(isFlashing: siren)
                        .frame(width: proxy.size.width * 0.36, height: proxy.size.width * 0.2)
                        .position(x: proxy.size.width / 2, y: -proxy.size.width * 0.04)
                }
            }
        }
        // Squash and stretch from the wheels up.
        .scaleEffect(x: bouncing ? 0.98 : 1, y: bouncing ? 1.03 : 1, anchor: .bottom)
        .offset(y: bouncing ? -4 : 0)
        .kgLoop(.seeriBounce, phase: $bouncing)
    }
}

#Preview("Seeri, alive") {
    SeeriAlive(.excited, shadow: true).frame(height: 160)
}

/// A police light for Seeri's roof: red and blue in turn with a glow while there's news, a calm blue while
/// something's still going on.
public struct SeeriSiren: View {
    let isFlashing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isFlashing: Bool) {
        self.isFlashing = isFlashing
    }

    /// Which colour is lit at `time`: two quick flashes each, about twice a second.
    nonisolated static func isRed(at time: TimeInterval) -> Bool {
        time.truncatingRemainder(dividingBy: 0.7) < 0.35
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isFlashing || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let color = isFlashing && (reduceMotion || Self.isRed(at: time)) ? Color.red : Color.blue
            let pulse = isFlashing && !reduceMotion ? 0.65 + 0.35 * abs(sin(time * 9)) : 0.5
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .bottom) {
                    Circle().fill(color.opacity(0.55 * pulse)).blur(radius: width * 0.28)
                        .frame(width: width * 1.5, height: width * 1.5)
                        .position(x: width / 2, y: proxy.size.height * 0.45)
                    UnevenRoundedRectangle(topLeadingRadius: width * 0.42, topTrailingRadius: width * 0.42)
                        .fill(color)
                        .overlay(alignment: .topLeading) {
                            Capsule().fill(.white.opacity(0.75))
                                .frame(width: width * 0.22, height: width * 0.28)
                                .offset(x: width * 0.2, y: width * 0.12)
                        }
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: width * 0.42, topTrailingRadius: width * 0.42)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 1))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
