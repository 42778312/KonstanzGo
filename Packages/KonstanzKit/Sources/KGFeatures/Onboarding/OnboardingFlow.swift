import KGDesign
import SwiftUI

/// The intro in one flow (plan S3): the motion graphic, the permissions, "Alles bereit". "Losfahren" calls
/// `onFinish`.
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
            if model.step == .permissions {
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
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome: IntroFilm { go { model.next() } }
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

}
