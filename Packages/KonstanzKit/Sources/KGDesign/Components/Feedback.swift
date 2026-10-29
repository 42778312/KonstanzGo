import SwiftUI

/// Seeri with a title, a line of text, an optional hint tag and buttons (B23; screen 23 "Keine Verbindung
/// gefunden", empty lists, no search results).
public struct KGEmptyState<Actions: View>: View {
    let expression: Seeri.Expression
    let title: Text
    let message: Text
    let hint: Text?
    let actions: Actions

    public init(_ expression: Seeri.Expression, title: Text, message: Text, hint: Text? = nil,
                @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.expression = expression
        self.title = title
        self.message = message
        self.hint = hint
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 0) {
            SeeriAlive(expression)
                .frame(width: 120, height: 120)
                .kgRiseIn()
            title
                .kgFont(.titleL.weighted(KGFont.bold).sized(26))
                .foregroundStyle(KGColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, KGSpace.compact)
                .accessibilityAddTraits(.isHeader)
                .kgRiseIn(index: 1)
            message
                .kgFont(.body)
                .lineSpacing(5)
                .foregroundStyle(KGColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, KGSpace.xs)
                .kgRiseIn(index: 2)
            if let hint {
                HStack(spacing: KGSpace.xs) {
                    KGIconView(.clock, size: 16)
                    hint.kgFont(.footnote.weighted(KGFont.extraBold))
                }
                .foregroundStyle(KGColor.lineText)
                .padding(.horizontal, KGSpace.mediumLarge)
                .frame(minHeight: 34)
                .background(KGColor.lineTint, in: .capsule)
                .padding(.top, KGSpace.mediumLarge)
                .kgRiseIn(index: 3)
            }
            VStack(spacing: KGSpace.medium) { actions }
                .padding(.top, KGSpace.xl)
        }
        .padding(.horizontal, KGSpace.xl)
    }
}

/// Seeri's speech bubble (B24): white with a hairline, pops in from its tail. `large` is the welcome
/// bubble (19 SemiBold, tail below the middle); `side` speaks from Seeri on its left (onboarding 03–05,
/// tail on the left edge); `small` is the map callout (13 ExtraBold, no tail).
public struct KGSpeechBubble: View {
    public enum Size: Sendable { case large, side, small }

    let text: Text
    let size: Size
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: Text, size: Size = .large) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        text
            .kgFont(size == .small ? .caption.weighted(KGFont.extraBold) : .headline.weighted(KGFont.semiBold))
            .lineSpacing(size == .small ? 0 : 5)
            .multilineTextAlignment(size == .large ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(KGColor.ink)
            .padding(.vertical, padding.height)
            .padding(.horizontal, padding.width)
            .background(KGColor.surface, in: .kgRounded(radius))
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(KGColor.line, lineWidth: 1) }
            .overlay(alignment: size == .side ? .leading : .bottom) { tail }
            .scaleEffect(shown ? 1 : 0.7, anchor: anchor)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(KGMotion.animation(KGMotion.pop, reduceMotion: reduceMotion)) { shown = true }
            }
    }

    private var radius: CGFloat {
        switch size {
        case .large: KGRadius.card
        case .side: 18
        case .small: KGRadius.large
        }
    }

    private var padding: CGSize {
        switch size {
        case .large: CGSize(width: KGSpace.large, height: KGSpace.screen)
        case .side: CGSize(width: KGSpace.screen, height: KGSpace.mediumLarge)
        case .small: CGSize(width: KGSpace.medium, height: KGSpace.small)
        }
    }

    private var anchor: UnitPoint {
        switch size {
        case .large: .bottom
        case .side: .leading
        case .small: .bottomLeading
        }
    }

    @ViewBuilder private var tail: some View {
        switch size {
        case .large:
            Tail().fill(KGColor.surface)
                .overlay(Tail().stroke(KGColor.line, lineWidth: 1))
                .frame(width: 22, height: 10)
                .offset(y: 9.5)
        case .side:
            Tail().fill(KGColor.surface)
                .overlay(Tail().stroke(KGColor.line, lineWidth: 1))
                .frame(width: 22, height: 10)
                .rotationEffect(.degrees(90))
                .offset(x: -15.5)
        case .small:
            EmptyView()
        }
    }

    /// The little triangle under the bubble, open at the top so it joins the bubble.
    private struct Tail: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
        }
    }
}

/// A short message at the bottom (B25): black capsule, white text, optional "Rückgängig". Announced to
/// VoiceOver. The screen decides when it hides (about 4 s).
public struct KGToast: View {
    let message: Text
    let undo: (() -> Void)?

    public init(_ message: Text, undo: (() -> Void)? = nil) {
        self.message = message
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: KGSpace.medium) {
            message.kgFont(.callout).foregroundStyle(KGColor.surface)
            if let undo {
                Button(action: undo) {
                    Text("Rückgängig", bundle: .kgDesign)
                        .kgFont(.callout.weighted(KGFont.extraBold))
                        .foregroundStyle(KGColor.lineFill)
                        .frame(minHeight: KGSize.touch)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, KGSpace.large)
        .padding(.trailing, undo == nil ? KGSpace.large : KGSpace.screen)
        .frame(minHeight: 48)
        .background(KGColor.ink, in: .capsule)
        .kgShadow(.floating, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Swipe left to delete (B26, screen 18): the native swipe action in coral with "Löschen", a warning haptic,
    /// and the same as a VoiceOver action.
    public func kgSwipeToDelete(_ action: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(action: action))
    }
}

private struct SwipeToDelete: ViewModifier {
    let action: () -> Void
    @State private var deleted = 0

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleted += 1
                    action()
                } label: {
                    Label { Text("Löschen", bundle: .kgDesign) } icon: { Image(systemName: "trash") }
                }
                .tint(KGColor.coral)
            }
            .accessibilityAction(named: Text("Löschen", bundle: .kgDesign)) {
                deleted += 1
                action()
            }
            .sensoryFeedback(KGHaptic.warning, trigger: deleted)
    }
}

#Preview("Feedback") {
    VStack(spacing: 24) {
        KGSpeechBubble(Text(verbatim: "Hallo, ich bin Seeri und bring dich durch ganz Konstanz."))
        KGSpeechBubble(Text(verbatim: "Ich warte an Steig D"), size: .small)
        KGToast(Text(verbatim: "Gelöscht")) {}
        KGEmptyState(.sleepy, title: Text(verbatim: "Keine Verbindung gefunden"),
                     message: Text(verbatim: "Um 01:30 fährt leider kein Bus zur Insel Mainau."),
                     hint: Text(verbatim: "Erster Bus 05:42")) {
            KGButton(Text(verbatim: "Andere Zeit wählen")) {}
        }
    }
    .padding()
    .background(KGColor.card)
}
