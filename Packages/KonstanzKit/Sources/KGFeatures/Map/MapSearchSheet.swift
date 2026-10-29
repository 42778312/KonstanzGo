import KGCore
import KGDesign
import SwiftUI

/// The map's search, Apple Maps style: the field at the top with ✕, and under it either the categories
/// (Schnell hin, saved stops, saved places: chips and cards that swipe sideways) and recent searches, or the
/// results while typing, each in a rounded group.
/// Picking something hands it to the map, which shows it in its own sheet.
struct MapSearchSheet: View {
    let services: AppServices
    /// Start listening right away (the microphone in the map's search bar).
    var listens = false
    let onPick: (SavedTarget) -> Void
    @State private var query = ""
    @State private var voice = VoiceSearch()
    @State private var results: [SearchResult] = []
    /// What `results` were found for, so "Nichts gefunden" waits for the search to finish.
    @State private var searched = ""
    @State private var settingSlot: Favorite.Slot?
    @State private var category: Category? = .quick

    enum Category: Int, CaseIterable, Identifiable {
        case quick, stops, places
        var id: Int { rawValue }
    }
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KGSpace.compact) {
                field
                Button { dismiss() } label: {
                    KGIconView(.close, size: 18).foregroundStyle(KGColor.ink)
                        .frame(width: 48, height: 48)
                        .background(KGColor.surface, in: .circle)
                }
                .buttonStyle(KGPressStyle())
                .accessibilityLabel(Text("Schließen", bundle: .module))
                .accessibilityIdentifier("closeSearch")
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, KGSpace.large)
            if let problem = voiceProblem {
                problem.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, KGSpace.large)
                    .padding(.top, KGSpace.small)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: KGSpace.xl) {
                    if trimmed.isEmpty {
                        categories
                        recent
                    } else if results.isEmpty, searched == trimmed {
                        KGEmptyState(.focused, title: Text("Nichts gefunden für „\(query)“", bundle: .module),
                                     message: Text("Versuch es mit einer Haltestelle, einer Straße oder einem Ort.",
                                                   bundle: .module))
                            .frame(maxWidth: .infinity)
                            .padding(.top, KGSpace.xl)
                    } else {
                        group(nil) {
                            ForEach(results) { result in
                                Button { onPick(Self.target(result)) } label: {
                                    ResultRow(result: result, query: query)
                                }
                                .buttonStyle(KGRowPressStyle())
                                .contextMenu {
                                    Button { save(result) } label: { Text("Merken", bundle: .module) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, KGSpace.screen)
                .padding(.vertical, KGSpace.large)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .background(KGColor.card.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // Focus once the sheet has settled, or the keyboard comes up without the field taking the typing.
            try? await Task.sleep(for: .milliseconds(350))
            voice.hints = services.transit.stations.map(\.shortName)
            if listens { await voice.start() } else { focused = true }
        }
        .onChange(of: voice.text) { _, words in if !words.isEmpty { query = words } }
        .onDisappear { voice.stop() }
        .task(id: trimmed) {
            // Off the main thread and after a short pause, so typing never waits for the search.
            let text = trimmed
            guard !text.isEmpty else { return results = [] }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let transit = services.transit
            let anchor = services.anchor
            let found = await Task.detached(priority: .userInitiated) {
                Array(transit.search(text, near: anchor).prefix(25))
            }.value
            if !Task.isCancelled {
                results = found
                searched = text
            }
        }
        .sheet(isPresented: Binding(get: { settingSlot != nil }, set: { if !$0 { settingSlot = nil } })) {
            if let slot = settingSlot {
                EndpointPicker(services: services, title: Self.slotQuestion(slot)) { endpoint in
                    services.updateUser {
                        try $0.setSlot(slot, to: .point(name: endpoint.name, coordinate: endpoint.coordinate))
                    }
                }
            }
        }
    }

    // MARK: Parts

    private var voiceProblem: Text? {
        switch voice.state {
        case .denied: Text("Erlaube Mikrofon und Spracherkennung in den Einstellungen, um per Sprache zu suchen.",
                            bundle: .module)
        case .unavailable: Text("Die Offline-Spracherkennung für deine Sprache ist auf diesem iPhone nicht geladen.",
                                bundle: .module)
        case .needsDownload:
            Text("Für die erste Sprachsuche lädt das iPhone einmal das Sprachmodell. Bitte versuch es einmal mit Internet, danach geht es offline.",
                 bundle: .module)
        case .idle, .preparing, .listening: nil
        }
    }

    private var field: some View {
        HStack(spacing: KGSpace.small) {
            KGIconView(.search, size: 20).foregroundStyle(KGColor.ink2)
            TextField(text: $query, prompt: Text("Wohin möchtest du?", bundle: .module)) {
                Text("Suche", bundle: .module)
            }
            .kgFont(.bodyMedium)
            .foregroundStyle(KGColor.ink)
            .tint(KGColor.coral)
            .focused($focused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .accessibilityIdentifier("searchField")
            if voice.state == .preparing {
                Text("Lade Sprachmodell …", bundle: .module)
                    .kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.ink2)
                    .fixedSize()
            } else if voice.isListening {
                Text("Ich höre zu …", bundle: .module)
                    .kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.coral)
                    .fixedSize()
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    KGIconView(.close, size: 10).foregroundStyle(KGColor.surface)
                        .frame(width: 20, height: 20)
                        .background(KGColor.ink3, in: .circle)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Löschen", bundle: .module))
            }
            MicButton(voice: voice) { focused = false }
        }
        .padding(.leading, KGSpace.mediumLarge)
        .padding(.trailing, KGSpace.xs)
        .frame(minHeight: 48)
        .background(KGColor.surface, in: .capsule)
    }

    /// Schnell hin · Haltestellen · Orte: chips on top, and one card each that swipes sideways.
    private var categories: some View {
        VStack(alignment: .leading, spacing: KGSpace.medium) {
            ScrollViewReader { chips in
                ScrollView(.horizontal) {
                    HStack(spacing: KGSpace.small) {
                        ForEach(Category.allCases) { item in
                            KGChip(title(item), isOn: (category ?? .quick) == item) {
                                withAnimation(KGMotion.slide) { category = item }
                            }
                            .id(item)
                            .accessibilityIdentifier("category-\(item.rawValue)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // The chip row follows the cards, so the chosen one is always in view.
                .onChange(of: category) { _, item in
                    withAnimation(KGMotion.slide) { chips.scrollTo(item, anchor: .center) }
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: KGSpace.medium) {
                    ForEach(Category.allCases) { item in
                        card(item)
                            .containerRelativeFrame(.horizontal)
                            .id(item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $category)
            .scrollIndicators(.hidden)
        }
    }

    private func title(_ item: Category) -> Text {
        switch item {
        case .quick: Text("Schnell hin", bundle: .module)
        case .stops: Text("Gemerkte Haltestellen", bundle: .module)
        case .places: Text("Gemerkte Orte", bundle: .module)
        }
    }

    private var savedFavorites: [Favorite] {
        _ = services.userVersion
        return ((try? services.user?.favorites()) ?? []).filter { $0.slot == nil }
    }

    @ViewBuilder private func card(_ item: Category) -> some View {
        VStack(spacing: 0) {
            switch item {
            case .quick:
                slotRow(.home, icon: .home, tint: KGColor.location, title: Text("Zuhause", bundle: .module))
                slotRow(.uni, icon: .uniCap, tint: KGColor.live, title: Text("Uni", bundle: .module))
                slotRow(.work, icon: .work, tint: KGColor.warn, title: Text("Arbeit", bundle: .module), last: true)
            case .stops:
                let stops = savedFavorites.filter { if case .station = $0.target { true } else { false } }
                savedRows(stops, icon: .bus, tint: KGColor.coral,
                          empty: Text("Noch keine Haltestelle gemerkt", bundle: .module))
            case .places:
                let places = savedFavorites.filter { if case .station = $0.target { false } else { true } }
                savedRows(places, icon: .pinFilled, tint: KGColor.live,
                          empty: Text("Noch kein Ort gemerkt", bundle: .module))
            }
        }
        .padding(.vertical, KGSpace.xs)
        .background(KGColor.surface, in: .kgRounded(KGRadius.card))
        .clipShape(.kgRounded(KGRadius.card))
    }

    @ViewBuilder private func savedRows(_ items: [Favorite], icon: KGIcon, tint: Color, empty: Text) -> some View {
        if items.isEmpty {
            SheetRow(icon: .star, tint: KGColor.ink3, title: empty,
                     subtitle: Text("Tippe auf ★, um etwas zu merken", bundle: .module), showsDivider: false)
        }
        ForEach(Array(items.enumerated()), id: \.element.id) { index, favorite in
            Button { onPick(favorite.target) } label: {
                SheetRow(icon: icon, tint: tint, title: Text(verbatim: favorite.displayName),
                         subtitle: Self.kind(favorite.target), showsDivider: index < items.count - 1)
            }
            .buttonStyle(KGRowPressStyle())
        }
    }

    private func slotRow(_ slot: Favorite.Slot, icon: KGIcon, tint: Color, title: Text,
                         last: Bool = false) -> some View {
        let favorite = { _ = services.userVersion; return try? services.user?.slot(slot) }()
        return Button {
            if let favorite { onPick(favorite.target) } else { settingSlot = slot }
        } label: {
            SheetRow(icon: icon, tint: tint, title: title,
                     subtitle: favorite.map { Text(verbatim: $0.target.name) }
                        ?? Text("Adresse festlegen", bundle: .module),
                     showsDivider: !last)
        }
        .buttonStyle(KGRowPressStyle())
    }

    @ViewBuilder private var recent: some View {
        let items = { _ = services.userVersion; return (try? services.user?.recent()) ?? [] }()
        if !items.isEmpty {
            let shown = Array(items.prefix(8))
            group(Text("Zuletzt", bundle: .module)) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    Button { onPick(item.target) } label: {
                        SheetRow(icon: .history, tint: KGColor.ink3, title: Text(verbatim: item.target.name),
                                 subtitle: Self.kind(item.target), showsDivider: index < shown.count - 1)
                    }
                    .buttonStyle(KGRowPressStyle())
                }
            }
        }
    }

    /// A title over a white rounded group.
    private func group<Content: View>(_ title: Text?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            if let title {
                title.kgFont(.title).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, KGSpace.xs)
            }
            VStack(spacing: 0) { content() }
                .padding(.vertical, KGSpace.xs)
                .background(KGColor.surface, in: .kgRounded(KGRadius.card))
                .clipShape(.kgRounded(KGRadius.card))
        }
    }

    // MARK: Helpers

    static func target(_ result: SearchResult) -> SavedTarget {
        switch result.target {
        case let .station(station, _): .station(id: station.id, name: station.shortName, coordinate: station.coordinate)
        case let .place(place): .place(id: place.id, name: place.name, kind: place.kind, coordinate: place.coordinate)
        }
    }

    static func kind(_ target: SavedTarget) -> Text {
        switch target {
        case .station: Text("Haltestelle", bundle: .module)
        case .place: Text("Ort", bundle: .module)
        case .point: Text("Markierter Ort", bundle: .module)
        }
    }

    static func slotQuestion(_ slot: Favorite.Slot) -> Text {
        switch slot {
        case .home: Text("Wo ist dein Zuhause?", bundle: .module)
        case .work: Text("Wo arbeitest du?", bundle: .module)
        case .uni: Text("Welche Uni?", bundle: .module)
        }
    }

    private func save(_ result: SearchResult) {
        let target = Self.target(result)
        if !services.isFavorite(target) { services.toggleFavorite(target) }
    }
}

/// A row in a rounded group: coloured circle with an icon, title, a grey line, and a divider under the text.
struct SheetRow: View {
    let icon: KGIcon
    let tint: Color
    let title: Text
    let subtitle: Text?
    var showsDivider = true

    var body: some View {
        HStack(spacing: KGSpace.medium) {
            KGIconView(icon, size: 19).foregroundStyle(KGColor.white)
                .frame(width: 38, height: 38)
                .background(tint, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                title.kgFont(.bodyMedium).foregroundStyle(KGColor.ink).lineLimit(1)
                if let subtitle {
                    subtitle.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .overlay(alignment: .bottom) {
                if showsDivider { Rectangle().fill(KGColor.line).frame(height: 1) }
            }
        }
        .padding(.horizontal, KGSpace.mediumLarge)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The microphone: starts or stops listening; coral and pulsing while it listens.
struct MicButton: View {
    let voice: VoiceSearch
    var size: CGFloat = 20
    var willListen: () -> Void = {}
    @State private var pulse = false

    var body: some View {
        Button {
            willListen()
            voice.toggle()
        } label: {
            KGIconView(.mic, size: size)
                .foregroundStyle(voice.isListening ? KGColor.white : KGColor.ink2)
                .frame(width: size + 18, height: size + 18)
                .background {
                    if voice.isListening {
                        Circle().fill(KGColor.coral)
                            .scaleEffect(pulse ? 1.12 : 0.94)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                            .onAppear { pulse = true }
                            .onDisappear { pulse = false }
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.isListening ? Text("Zuhören beenden", bundle: .module)
                                              : Text("Per Sprache suchen", bundle: .module))
        .accessibilityIdentifier("voiceSearch")
    }
}
