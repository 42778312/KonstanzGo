import KGDesign
import SwiftUI

/// Back chevron and the progress bar, 44 high, 11 pt under the safe area (screens 02–05).
struct OnboardingHeader: View {
    let step: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: KGSpace.compact) {
            Button(action: onBack) {
                KGIconView(.back, size: 24)
                    .foregroundStyle(KGColor.clearButton)
                    .frame(width: KGSize.touch, height: KGSize.touch)
                    .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Zurück", bundle: .module))
            KGStepProgress(step: step, of: OnboardingModel.Step.counted)
        }
        .padding(.leading, KGSpace.medium)
        .padding(.trailing, KGSpace.large)
        .frame(height: KGSize.touch)
        .padding(.top, 11)
    }
}

/// Small Seeri (96 × 102) on the left saying something in a bubble on its right (screens 03–05).
struct SeeriSays: View {
    let expression: Seeri.Expression
    let text: Text

    var body: some View {
        HStack(alignment: .center, spacing: KGSpace.screen) {
            SeeriAlive(expression)
                .frame(width: 96, height: 102)
            KGSpeechBubble(text, size: .side)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, KGSpace.screen)
        .padding(.trailing, KGSpace.large)
        .padding(.top, KGSpace.screen)
        .accessibilityElement(children: .combine)
    }
}

/// One promise under the illustration: grey 48 pt circle with a coral icon, title 17 Bold, line 15 grey.
struct FeatureRow: View {
    let icon: KGIcon
    let title: Text
    let detail: Text

    var body: some View {
        HStack(spacing: KGSpace.mediumLarge) {
            KGIconView(icon, size: 24)
                .foregroundStyle(KGColor.coral)
                .frame(width: 48, height: 48)
                .background(KGColor.pressed, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                title.kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                detail.kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The two feature rows at the bottom of screens 03 and 04, rising in one after the other.
struct FeatureList: View {
    let rows: [FeatureRow]
    /// When the first row rises in; the next follows 0.15 s later (the design's timings).
    let delay: Double

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.large) {
            ForEach(rows.indices, id: \.self) { index in
                rows[index].riseIn(after: delay + Double(index) * 0.15)
            }
        }
        .padding(.horizontal, KGSpace.xxl)
    }
}

/// The page frame: content on top, the buttons 20 pt from the sides and 10 pt over the bottom safe area.
struct OnboardingPage<Content: View, Buttons: View>: View {
    let content: Content
    let buttons: Buttons

    init(@ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.content = content()
        self.buttons = buttons()
    }

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxHeight: .infinity, alignment: .top)
            VStack(spacing: KGSpace.xxs) { buttons }
                .padding(.horizontal, KGSpace.large)
                .padding(.bottom, KGSpace.compact)
        }
    }
}

extension View {
    /// Appears after `delay` seconds with a pop (k-pop), or a fade with Reduce Motion.
    func popIn(after delay: Double) -> some View {
        modifier(PopIn(delay: delay))
    }
}

private struct PopIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(KGMotion.animation(KGMotion.pop, reduceMotion: reduceMotion)?.delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// k-up after `delay` seconds: 18 pt up and fade in; a fade with Reduce Motion.
    func riseIn(after delay: Double) -> some View {
        modifier(RiseAfter(delay: delay))
    }
}

private struct RiseAfter: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : KGMotion.riseDistance)
            .onAppear {
                withAnimation(KGMotion.animation(KGMotion.rise, reduceMotion: reduceMotion)?.delay(delay)) {
                    shown = true
                }
            }
    }
}

/// A point on an illustration's grid; keeps the design's coordinate lists short.
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
