import SwiftUI

/// The map's search bar (B4): white, 56 high, radius 18, magnifier, "Wohin möchtest du?" in grey, Seeri's
/// logo tile on the right. The whole bar is one button that opens the search screen.
public struct KGMapSearchBar: View {
    let placeholder: Text
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = KGSize.searchBar

    public init(placeholder: Text? = nil, action: @escaping () -> Void) {
        self.placeholder = placeholder ?? Text("Wohin möchtest du?", bundle: .kgDesign)
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: KGSpace.medium) {
                KGIconView(.search, size: 22).foregroundStyle(KGColor.ink)
                placeholder.kgFont(.bodyMedium).foregroundStyle(KGColor.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                SeeriLogo(size: 38)
            }
            .padding(.leading, 18)
            .padding(.trailing, KGSpace.compact)
            .frame(minHeight: height)
            .kgGlass(in: .kgRounded(KGRadius.search))
            .kgShadow(.search, in: .kgRounded(KGRadius.search))
            .contentShape(.kgRounded(KGRadius.search))
        }
        .buttonStyle(KGPressStyle())
        .accessibilityLabel(placeholder)
        .accessibilityHint(Text("Öffnet die Suche", bundle: .kgDesign))
    }
}

/// The search screen's field (B5): grey field (40 high, radius 12) with magnifier, coral caret and a clear
/// button, then blue "Abbrechen". Takes focus when it appears.
public struct KGSearchField: View {
    @Binding var text: String
    let prompt: Text
    let onCancel: () -> Void
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 40

    public init(text: Binding<String>, prompt: Text? = nil, onCancel: @escaping () -> Void) {
        _text = text
        self.prompt = prompt ?? Text("Haltestelle, Adresse oder Ort", bundle: .kgDesign)
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: KGSpace.medium) {
            HStack(spacing: 7) {
                KGIconView(.search, size: 18).foregroundStyle(KGColor.ink3)
                TextField(text: $text, prompt: prompt.foregroundStyle(KGColor.ink3)) { prompt }
                    .kgFont(.bodyMedium.weighted(KGFont.regular))
                    .foregroundStyle(KGColor.ink)
                    .tint(KGColor.coral)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        KGIconView(.close, size: 10)
                            .foregroundStyle(KGColor.white)
                            .frame(width: 18, height: 18)
                            .background(KGColor.clearButton, in: .circle)
                            .frame(width: KGSize.touch, height: KGSize.touch)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -13)
                    .accessibilityLabel(Text("Eingabe löschen", bundle: .kgDesign))
                }
            }
            .padding(.horizontal, KGSpace.compact)
            .frame(minHeight: height)
            .kgGlassCard(in: .kgRounded(KGRadius.medium))
            KGTextButton(Text("Abbrechen", bundle: .kgDesign), style: .bodyMedium.weighted(KGFont.regular),
                         action: onCancel)
        }
        .onAppear { focused = true }
    }
}

#Preview("Search") {
    @Previewable @State var text = "Uni"
    VStack(spacing: 20) {
        KGMapSearchBar {}
        KGSearchField(text: $text) {}
    }
    .padding()
    .background(KGColor.mapLand)
}
