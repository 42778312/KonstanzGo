import KGCore
import KGDesign
import SwiftUI

/// Screen 08 (Suche): the field with focus, quick chips for Zuhause / Arbeit / Uni, results while typing
/// (stops with their lines, places, streets) with the typed part in bold, recent searches when empty, and the
/// long-press tip (plan S5).
struct SearchScreen: View {
    let services: AppServices
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var toast: Text?

    var body: some View {
        VStack(spacing: 0) {
            KGSearchField(text: $query) { services.router.back() }
                .padding(.horizontal, KGSpace.screen)
                .padding(.top, KGSpace.small)
                .accessibilityIdentifier("searchField")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        QuickChips(services: services, onPick: open)
                            .padding(.horizontal, KGSpace.screen)
                            .padding(.top, KGSpace.screen)
                        recent
                        // Part of the list, so it never covers the recent searches when the keyboard is up.
                        TipCard().padding(.horizontal, KGSpace.screen).padding(.top, KGSpace.xl)
                    } else if results.isEmpty {
                        KGEmptyState(.focused, title: Text("Nichts gefunden für „\(query)“", bundle: .module),
                                     message: Text("Versuch es mit einer Haltestelle, einer Straße oder einem Ort.",
                                                   bundle: .module))
                            .padding(.top, 40)
                    } else {
                        header(Text("Ergebnisse", bundle: .module))
                        ForEach(results) { result in
                            ResultRow(result: result, query: query)
                                .onTapGesture { open(result) }
                                .onLongPressGesture { save(result) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction(named: Text("Merken", bundle: .module)) { save(result) }
                        }
                    }
                }
                .padding(.bottom, KGSpace.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(KGGlassBackdrop().ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast {
                KGToast(toast).padding(.bottom, KGSpace.xl)
            }
        }
        .sensoryFeedback(KGHaptic.success, trigger: toast != nil) { _, shown in shown }
        .onChange(of: query) { _, text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            results = trimmed.isEmpty ? [] : Array(services.transit.search(trimmed, near: services.anchor).prefix(25))
        }
    }

    private func header(_ title: Text) -> some View {
        KGSectionHeader(title)
            .padding(.horizontal, KGSpace.large)
            .padding(.top, KGSpace.xl)
            .padding(.bottom, KGSpace.xs)
    }

    @ViewBuilder private var recent: some View {
        let items = { _ = services.userVersion; return (try? services.user?.recent()) ?? [] }()
        if !items.isEmpty {
            header(Text("Zuletzt", bundle: .module))
            ForEach(items.prefix(8)) { item in
                RecentRow(target: item.target)
                    .onTapGesture { open(item.target) }
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    // MARK: Actions

    /// Station → 09, place → 15, street or address → 16 (S5.6).
    private func open(_ result: SearchResult) {
        switch result.target {
        case let .station(station, _):
            open(.station(id: station.id, name: station.shortName, coordinate: station.coordinate))
        case let .place(place):
            open(.place(id: place.id, name: place.name, kind: place.kind, coordinate: place.coordinate))
        }
    }

    private func open(_ target: SavedTarget) {
        services.updateUser { try $0.addRecent(target) }
        switch target {
        case let .station(id, _, _):
            services.router.open(.stop(id))
        case let .place(id, name, kind, coordinate):
            if kind == .street || kind == .address {
                services.router.open(.pin(coordinate))
            } else if let place = services.transit.placeSearch.place(id: id) {
                services.router.open(.place(place))
            } else {
                services.router.open(.place(Place(id: id, name: name, kind: kind, category: "", area: "",
                                                  coordinate: coordinate)))
            }
        case let .point(_, coordinate):
            services.router.open(.pin(coordinate))
        }
    }

    /// Long-press saves (S5.5).
    private func save(_ result: SearchResult) {
        let target: SavedTarget = switch result.target {
        case let .station(station, _): .station(id: station.id, name: station.shortName, coordinate: station.coordinate)
        case let .place(place): .place(id: place.id, name: place.name, kind: place.kind, coordinate: place.coordinate)
        }
        if !services.isFavorite(target) { services.toggleFavorite(target) }
        withAnimation(KGMotion.sheet) { toast = Text("„\(result.name)“ gemerkt", bundle: .module) }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toast = nil }
        }
    }
}

/// Zuhause · Arbeit · Uni: outlined 46 pt buttons. One without an address offers to set it (S5.2).
private struct QuickChips: View {
    let services: AppServices
    let onPick: (SavedTarget) -> Void

    var body: some View {
        HStack(spacing: KGSpace.compact) {
            chip(.home, icon: .home, title: Text("Zuhause", bundle: .module))
            chip(.work, icon: .work, title: Text("Arbeit", bundle: .module))
            chip(.uni, icon: .uniCap, title: Text("Uni", bundle: .module))
        }
    }

    private func chip(_ slot: Favorite.Slot, icon: KGIcon, title: Text) -> some View {
        let favorite = { _ = services.userVersion; return try? services.user?.slot(slot) }()
        return KGButton(title, icon: icon, kind: .outline) {
            if let favorite {
                onPick(favorite.target)
            } else {
                services.router.open(.pin(services.anchor))
            }
        }
        .accessibilityHint(favorite == nil ? Text("Noch nicht festgelegt", bundle: .module)
                                           : Text(verbatim: favorite?.target.name ?? ""))
    }
}

/// One result: coloured circle by kind, name with the typed part bold, what it is, line badges for stops.
struct ResultRow: View {
    let result: SearchResult
    let query: String

    var body: some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(icon, size: 21)
                .foregroundStyle(KGColor.white)
                .frame(width: 40, height: 40)
                .background(tint, in: .circle)
            HStack(spacing: KGSpace.compact) {
                VStack(alignment: .leading, spacing: 1) {
                    highlightedName.kgFont(.bodyMedium).foregroundStyle(KGColor.ink).lineLimit(1)
                    subtitle.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if case let .station(_, lines) = result.target {
                    HStack(spacing: KGSpace.xxs) {
                        ForEach(lines.prefix(3), id: \.id) { KGLineBadge($0.name, size: .small) }
                    }
                }
            }
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) { Rectangle().fill(KGColor.line).frame(height: 1) }
        }
        .padding(.horizontal, KGSpace.large)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// "**Uni**versität": the matched characters ExtraBold.
    private var highlightedName: Text {
        let name = result.name
        guard let match = result.match, match.lowerBound >= 0, match.upperBound <= name.count else {
            return Text(verbatim: name)
        }
        let start = name.index(name.startIndex, offsetBy: match.lowerBound)
        let end = name.index(name.startIndex, offsetBy: match.upperBound)
        return Text(verbatim: String(name[..<start]))
            + Text(verbatim: String(name[start..<end])).font(KGTextStyle.bodyMedium.weighted(KGFont.extraBold).font)
            + Text(verbatim: String(name[end...]))
    }

    private var subtitle: Text {
        switch result.target {
        case .station: Text("Haltestelle", bundle: .module)
        case let .place(place):
            if place.kind == .street {
                Text("Straße · \(place.area)", bundle: .module)
            } else if let address = place.address, !address.isEmpty {
                Text(verbatim: address)
            } else {
                Text(verbatim: [place.categoryGerman, place.area].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
    }

    private var icon: KGIcon {
        switch result.target {
        case .station: .bus
        case let .place(place): place.kind == .street || place.kind == .address ? .pin : .pinFilled
        }
    }

    private var tint: Color {
        switch result.target {
        case .station: KGColor.coral
        case let .place(place): place.kind == .street || place.kind == .address ? KGColor.ink3 : KGColor.live
        }
    }
}

/// A recent search: grey circle with a clock, name, kind (56 high).
private struct RecentRow: View {
    let target: SavedTarget

    var body: some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(.history, size: 20)
                .foregroundStyle(KGColor.ink2)
                .frame(width: 40, height: 40)
                .kgGlassCard(in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: target.name).kgFont(.bodyMedium.weighted(KGFont.regular)).foregroundStyle(KGColor.ink)
                kind.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(KGColor.line).frame(height: 1) }
        }
        .padding(.horizontal, KGSpace.large)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var kind: Text {
        switch target {
        case .station: Text("Haltestelle", bundle: .module)
        case .place: Text("Ort", bundle: .module)
        case .point: Text("Markierter Ort", bundle: .module)
        }
    }
}

/// "Tipp: Halte eine Haltestelle gedrückt, um sie zu merken." with Seeri, on grey (S5.5).
private struct TipCard: View {
    @State private var bob = false

    var body: some View {
        HStack(spacing: KGSpace.medium) {
            Seeri(.happy).frame(width: 50, height: 54)
                .offset(y: bob ? -4 : 0)
                .kgLoop(.seeriPeek, phase: $bob)
            (Text("Tipp: ", bundle: .module).bold() + Text("Halte eine Haltestelle gedrückt, um sie zu merken.", bundle: .module))
                .kgFont(.callout.weighted(KGFont.regular))
                .foregroundStyle(KGColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, KGSpace.mediumLarge)
        .padding(.horizontal, KGSpace.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.pressed, in: .kgRounded(KGRadius.card))
        .accessibilityElement(children: .combine)
    }
}
