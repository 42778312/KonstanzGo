import KGDesign
import SwiftUI

/// Screen 05: "Soll ich dir sagen, wann ich komme?" A sample notification slides in over a radar around
/// the user's dot; two switches choose what to allow; "Erlauben" asks iOS, "Später" asks nothing.
struct PermissionsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                SeeriSays(expression: .curious, text: Text("Soll ich dir sagen, wann ich komme?", bundle: .module))
                ZStack(alignment: .top) {
                    RadarScene()
                        .frame(height: 140)
                        .padding(.top, 80)
                    SampleNotification()
                        .padding(.horizontal, KGSpace.screen)
                }
                .padding(.top, 12)
                Spacer(minLength: KGSpace.large)
                permissionCard
                    .padding(.horizontal, KGSpace.large)
                    .riseIn(after: 0.9)
                Spacer(minLength: KGSpace.large)
            }
        } buttons: {
            Button {
                model.later()
            } label: {
                Text("Später", bundle: .module)
                    .kgFont(.body.weighted(KGFont.extraBold))
                    .tracking(0.8)
                    .foregroundStyle(KGColor.ink)
                    .frame(maxWidth: .infinity, minHeight: KGSize.touch)
                    .contentShape(.rect)
            }
            .buttonStyle(KGPressStyle())
            .padding(.bottom, KGSpace.large)
            KGButton(Text("Erlauben", bundle: .module), isLoading: model.isAsking) {
                Task { await model.allow() }
            }
            .accessibilityIdentifier("allowPermissions")
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 0) {
            PermissionRow(icon: .locate, tile: KGColor.location, title: Text("Standort", bundle: .module),
                          detail: Text("Haltestellen in deiner Nähe", bundle: .module), isOn: $model.wantsLocation)
            Rectangle().fill(KGColor.line).frame(height: 1).padding(.leading, 58)
            PermissionRow(icon: .bell, tile: KGColor.tileRed, title: Text("Mitteilungen", bundle: .module),
                          detail: Text("Abfahrtsalarme", bundle: .module), isOn: $model.wantsNotifications)
        }
        .background(KGColor.card, in: .kgRounded(KGRadius.large))
    }
}

/// One switch row on the grey card: 60 high, coloured tile, title and a line of explanation.
private struct PermissionRow: View {
    let icon: KGIcon
    let tile: Color
    let title: Text
    let detail: Text
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: KGSpace.medium) {
                KGIconView(icon, size: 17)
                    .foregroundStyle(KGColor.white)
                    .frame(width: KGSize.settingsIcon, height: KGSize.settingsIcon)
                    .background(tile, in: .kgRounded(KGRadius.tile))
                VStack(alignment: .leading, spacing: 0) {
                    title.kgFont(.bodyMedium.weighted(KGFont.regular)).foregroundStyle(KGColor.ink)
                    detail.kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                }
            }
        }
        .tint(KGColor.live)
        .padding(.horizontal, KGSpace.screen)
        .frame(minHeight: 60)
        .sensoryFeedback(KGHaptic.selection, trigger: isOn)
    }
}

/// An iOS-style banner: app tile, "KonstanzGo · jetzt", "Dein Bus 9A kommt in 3 Min." Slides down at 0.3 s.
private struct SampleNotification: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: KGSpace.compact) {
            SeeriLogo(size: 38)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(verbatim: "KonstanzGo").kgFont(.callout).foregroundStyle(KGColor.ink)
                    Spacer()
                    Text("jetzt", bundle: .module).kgFont(.caption.weighted(KGFont.regular))
                        .foregroundStyle(KGColor.ink2)
                }
                Text("Dein Bus 9A kommt in 3 Min.", bundle: .module)
                    .kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink)
            }
        }
        .padding(.vertical, KGSpace.medium)
        .padding(.horizontal, KGSpace.mediumLarge)
        .background(KGColor.banner, in: .kgRounded(KGRadius.cardLarge))
        .kgShadow(.tabBar, in: .kgRounded(KGRadius.cardLarge))
        .offset(y: shown || reduceMotion ? 0 : -30)
        .scaleEffect(shown ? 1 : 0.96)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(KGMotion.animation(KGMotion.pop, reduceMotion: reduceMotion)?.delay(0.05)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Beispiel-Mitteilung: Dein Bus 9A kommt in 3 Min.", bundle: .module))
    }
}

/// The blue location dot with three radar rings, two buses and a ringing bell around it.
private struct RadarScene: View {
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    ZStack {
                        ForEach(0..<3) { index in
                            let t = Self.ring(elapsed - 0.2 - Double(index) * 0.95)
                            Circle().fill(KGColor.location)
                                .frame(width: 56, height: 56)
                                .scaleEffect(1 + 2.6 * t)
                                .opacity(reduceMotion || t == 0 ? 0 : 0.35 * (1 - t))
                        }
                    }
                    .frame(width: width, height: 140)
                }
                KGIconView(.locate, size: 24)
                    .foregroundStyle(KGColor.white)
                    .frame(width: 56, height: 56)
                    .background(KGColor.location, in: .circle)
                    .overlay(Circle().strokeBorder(KGColor.white, lineWidth: 4))
                    .shadow(color: KGColor.location.opacity(0.35), radius: 9, y: 6)
                    .position(x: width / 2, y: 70)
                bubble(.bus, fill: KGColor.coral).position(x: width * 79 / 390, y: 95).popIn(after: 1.0)
                bubble(.bus, fill: KGColor.coral).position(x: width * 287 / 390, y: 35).popIn(after: 1.2)
                RingingBell().position(x: width * 303 / 390, y: 109).popIn(after: 1.4)
            }
        }
        .onAppear { start = .now }
        .accessibilityHidden(true)
    }

    private func bubble(_ icon: KGIcon, fill: Color) -> some View {
        KGIconView(icon, size: 16)
            .foregroundStyle(KGColor.white)
            .frame(width: 34, height: 34)
            .background(fill, in: .circle)
            .overlay(Circle().strokeBorder(KGColor.white, lineWidth: 3))
            .kgShadow(.floating, in: Circle())
    }

    /// k-radar: 0 … 1 over each 2.8 s, 0 before it starts.
    static func ring(_ time: Double) -> Double {
        guard time > 0 else { return 0 }
        return (time / 2.8).truncatingRemainder(dividingBy: 1)
    }
}

/// White circle with an orange bell that rings every 2.4 s (k-ring).
private struct RingingBell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = (timeline.date.timeIntervalSinceReferenceDate / 2.4).truncatingRemainder(dividingBy: 1)
            KGIconView(.bell, size: 18)
                .foregroundStyle(KGColor.warn)
                .rotationEffect(.degrees(reduceMotion ? 0 : Self.swing(t)), anchor: UnitPoint(x: 0.5, y: 0.1))
                .frame(width: 34, height: 34)
                .background(KGColor.surface, in: .circle)
                .kgShadow(.floating, in: Circle())
        }
    }

    /// 0 until 60 %, then 16°, −14°, 9°, −5°, 0.
    static func swing(_ t: Double) -> Double {
        let keys: [(Double, Double)] = [(0.6, 0), (0.66, 16), (0.74, -14), (0.82, 9), (0.9, -5), (1, 0)]
        guard t > 0.6 else { return 0 }
        for index in 1..<keys.count where t <= keys[index].0 {
            let (t0, v0) = keys[index - 1]
            let (t1, v1) = keys[index]
            return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
        }
        return 0
    }
}
