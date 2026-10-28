import SwiftUI

/// The design's animations (its CSS keyframes) as SwiftUI animations. Every one has a Reduce Motion version:
/// loops stop and movement becomes a short fade (plan A4.2).
public enum KGMotion {
    /// k-up: content rising 18 pt and fading in. cubic-bezier(.2, .8, .2, 1), 0.45 s.
    public static let rise = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)
    public static let riseDistance: CGFloat = 18
    /// k-sheet: the bottom sheet coming up 120 pt. cubic-bezier(.2, .9, .3, 1), 0.6 s.
    public static let sheet = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.6)
    public static let sheetDistance: CGFloat = 120
    /// k-pop: scale 0.6 → 1.08 → 1 (chips, check marks).
    public static let pop = Animation.spring(response: 0.35, dampingFraction: 0.55)
    public static let popStart: CGFloat = 0.6
    /// Delay between list items appearing one after another.
    public static let stagger: Double = 0.06
    /// The selected segment / tab capsule sliding.
    public static let slide = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// k-drive: Seeri driving in from the left with a tilt and overshoot, 1 s.
    public static let drive = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 1)

    /// Looping animations: duration of one cycle, from the design.
    public enum Loop: Double, Sendable, CaseIterable {
        /// k-live: the live dot's ring, scale 1 → 2.6, fading out.
        case livePulse = 1.3
        /// k-pulse: the user's location ring, scale 1 → 3.4.
        case locationPulse = 2.4
        /// k-busbob: buses bobbing 1 pt.
        case busBob = 0.5
        /// k-peek: Seeri peeking over the sheet, 6 pt up and −3°.
        case seeriPeek = 2.6
        /// k-bounce: Seeri's squash and stretch.
        case seeriBounce = 1.6

        public var animation: Animation {
            switch self {
            case .livePulse, .locationPulse: .easeOut(duration: rawValue).repeatForever(autoreverses: false)
            case .busBob, .seeriPeek, .seeriBounce: .easeInOut(duration: rawValue / 2).repeatForever(autoreverses: true)
            }
        }
    }

    /// The animation to use, or a short fade (or nothing for loops) when Reduce Motion is on.
    public static func animation(_ animation: Animation, reduceMotion: Bool, isLoop: Bool = false) -> Animation? {
        guard reduceMotion else { return animation }
        return isLoop ? nil : .easeInOut(duration: 0.2)
    }
}

extension View {
    /// k-up: rises into place when it appears, `index` steps after the first (stagger). A fade with Reduce Motion.
    public func kgRiseIn(index: Int = 0) -> some View {
        modifier(RiseIn(index: index))
    }

    /// Runs a looping animation only while the view is on screen and the app is active (plan A4.3); never with
    /// Reduce Motion. `phase` flips between false and true; drive the loop's look from it.
    public func kgLoop(_ loop: KGMotion.Loop, phase: Binding<Bool>) -> some View {
        modifier(LoopModifier(loop: loop, phase: phase))
    }
}

private struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : KGMotion.riseDistance)
            .onAppear {
                let animation = KGMotion.animation(KGMotion.rise, reduceMotion: reduceMotion)?
                    .delay(Double(index) * KGMotion.stagger)
                withAnimation(animation) { shown = true }
            }
    }
}

private struct LoopModifier: ViewModifier {
    let loop: KGMotion.Loop
    @Binding var phase: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true; update() }
            .onDisappear { visible = false; update() }
            .onChange(of: scenePhase) { update() }
            .onChange(of: reduceMotion) { update() }
    }

    private func update() {
        let running = visible && scenePhase == .active && !reduceMotion
        if running {
            withAnimation(loop.animation) { phase = true }
        } else {
            // Setting it without animation stops the repeating animation at rest.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { phase = false }
        }
    }
}

/// When the app gives haptic feedback (plan A4.4): selections, success, warnings. Nothing on plain taps.
public enum KGHaptic {
    /// Segmented controls, time wheels, tab changes.
    public static let selection = SensoryFeedback.selection
    /// Saved, alarm set.
    public static let success = SensoryFeedback.success
    /// Delete.
    public static let warning = SensoryFeedback.warning
    /// Pin dropped on the map.
    public static let drop = SensoryFeedback.impact(weight: .medium)
}
