import KGCore
import KGDesign
import SwiftUI

/// Picks a new start or target on screen 10: "Mein Standort", Zuhause / Arbeit / Uni when set, recent
/// searches, or anything found by typing (stops, places, streets, addresses).
struct EndpointPicker: View {
    let services: AppServices
    let title: Text
    let onPick: (Endpoint) -> Void
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title.kgFont(.title).foregroundStyle(KGColor.ink)
                .padding(.horizontal, KGSpace.large)
                .padding(.top, KGSpace.large)
                .accessibilityAddTraits(.isHeader)
            KGSearchField(text: $query) { dismiss() }
                .padding(.horizontal, KGSpace.screen)
                .padding(.top, KGSpace.medium)
                .accessibilityIdentifier("endpointField")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestions
                    } else if results.isEmpty {
                        KGEmptyState(.focused, title: Text("Nichts gefunden für „\(query)“", bundle: .module),
                                     message: Text("Versuch es mit einer Haltestelle, einer Straße oder einem Ort.",
                                                   bundle: .module))
                            .padding(.top, KGSpace.xxl)
                    } else {
                        ForEach(results) { result in
                            Button {
                                pick(Endpoint(name: result.name, coordinate: result.coordinate))
                            } label: {
                                ResultRow(result: result, query: query)
                            }
                            .buttonStyle(KGRowPressStyle())
                        }
                    }
                }
                .padding(.bottom, KGSpace.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(KGRadius.card)
        .presentationBackground(.thinMaterial)
        .onChange(of: query) { _, text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            results = trimmed.isEmpty ? [] : Array(services.transit.search(trimmed, near: services.anchor).prefix(25))
        }
    }

    @ViewBuilder private var suggestions: some View {
        if let here = services.here {
            row(icon: .locate, tint: KGColor.location, background: KGColor.locationTint,
                title: Text("Mein Standort", bundle: .module), subtitle: nil) { pick(here) }
                .accessibilityIdentifier("pickHere")
        }
        let slots: [(Favorite.Slot, KGIcon, Text)] = [
            (.home, .home, Text("Zuhause", bundle: .module)),
            (.work, .work, Text("Arbeit", bundle: .module)),
            (.uni, .uniCap, Text("Uni", bundle: .module)),
        ]
        ForEach(slots, id: \.0) { slot, icon, name in
            if let favorite = { _ = services.userVersion; return try? services.user?.slot(slot) }() {
                row(icon: icon, tint: KGColor.ink2, background: KGColor.card, title: name,
                    subtitle: Text(verbatim: favorite.target.name)) {
                    pick(Endpoint(name: favorite.displayName, coordinate: favorite.target.coordinate))
                }
            }
        }
        let recent = { _ = services.userVersion; return (try? services.user?.recent()) ?? [] }()
        if !recent.isEmpty {
            KGSectionHeader(Text("Zuletzt", bundle: .module))
                .padding(.horizontal, KGSpace.large).padding(.top, KGSpace.large).padding(.bottom, KGSpace.xs)
            ForEach(recent.prefix(8)) { item in
                row(icon: .history, tint: KGColor.ink2, background: KGColor.card,
                    title: Text(verbatim: item.target.name), subtitle: nil) {
                    pick(Endpoint(name: item.target.name, coordinate: item.target.coordinate))
                }
            }
        }
    }

    private func row(icon: KGIcon, tint: Color, background: Color, title: Text, subtitle: Text?,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KGSpace.medium) {
                KGIconView(icon, size: 20).foregroundStyle(tint)
                    .frame(width: 40, height: 40).background(background, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    title.kgFont(.bodyMedium).foregroundStyle(KGColor.ink)
                    if let subtitle {
                        subtitle.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(KGColor.line).frame(height: 1) }
            }
            .padding(.horizontal, KGSpace.large)
            .contentShape(.rect)
        }
        .buttonStyle(KGRowPressStyle())
    }

    private func pick(_ endpoint: Endpoint) {
        onPick(endpoint)
        dismiss()
    }
}
