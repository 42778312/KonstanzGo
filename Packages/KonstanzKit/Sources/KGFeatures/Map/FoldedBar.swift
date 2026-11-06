import KGDesign
import SwiftUI

/// A sheet folded down after a tap on the map (Apple Maps' "Directions" bar): the stop's, place's or route's
/// name, maybe a line under it, and ✕. Tapping the name opens the sheet again.
struct FoldedBar: View {
    let title: String
    var subtitle: Text?
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: KGSpace.compact) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).kgFont(.title).foregroundStyle(KGColor.ink).lineLimit(1)
                    subtitle?.kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Öffnet die Liste wieder", bundle: .module))
            .accessibilityIdentifier("foldedBar")
            Button(action: onClose) {
                KGIconView(.close, size: 16).foregroundStyle(KGColor.ink)
                    .frame(width: 40, height: 40)
                    .kgGlassCard(in: .circle)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Schließen", bundle: .module))
            .accessibilityIdentifier("closeFolded")
        }
        .padding(.leading, KGSpace.large)
        .padding(.trailing, KGSpace.medium)
    }
}

/// The map's stop and place sheets: half the screen with the map usable above, pulled up to full height, or
/// folded to a bar with the name when the map is tapped.
struct FoldingSheet<Content: View>: View {
    static var folded: PresentationDetent { .height(84) }
    static var half: PresentationDetent { .fraction(0.5) }

    @Binding var detent: PresentationDetent
    let title: String
    var subtitle: Text?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if detent == Self.folded {
                FoldedBar(title: title, subtitle: subtitle, onOpen: { detent = Self.half }, onClose: onClose)
                    .frame(maxHeight: .infinity)
            } else {
                content
            }
        }
        .presentationDetents([Self.folded, Self.half, .large], selection: $detent)
        // Swiping down rests on the folded bar (Apple Maps); ✕ closes.
        .interactiveDismissDisabled()
        .kgGlassSheet()
        .presentationDragIndicator(detent == Self.folded ? .hidden : .visible)
    }
}
