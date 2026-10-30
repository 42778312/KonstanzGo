import KGCore
import KGDesign
import SwiftUI

/// The app's way in: the start animation, then onboarding the first time, then home with the map.
public struct RootView: View {
    enum Stage { case start, onboarding, home }

    let info: TimetableInfo?
    @State private var stage: Stage
    @State private var onboarding: OnboardingModel
    /// Opens the timetable, search and walking data while the start animation plays (S1.2).
    @State private var loader: TransitLoader
    /// Onboarding just ended: Seeri shows the map.
    @State private var tourNext = false

    public init(info: TimetableInfo?, data: BundledData?, permissions: PermissionAsking,
                defaults: UserDefaults = .standard) {
        self.info = info
        _loader = State(initialValue: TransitLoader(data: data))
        let model = OnboardingModel(defaults: defaults, permissions: permissions)
        _onboarding = State(initialValue: model)
        // The logo shows on every launch: the short start screen, then the map (or onboarding the first time).
        _stage = State(initialValue: .start)
    }

    public var body: some View {
        ZStack {
            switch stage {
            case .start:
                StartScreen {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        stage = onboarding.isFinished ? .home : .onboarding
                    }
                }
                .transition(.opacity)
            case .onboarding:
                OnboardingFlow(model: onboarding) {
                    tourNext = true
                    withAnimation(.easeInOut(duration: 0.35)) { stage = .home }
                }
                .transition(.opacity)
            case .home:
                HomeView(loader: loader, startsTour: tourNext) {
                    onboarding.reset()
                    withAnimation(.easeInOut(duration: 0.35)) { stage = .start }
                }
                .transition(.opacity)
            }
        }
        // Always dark, with the Apple Maps night map (changed after testing on a phone).
        .preferredColorScheme(.dark)
    }
}

/// The bundled timetable's date and a way to see onboarding again (used before the map existed; kept for the
/// snapshot pipeline check).
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
    RootView(info: nil, data: nil, permissions: FixedPermissions(allow: true),
             defaults: UserDefaults(suiteName: "preview") ?? .standard)
}
