import SwiftUI

extension KGPalette {
    /// Every token with its name, for the design-system screen.
    public static let named: [(name: String, value: KGColorValue)] = [
        ("coral", coral), ("coralDeep", coralDeep), ("coralPressed", coralPressed), ("coralTint", coralTint),
        ("ink", ink), ("ink2", ink2), ("ink3", ink3), ("ink4", ink4), ("chevron", chevron),
        ("surface", surface), ("card", card), ("pressed", pressed), ("line", line), ("switchOff", switchOff),
        ("handle", handle), ("live", live), ("liveText", liveText), ("liveTint", liveTint),
        ("location", location), ("locationTint", locationTint), ("warn", warn),
        ("lineFill", lineFill), ("onLine", onLine), ("lineTint", lineTint),
    ]
}

/// The brand board as a live screen: logo, Seeri, colours, type and icons, all drawn from the tokens
/// (plan A8). Debug builds only; the components join it as they are built (Part B).
public struct DesignSystemScreen: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.xxl) {
                section("Marke") {
                    VStack(alignment: .leading, spacing: KGSpace.small) {
                        Wordmark()
                        Text(verbatim: "Dein Bus durch Konstanz").kgFont(.headline).foregroundStyle(KGColor.ink2)
                    }
                }
                section("Seeri") { SeeriGallery() }
                section("Farben") { ColorSwatches() }
                section("Schrift") { TypeSpecimen() }
                section("Icons") { IconGallery() }
            }
            .padding(.vertical, KGSpace.large)
        }
        .background(KGColor.surface)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KGSpace.medium) {
            Text(verbatim: title).kgFont(.overline).foregroundStyle(KGColor.ink2)
                .padding(.horizontal, KGSpace.screen)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// The colour swatches on their own, for snapshot tests.
public struct ColorSwatchesPreview: View {
    public init() {}
    public var body: some View { ColorSwatches().padding(.vertical, KGSpace.screen).background(KGColor.surface) }
}

/// Each colour token as a swatch with its light and dark values.
struct ColorSwatches: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: KGSpace.medium)], spacing: KGSpace.medium) {
            ForEach(KGPalette.named, id: \.name) { token in
                VStack(alignment: .leading, spacing: KGSpace.xxs) {
                    HStack(spacing: 0) {
                        Color(KGColorValue(token.value.light))
                        Color(KGColorValue(token.value.dark))
                    }
                    .frame(height: 44)
                    .clipShape(.kgRounded(KGRadius.medium))
                    .overlay(RoundedRectangle(cornerRadius: KGRadius.medium, style: .continuous)
                        .stroke(KGColor.line, lineWidth: 1))
                    Text(verbatim: token.name).kgFont(.caption).foregroundStyle(KGColor.ink)
                    Text(verbatim: Self.hex(token.value.light) + " / " + Self.hex(token.value.dark))
                        .kgFont(.caption).foregroundStyle(KGColor.ink3).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, KGSpace.screen)
    }

    static func hex(_ value: UInt32) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
}

#Preview("Design system") {
    DesignSystemScreen()
}
