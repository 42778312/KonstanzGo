import SwiftUI

/// One choice in a glass menu.
public struct KGGlassMenuItem {
    let title: Text
    let icon: KGIcon?
    let isSelected: Bool
    let isDestructive: Bool
    let action: () -> Void

    public init(_ title: Text, icon: KGIcon? = nil, isSelected: Bool = false, isDestructive: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isDestructive = isDestructive
        self.action = action
    }
}

extension View {
    /// Every menu and dropdown in the app: the app's glass, beside the view it opens from. iOS's own menus and dialogs
    /// can't be restyled, so the app uses this instead. A tap outside closes it, so it needs no Cancel row.
    public func kgGlassMenu(isPresented: Binding<Bool>, title: Text? = nil, message: Text? = nil,
                            items: [KGGlassMenuItem]) -> some View {
        popover(isPresented: isPresented) {
            KGGlassMenuPanel(title: title, message: message, items: items) { isPresented.wrappedValue = false }
                // On the content, not `presentationBackground`: that one also repaints the sheet the menu opens from.
                .background { KGGlassBackdrop().ignoresSafeArea() }
                .presentationCompactAdaptation(.popover)
        }
    }
}

private enum KGMenuStyle {
    static let width: CGFloat = 270
    static let divider = KGColor.line
}

private struct KGGlassMenuPanel: View {
    let title: Text?
    let message: Text?
    let items: [KGGlassMenuItem]
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if title != nil || message != nil {
                header
                Rectangle().fill(KGMenuStyle.divider).frame(height: 0.5)
            }
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(KGMenuStyle.divider).frame(height: 0.5).padding(.leading, KGSpace.medium)
                }
                row(items[index])
            }
        }
        .frame(width: KGMenuStyle.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        VStack(spacing: KGSpace.xxs) {
            title?.kgFont(.callout.weighted(KGFont.semiBold)).foregroundStyle(KGColor.ink)
                .accessibilityAddTraits(.isHeader)
            message?.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, KGSpace.medium)
        .padding(.vertical, KGSpace.mediumLarge)
    }

    private func row(_ item: KGGlassMenuItem) -> some View {
        Button {
            close()
            item.action()
        } label: {
            HStack(spacing: KGSpace.small) {
                if let icon = item.icon { KGIconView(icon, size: 18) }
                item.title.kgFont(.bodyMedium)
                Spacer(minLength: KGSpace.small)
                if item.isSelected { KGIconView(.check, size: 18).foregroundStyle(KGColor.location) }
            }
            .foregroundStyle(item.isDestructive ? KGColor.tileRed : KGColor.ink)
            .padding(.horizontal, KGSpace.medium)
            .frame(minHeight: KGSize.touch + 4)
            .contentShape(.rect)
        }
        .buttonStyle(KGRowPressStyle())
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }
}
