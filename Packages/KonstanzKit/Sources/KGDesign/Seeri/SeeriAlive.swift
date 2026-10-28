import SwiftUI

/// Seeri with a bit of life: blinks every few seconds and bounces gently (k-bounce), only while on screen and
/// never with Reduce Motion (plan A6.2, A4.2).
public struct SeeriAlive: View {
    let seeri: (Double) -> Seeri
    @State private var bouncing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Blinks happen at these points of a 4.2 s cycle (seconds); a blink lasts 0.16 s.
    nonisolated static let blinkCycle = 4.2
    nonisolated static let blinkLength = 0.16

    public init(_ expression: Seeri.Expression = .happy, detail: Seeri.Detail = .full, hat: Seeri.Hat = .none,
                shadow: Bool = false) {
        seeri = { blink in Seeri(expression, detail: detail, hat: hat, shadow: shadow, blink: blink) }
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
        // Squash and stretch from the wheels up.
        .scaleEffect(x: bouncing ? 0.98 : 1, y: bouncing ? 1.03 : 1, anchor: .bottom)
        .offset(y: bouncing ? -4 : 0)
        .kgLoop(.seeriBounce, phase: $bouncing)
    }
}

#Preview("Seeri, alive") {
    SeeriAlive(.excited, shadow: true).frame(height: 160)
}
