import SwiftUI

/// "Konstanz" with "Go" in a tag: the name as the brand board draws it. ExtraBold, −2 % letter-spacing.
/// On light backgrounds the tag is coral with white text (brand board, 54 pt); on coral the word is white and
/// the tag white with deep-red text (start screen 01, 44 pt).
public struct Wordmark: View {
    public enum Background: Sendable { case light, coral }

    let size: CGFloat
    let background: Background

    public init(size: CGFloat = 54, on background: Background = .light) {
        self.size = size
        self.background = background
    }

    public var body: some View {
        let style = KGTextStyle(fontName: KGFont.extraBold, size: size, relativeTo: .largeTitle)
        // The brand board's tag at 54 pt: padding 3 / 12 / 7, radius 16 (scaled with the size).
        let scale = size / 54
        HStack(spacing: 4 * scale) {
            Text(verbatim: "Konstanz")
                .foregroundStyle(background == .coral ? KGColor.white : KGColor.ink)
            Text(verbatim: "Go")
                .foregroundStyle(background == .coral ? Color(KGColorValue(0xC4363F)) : KGColor.white)
                .padding(.top, 3 * scale)
                .padding(.horizontal, 12 * scale)
                .padding(.bottom, 7 * scale)
                .background(background == .coral ? KGColor.white : KGColor.coral, in: .kgRounded(16 * scale))
        }
        .font(style.font)
        .tracking(-0.02 * size)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "KonstanzGo"))
    }
}

#Preview("Wordmark") {
    VStack(spacing: 24) {
        Wordmark()
        Wordmark(size: 44, on: .coral).padding().background(KGColor.coral)
    }
}
