import SwiftUI

/// The design's buttons (plan B1–B3). Measured from the artboards:
/// - primary: coral, 52 high, radius 8, 19 Bold white ("Los geht's", "Route hierher"). White on coral is
///   3.3:1, enough for 19 pt Bold (large text), so the design's colour stays.
/// - secondary: white with a 1 pt line and the card shadow, 52 high, radius 8, 16 SemiBold ("Neue Suche").
/// - outline: white with a 1.5 pt black border, 46 high, radius 14, 15 ExtraBold, icon in front ("Merken").
public enum KGButtonKind: Sendable {
    case primary, secondary, outline
}

/// Pressed: 0.85 opacity and scale 0.98 (B1). Disabled: 40 % opacity. Loading: a spinner in place of the
/// label at the same width, and taps are ignored.
public struct KGButtonStyle: ButtonStyle {
    let kind: KGButtonKind
    let isLoading: Bool
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var bigHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var outlineHeight: CGFloat = 46

    public init(_ kind: KGButtonKind, isLoading: Bool = false) {
        self.kind = kind
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: kind == .outline ? KGRadius.large : KGRadius.small,
                                     style: .continuous)
        configuration.label
            .kgFont(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .opacity(isLoading ? 0 : 1)
            .overlay { if isLoading { ProgressView().tint(foreground) } }
            // Outline buttons sit three in a row ("Zuhause · Arbeit · Uni"), so they keep less space at the sides.
            .padding(.horizontal, kind == .outline ? KGSpace.small : KGSpace.screen)
            .frame(maxWidth: .infinity, minHeight: kind == .outline ? outlineHeight : bigHeight)
            .background(background, in: shape)
            .overlay { border(shape) }
            .modifier(SecondaryShadow(active: kind == .secondary, shape: shape))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var font: KGTextStyle {
        switch kind {
        case .primary: .primaryButton
        case .secondary: .bodyStrong.weighted(KGFont.semiBold).sized(16)
        case .outline: .callout.weighted(KGFont.extraBold)
        }
    }

    private var foreground: Color { kind == .primary ? KGColor.white : KGColor.ink }

    private var background: Color {
        switch kind {
        case .primary: KGColor.coral
        case .secondary, .outline: KGColor.surface
        }
    }

    @ViewBuilder private func border(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .primary: EmptyView()
        case .secondary: shape.stroke(KGColor.line, lineWidth: 1)
        case .outline: shape.stroke(KGColor.ink, lineWidth: 1.5)
        }
    }
}

private struct SecondaryShadow<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S

    func body(content: Content) -> some View {
        if active { content.kgShadow(.card, in: shape) } else { content }
    }
}

extension KGTextStyle {
    /// 19 Bold: the big coral buttons.
    public static let primaryButton = KGTextStyle(fontName: KGFont.bold, size: 19, relativeTo: .headline)

    /// The same style in another weight.
    public func weighted(_ fontName: String) -> KGTextStyle {
        var copy = self
        copy.fontName = fontName
        return copy
    }
}

/// A full-width button with an optional icon in front: `KGButton("Route hierher", kind: .primary) { … }`.
public struct KGButton: View {
    let title: Text
    let icon: KGIcon?
    let kind: KGButtonKind
    let isLoading: Bool
    let action: () -> Void

    public init(_ title: Text, icon: KGIcon? = nil, kind: KGButtonKind = .primary, isLoading: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            if !isLoading { action() }
        } label: {
            HStack(spacing: KGSpace.xs) {
                if let icon { KGIconView(icon, size: kind == .outline ? 18 : 20) }
                title
            }
        }
        .buttonStyle(KGButtonStyle(kind, isLoading: isLoading))
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }
}

/// Blue text button ("Alle", "Abbrechen", "Offline-Daten ›"), 15 SemiBold, hit area at least 44 pt.
public struct KGTextButton: View {
    let title: Text
    let style: KGTextStyle
    let action: () -> Void

    public init(_ title: Text, style: KGTextStyle = .callout, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            title.kgFont(style).foregroundStyle(KGColor.location)
                .frame(minHeight: KGSize.touch)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A round (or rounded-square) icon button: white with the floating shadow over the map, card fill on plain
/// surfaces (B3). The label is required, because the icon alone says nothing to VoiceOver.
public struct KGRoundIconButton: View {
    public enum Surface: Sendable {
        /// 44 pt white circle with shadow (back / favourite over a map).
        case map
        /// 44 pt card-grey circle (swap in the route card, close in sheets).
        case plain
        /// 48 pt white rounded square, radius 14 (layers, my location).
        case mapSquare
    }

    let icon: KGIcon
    let label: Text
    let surface: Surface
    let tint: Color
    let action: () -> Void

    public init(_ icon: KGIcon, label: Text, surface: Surface = .map, tint: Color = KGColor.ink,
                action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.surface = surface
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            KGIconView(icon, size: surface == .mapSquare ? 22 : 20)
                .foregroundStyle(tint)
                .frame(width: side, height: side)
                .background(fill, in: shape)
                .modifier(FloatingShadow(active: surface != .plain, shape: shape))
                .contentShape(shape)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityLabel(label)
    }

    private var side: CGFloat { surface == .mapSquare ? KGSize.mapButton : KGSize.touch }
    private var fill: Color { surface == .plain ? KGColor.card : KGColor.surface }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: surface == .mapSquare ? KGRadius.large : side / 2, style: .continuous)
    }
}

private struct FloatingShadow<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S

    func body(content: Content) -> some View {
        if active { content.kgShadow(.floating, in: shape) } else { content }
    }
}

/// Plain press feedback for custom-drawn buttons: 0.85 opacity and scale 0.96.
public struct KGPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A filter chip (screen 10 "Jetzt · Später · Barrierefrei"): 36 high capsule, 15 SemiBold; black when on.
public struct KGChip: View {
    let title: Text
    let icon: KGIcon?
    let isOn: Bool
    let action: () -> Void

    public init(_ title: Text, icon: KGIcon? = nil, isOn: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: KGSpace.xs) {
                if let icon { KGIconView(icon, size: 16) }
                title.kgFont(.callout)
            }
            .foregroundStyle(isOn ? KGColor.surface : KGColor.ink)
            .padding(.horizontal, icon == nil ? KGSpace.screen : KGSpace.medium)
            .frame(minHeight: 36)
            .background(isOn ? KGColor.ink : KGColor.surface, in: .capsule)
            .frame(minHeight: KGSize.touch)
            .contentShape(.capsule)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        KGButton(Text(verbatim: "Los geht's")) {}
        KGButton(Text(verbatim: "Alarm stellen"), icon: .bell) {}
        KGButton(Text(verbatim: "Suchen"), isLoading: true) {}
        KGButton(Text(verbatim: "Neue Suche"), kind: .secondary) {}
        HStack {
            KGButton(Text(verbatim: "Merken"), icon: .star, kind: .outline) {}
            KGButton(Text(verbatim: "Teilen"), icon: .share, kind: .outline) {}
        }
        KGButton(Text(verbatim: "Deaktiviert")) {}.disabled(true)
        HStack {
            KGChip(Text(verbatim: "Jetzt"), isOn: true) {}
            KGChip(Text(verbatim: "Später")) {}
            KGChip(Text(verbatim: "Barrierefrei"), icon: .accessibility) {}
        }
        HStack {
            KGRoundIconButton(.back, label: Text(verbatim: "Zurück")) {}
            KGRoundIconButton(.swap, label: Text(verbatim: "Tauschen"), surface: .plain) {}
            KGRoundIconButton(.layers, label: Text(verbatim: "Kartenebenen"), surface: .mapSquare) {}
            KGTextButton(Text(verbatim: "Alle")) {}
        }
    }
    .padding(20)
    .background(KGColor.card)
}
