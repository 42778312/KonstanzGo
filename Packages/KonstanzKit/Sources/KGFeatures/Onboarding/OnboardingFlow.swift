import KGDesign
import SwiftUI

/// Screens 02–06 in one flow (plan S3): the header stays, the pages slide; swiping left goes on and right
/// goes back on the first three pages. "Losfahren" calls `onFinish`.
public struct OnboardingFlow: View {
    @Bindable var model: OnboardingModel
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: OnboardingModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            if model.step != .ready {
                OnboardingHeader(step: model.step.rawValue) { go { model.back() } }
            }
            ZStack {
                page
                    .id(model.step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(KGColor.surface.ignoresSafeArea())
        .simultaneousGesture(swipe)
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome: WelcomeStep { go { model.next() } }
        case .offline: OfflineStep { go { model.next() } }
        case .search: SearchStep { go { model.next() } }
        case .permissions: PermissionsStep(model: model)
        case .ready:
            ReadyStep(notificationsOn: model.notificationsAllowed) {
                model.finish()
                onFinish()
            }
        }
    }

    private func go(_ change: () -> Void) {
        withAnimation(KGMotion.animation(KGMotion.slide, reduceMotion: reduceMotion), change)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = model.movedForward ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: edge == .trailing ? .leading : .trailing).combined(with: .opacity))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                let swipeable: Set<OnboardingModel.Step> = [.welcome, .offline, .search]
                if value.translation.width < -60, swipeable.contains(model.step) {
                    go { model.next() }
                } else if value.translation.width > 60, model.step != .welcome, model.step != .ready {
                    go { model.back() }
                }
            }
    }
}
