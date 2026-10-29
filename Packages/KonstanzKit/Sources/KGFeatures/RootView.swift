import KGCore
import KGDesign
import SwiftUI

/// The app's way in: the start animation, then onboarding the first time, then home. Home is still the
/// Milestone 0 placeholder until the map arrives (plan S4).
public struct RootView: View {
    enum Stage { case start, onboarding, home }

    let info: TimetableInfo?
    @State private var stage = Stage.start
    @State private var onboarding: OnboardingModel
    /// The first start plays the full animation; later starts the short one (S1.4).
    private let shortStart: Bool

    public init(info: TimetableInfo?, permissions: PermissionAsking, defaults: UserDefaults = .standard) {
        self.info = info
        let model = OnboardingModel(defaults: defaults, permissions: permissions)
        _onboarding = State(initialValue: model)
        shortStart = model.isFinished
    }

    public var body: some View {
        ZStack {
            switch stage {
            case .start:
                StartScreen(short: shortStart) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        stage = onboarding.isFinished ? .home : .onboarding
                    }
                }
                .transition(.opacity)
            case .onboarding:
                OnboardingFlow(model: onboarding) {
                    withAnimation(.easeInOut(duration: 0.35)) { stage = .home }
                }
                .transition(.opacity)
            case .home:
                HomePlaceholder(info: info) {
                    onboarding.reset()
                    withAnimation(.easeInOut(duration: 0.35)) { stage = .start }
                }
                .transition(.opacity)
            }
        }
    }
}

/// What home shows until the map is built: the bundled timetable's date, and a way to see onboarding again.
public struct HomePlaceholder: View {
    let info: TimetableInfo?
    let onReplay: () -> Void

    public init(info: TimetableInfo?, onReplay: @escaping () -> Void) {
        self.info = info
        self.onReplay = onReplay
    }

    public var body: some View {
        VStack(spacing: KGSpace.medium) {
            Text(verbatim: "KonstanzGo")
                .kgFont(.titleL)
                .foregroundStyle(KGColor.ink)
                .accessibilityIdentifier("appTitle")
            if let info, let end = Calendar.konstanz.date(from: info.validUntil) {
                // Formatted by Text, so it follows the view's locale, not the device's.
                Text("Fahrplan bis \(end, format: .dateTime.day().month().year())", bundle: .module)
                    .kgFont(.body)
                    .foregroundStyle(KGColor.ink2)
                    .accessibilityIdentifier("timetableStatus")
            } else {
                Text("Offline-Daten fehlen", bundle: .module)
                    .kgFont(.body)
                    .foregroundStyle(KGColor.ink2)
                    .accessibilityIdentifier("timetableStatus")
            }
            KGTextButton(Text("Einführung noch einmal ansehen", bundle: .module), action: onReplay)
                .padding(.top, KGSpace.xl)
                .accessibilityIdentifier("replayOnboarding")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KGColor.surface.ignoresSafeArea())
    }
}

#Preview("Daten da") {
    HomePlaceholder(info: TimetableInfo(
        feedVersion: "20261011",
        validFrom: DateComponents(year: 2026, month: 7, day: 12),
        validUntil: DateComponents(year: 2026, month: 12, day: 12),
        attribution: "Datensatz der NVBW GmbH",
        stations: 142, platforms: 263, cityLines: 18, trips: 3380
    )) {}
}

#Preview("Daten fehlen") {
    HomePlaceholder(info: nil) {}
}

#Preview("Onboarding") {
    RootView(info: nil, permissions: FixedPermissions(allow: true),
             defaults: UserDefaults(suiteName: "preview") ?? .standard)
}
