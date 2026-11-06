import KGDesign
import SwiftUI

/// The intro in one flow (plan S3): the real app step by step, the permissions, "Alles bereit". "Losfahren"
/// calls `onFinish`.
public struct OnboardingFlow: View {
    @Bindable var model: OnboardingModel
    let loader: TransitLoader
    let onFinish: () -> Void
    /// The app's own parts, for the intro to show.
    @State private var services: AppServices?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: OnboardingModel, loader: TransitLoader, onFinish: @escaping () -> Void) {
        self.model = model
        self.loader = loader
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
        .background(KGGlassBackdrop().ignoresSafeArea())
        .onChange(of: loader.transit != nil, initial: true) { _, ready in
            guard ready, services == nil, let transit = loader.transit, let data = loader.data else { return }
            services = AppServices(data: data, transit: transit, location: LocationModel())
        }
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome:
            if let services {
                IntroSteps(services: services) { go { model.next() } }
            } else if loader.failed {
                // Without the offline data there's nothing to show; home says what's wrong.
                Color.clear.onAppear(perform: onFinish)
            } else {
                SeeriAlive(.happy).frame(width: 120, height: 128)
            }
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
