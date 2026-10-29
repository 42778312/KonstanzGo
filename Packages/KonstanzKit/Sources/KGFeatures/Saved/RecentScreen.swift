import KGCore
import KGDesign
import SwiftUI

/// Screen 18 (Zuletzt): everything searched, with kind and day; swipe to delete with undo; "Alle löschen"
/// after asking (plan S16.5).
struct RecentScreen: View {
    let services: AppServices
    @State private var confirmingClear = false
    @State private var undo: RecentItem?

    private var items: [RecentItem] {
        _ = services.userVersion
        return (try? services.user?.recent()) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { services.router.back() } label: {
                    HStack(spacing: 2) {
                        KGIconView(.back, size: 22)
                        Text("Zurück", bundle: .module).kgFont(.bodyMedium)
                    }
                    .foregroundStyle(KGColor.location)
                    .frame(minHeight: KGSize.touch)
                }
                .buttonStyle(.plain)
                Spacer()
                if !items.isEmpty {
                    KGTextButton(Text("Alle löschen", bundle: .module), style: .bodyMedium) { confirmingClear = true }
                        .accessibilityIdentifier("clearRecent")
                }
            }
            .padding(.horizontal, KGSpace.medium)
            Text("Zuletzt", bundle: .module).kgFont(.display.weighted(KGFont.bold).sized(34)).foregroundStyle(KGColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KGSpace.large)
                .accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Spacer()
                KGEmptyState(.sleepy, title: Text("Noch nichts gesucht", bundle: .module),
                             message: Text("Was du suchst, erscheint hier – nur auf diesem iPhone.", bundle: .module))
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        Button { open(item.target) } label: { row(item) }
                            .listRowInsets(EdgeInsets(top: 0, leading: KGSpace.large, bottom: 0, trailing: KGSpace.large))
                            .kgSwipeToDelete { delete(item) }
                    }
                    Text("Nach links wischen zum Löschen. Dein Verlauf bleibt nur auf diesem iPhone.", bundle: .module)
                        .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink3)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .background(KGColor.surface.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let undo {
                KGToast(Text("„\(undo.target.name)“ gelöscht", bundle: .module)) {
                    services.updateUser { try $0.addRecent(undo.target, at: undo.date) }
                    withAnimation { self.undo = nil }
                }
                .padding(.bottom, KGSpace.xl)
            }
        }
        .confirmationDialog(Text("Verlauf löschen?", bundle: .module), isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                for item in items { services.updateUser { try $0.removeRecent(id: item.id) } }
            } label: { Text("Alle löschen", bundle: .module) }
        }
    }

    private func row(_ item: RecentItem) -> some View {
        HStack(spacing: KGSpace.mediumLarge) {
            KGIconView(icon(item.target), size: 18).foregroundStyle(KGColor.ink2)
                .frame(width: 40, height: 40).background(KGColor.card, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.target.name).kgFont(.bodyMedium).foregroundStyle(KGColor.ink)
                Text(verbatim: "\(kind(item.target)) · \(day(item.date))").kgFont(.footnote.weighted(KGFont.regular))
                    .foregroundStyle(KGColor.ink2)
            }
            Spacer()
        }
        .frame(minHeight: 64)
        .contentShape(.rect)
    }

    private func icon(_ target: SavedTarget) -> KGIcon {
        switch target {
        case .station: .bus
        case .place: .pin
        case .point: .pinFilled
        }
    }

    private func kind(_ target: SavedTarget) -> String {
        switch target {
        case .station: String(localized: "Haltestelle", bundle: .module)
        case .place: String(localized: "Ort", bundle: .module)
        case .point: String(localized: "Markierter Ort", bundle: .module)
        }
    }

    /// "Heute", "Gestern", "21. Okt.".
    private func day(_ date: Date) -> String {
        let calendar = Calendar.konstanz
        if calendar.isDateInToday(date) { return String(localized: "Heute", bundle: .module) }
        if calendar.isDateInYesterday(date) { return String(localized: "Gestern", bundle: .module) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func delete(_ item: RecentItem) {
        services.updateUser { try $0.removeRecent(id: item.id) }
        withAnimation(KGMotion.sheet) { undo = item }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if undo?.id == item.id { undo = nil } }
        }
    }

    private func open(_ target: SavedTarget) {
        services.openOnMap(target)
    }
}
