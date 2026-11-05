import SwiftUI

/// A segmented control as the design draws it (B13): grey track, white thumb with a soft shadow that slides
/// to the chosen segment. `small` is the stop screen's "Abfahrten | Linien" (36 high, 14 SemiBold), `large`
/// the "Jetzt | Abfahrt | Ankunft" of screen 19 (42 high, 15 ExtraBold).
public struct KGSegmentedControl<Value: Hashable>: View {
    public enum Size: Sendable { case small, large }

    @Binding var selection: Value
    let options: [(value: Value, title: Text)]
    let size: Size
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Value>, options: [(value: Value, title: Text)], size: Size = .small) {
        _selection = selection
        self.options = options
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(KGMotion.animation(KGMotion.slide, reduceMotion: reduceMotion)) {
                        selection = option.value
                    }
                } label: {
                    option.title
                        .kgFont(size == .small ? .footnote : .callout.weighted(KGFont.extraBold))
                        .foregroundStyle(KGColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: (size == .small ? 36 : 42) - 2 * inset)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: thumbRadius, style: .continuous)
                                    .fill(KGColor.pressed)
                                    .shadow(color: .black.opacity(0.12), radius: size == .small ? 2 : 3,
                                            y: size == .small ? 1 : 2)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(inset)
        .background(KGColor.glassFill, in: .kgRounded(size == .small ? KGRadius.compact : KGRadius.medium))
        .frame(minHeight: KGSize.touch)
        .sensoryFeedback(KGHaptic.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    private var inset: CGFloat { size == .small ? 2 : 3 }
    private var thumbRadius: CGFloat { size == .small ? KGRadius.small : 9 }
}

extension KGRadius {
    /// The small segmented control's track.
    public static let compact: CGFloat = 10
    /// Settings icon tiles.
    public static let tile: CGFloat = 7
    /// Option cards ("Schnellste"), the pin screen's stop row.
    public static let option: CGFloat = 16
    /// Departure-details and trip cards.
    public static let cardLarge: CGFloat = 22
}

/// A label and a switch as one control (B14). The switch is the system one, tinted the design's green.
public struct KGToggleRow: View {
    let title: Text
    let subtitle: Text?
    @Binding var isOn: Bool
    let strong: Bool

    /// `strong` is the 16 ExtraBold label of screen 19; the default is the 17 Regular settings label.
    public init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>, strong: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
        self.strong = strong
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                title.kgFont(strong ? .body.weighted(KGFont.extraBold) : .bodyMedium.weighted(KGFont.regular))
                    .foregroundStyle(KGColor.ink)
                if let subtitle { subtitle.kgFont(.caption).foregroundStyle(KGColor.ink2) }
            }
        }
        .tint(KGColor.live)
        .frame(minHeight: 52)
        .sensoryFeedback(KGHaptic.selection, trigger: isOn)
    }
}

/// One row of a settings group (B15): coloured 30 pt icon tile (radius 7), title 17, grey value, chevron.
/// Pass `isOn` for a switch instead of a value and chevron.
public struct KGSettingsRow: View {
    let icon: KGIcon
    let tile: Color
    let title: Text
    let value: Text?
    let isOn: Binding<Bool>?
    let action: (() -> Void)?

    public init(_ title: Text, icon: KGIcon, tile: Color, value: Text? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.tile = tile
        self.value = value
        isOn = nil
        self.action = action
    }

    public init(_ title: Text, icon: KGIcon, tile: Color, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self.tile = tile
        value = nil
        self.isOn = isOn
        action = nil
    }

    public var body: some View {
        if let isOn {
            Toggle(isOn: isOn) { label }
                .tint(KGColor.live)
                .padding(.horizontal, KGSpace.screen)
                .frame(minHeight: 52)
        } else if let action {
            Button(action: action) { navigationRow }
                .buttonStyle(KGRowPressStyle())
        } else {
            navigationRow
        }
    }

    private var label: some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(icon, size: 17)
                .foregroundStyle(KGColor.white)
                .frame(width: KGSize.settingsIcon, height: KGSize.settingsIcon)
                .background(tile, in: .kgRounded(KGRadius.tile))
            title.kgFont(.bodyMedium.weighted(KGFont.regular)).foregroundStyle(KGColor.ink)
        }
    }

    private var navigationRow: some View {
        HStack(spacing: KGSpace.medium) {
            label
            Spacer(minLength: KGSpace.small)
            if let value {
                value.kgFont(.bodyMedium.weighted(KGFont.regular)).foregroundStyle(KGColor.ink3).lineLimit(1)
            }
            if action != nil {
                KGIconView(.chevronRight, size: 14).foregroundStyle(KGColor.chevron)
            }
        }
        .padding(.horizontal, KGSpace.screen)
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Rows highlight in the `pressed` grey while touched, like iOS lists.
public struct KGRowPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? KGColor.pressed : .clear)
    }
}

/// A white rounded group of rows with hairlines inset past the icon tiles (B15, screen 13).
public struct KGSettingsGroup<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(KGColor.line).frame(height: 1)
                            .padding(.leading, KGSpace.screen + KGSize.settingsIcon + KGSpace.medium)
                    }
                    rows[index]
                }
            }
        }
        .background(KGColor.glassFill)
        .clipShape(.kgRounded(KGRadius.large))
    }
}

/// A section header ("ERGEBNISSE", "BEVORZUGEN"): overline style in `ink2`, marked as a header (B16).
public struct KGSectionHeader: View {
    let title: Text

    public init(_ title: Text) {
        self.title = title
    }

    public var body: some View {
        title.kgFont(.overline).foregroundStyle(KGColor.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One choice of a set (screen 19 "BEVORZUGEN"): 58 high card, radius 16; chosen = black 2 pt border, grey
/// fill and a black check that pops in.
public struct KGOptionCard: View {
    let title: Text
    let subtitle: Text?
    let icon: KGIcon?
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: Text, subtitle: Text? = nil, icon: KGIcon? = nil, isSelected: Bool,
                action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: KGSpace.medium) {
                if let icon { KGIconView(icon, size: 22).foregroundStyle(KGColor.ink) }
                VStack(alignment: .leading, spacing: 0) {
                    title.kgFont(.body.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink)
                    if let subtitle { subtitle.kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    KGIconView(.check, size: 13)
                        .foregroundStyle(KGColor.surface)
                        .frame(width: 24, height: 24)
                        .background(KGColor.ink, in: .circle)
                        .transition(.scale(scale: KGMotion.popStart).combined(with: .opacity))
                }
            }
            .padding(.horizontal, KGSpace.mediumLarge)
            .frame(minHeight: 58)
            .background(isSelected ? KGColor.pressed : KGColor.glassFill, in: .kgRounded(KGRadius.option))
            .overlay {
                RoundedRectangle(cornerRadius: KGRadius.option, style: .continuous)
                    .strokeBorder(isSelected ? KGColor.ink : KGColor.line, lineWidth: 2)
            }
            .contentShape(.kgRounded(KGRadius.option))
            .animation(KGMotion.pop, value: isSelected)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .sensoryFeedback(KGHaptic.selection, trigger: isSelected) { _, new in new }
    }
}

/// Onboarding progress (B19, screens 03–05): a 16 pt grey capsule with a coral fill and a light stripe on
/// top, which springs to the new length. The design draws a bar here, not dots.
public struct KGStepProgress: View {
    let step: Int
    let count: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(step: Int, of count: Int) {
        self.step = step
        self.count = count
    }

    public var body: some View {
        GeometryReader { proxy in
            let total = max(count, 1)
            let fraction = CGFloat(min(max(step, 0), total)) / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule().fill(KGColor.line)
                Capsule().fill(KGColor.coral)
                    .overlay(alignment: .top) {
                        Capsule().fill(KGColor.white.opacity(0.35))
                            .frame(height: 4)
                            .padding(.horizontal, 7)
                            .padding(.top, 3)
                    }
                    .frame(width: max(16, proxy.size.width * (shown ? fraction : 0)))
            }
        }
        .frame(height: 16)
        .onAppear {
            withAnimation(KGMotion.animation(KGMotion.progress, reduceMotion: reduceMotion)?.delay(0.2)) {
                shown = true
            }
        }
        .animation(KGMotion.animation(KGMotion.progress, reduceMotion: reduceMotion), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text("Schritt \(step) von \(count)", bundle: .kgDesign))
    }
}

extension KGMotion {
    /// k-prog: the progress bars' springy fill, cubic-bezier(.3, 1.4, .5, 1), 0.8 s.
    public static let progress = Animation.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.8)
}

#Preview("Controls") {
    @Previewable @State var tab = 0
    @Previewable @State var mode = "now"
    @Previewable @State var isOn = true
    @Previewable @State var pick = 0
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            KGSegmentedControl(selection: $tab, options: [(0, Text(verbatim: "Abfahrten")),
                                                          (1, Text(verbatim: "Linien"))])
            KGSegmentedControl(selection: $mode, options: [("now", Text(verbatim: "Jetzt")),
                                                           ("dep", Text(verbatim: "Abfahrt")),
                                                           ("arr", Text(verbatim: "Ankunft"))], size: .large)
            KGStepProgress(step: 2, of: 4)
            KGSectionHeader(Text(verbatim: "Bevorzugen"))
            KGOptionCard(Text(verbatim: "Schnellste"), subtitle: Text(verbatim: "Früheste Ankunft"),
                         isSelected: pick == 0) { pick = 0 }
            KGOptionCard(Text(verbatim: "Wenig laufen"), subtitle: Text(verbatim: "Kürzere Fußwege"),
                         isSelected: pick == 1) { pick = 1 }
            KGToggleRow(Text(verbatim: "Barrierefrei"), isOn: $isOn, strong: true)
            KGSettingsGroup {
                KGSettingsRow(Text(verbatim: "Mitteilungen"), icon: .bell, tile: KGColor.tileRed, isOn: $isOn)
                KGSettingsRow(Text(verbatim: "Abfahrtsalarm"), icon: .timer, tile: KGColor.warn,
                              value: Text(verbatim: "2 Min. vorher")) {}
                KGSettingsRow(Text(verbatim: "Datenschutz"), icon: .shield, tile: KGColor.live) {}
            }
        }
        .padding()
    }
    .background(KGColor.card)
}
