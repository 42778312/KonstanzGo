import KGCore
import KGDesign
import SwiftUI

/// Screen 12 (Favoriten): "Schnell los" cards for Zuhause / Uni / Arbeit with the next connection, "Meine
/// Haltestellen" with their next two buses, "Zuletzt gesucht", and an edit mode to reorder, rename and remove
/// (plan S16).
struct SavedScreen: View {
    let services: AppServices
    @State private var editing = false
    @State private var now = Date.now
    @State private var quick: [Favorite.Slot: Journey?] = [:]
    @State private var renaming: Favorite?
    @State private var newName = ""

    private var favorites: [Favorite] {
        _ = services.userVersion
        return (try? services.user?.favorites()) ?? []
    }

    private var stops: [Favorite] {
        favorites.filter { if case .station = $0.target { return $0.slot == nil } else { return false } }
    }

    private var places: [Favorite] {
        favorites.filter { $0.slot == nil && !stops.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Favoriten", bundle: .module).kgFont(.display.weighted(KGFont.bold).sized(34))
                    .foregroundStyle(KGColor.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                KGTextButton(editing ? Text("Fertig", bundle: .module) : Text("Bearbeiten", bundle: .module),
                             style: .bodyMedium) {
                    withAnimation { editing.toggle() }
                }
                .accessibilityIdentifier("editFavorites")
            }
            .padding(.leading, KGSpace.large)
            .padding(.trailing, KGSpace.medium)
            .padding(.top, KGSpace.small)
            if editing {
                EditFavoritesList(services: services, favorites: favorites.filter { $0.slot == nil }) { favorite in
                    newName = favorite.displayName
                    renaming = favorite
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        KGSectionHeader(Text("Schnell los", bundle: .module)).padding(.horizontal, KGSpace.large)
                            .padding(.top, KGSpace.large).padding(.bottom, KGSpace.small)
                        ScrollView(.horizontal) {
                            HStack(spacing: KGSpace.medium) {
                                QuickCard(services: services, slot: .home, journey: quick[.home] ?? nil, now: now)
                                QuickCard(services: services, slot: .uni, journey: quick[.uni] ?? nil, now: now)
                                QuickCard(services: services, slot: .work, journey: quick[.work] ?? nil, now: now)
                            }
                            .padding(.horizontal, KGSpace.screen)
                            .padding(.vertical, KGSpace.small)
                        }
                        .scrollIndicators(.hidden)
                        myStops
                        if !places.isEmpty { myPlaces }
                        recentLink
                    }
                    .padding(.bottom, KGSpace.large)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: services.userVersion) { await planQuick() }
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .alert(Text("Umbenennen", bundle: .module), isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
            TextField(text: $newName) { Text("Name", bundle: .module) }
            Button { if let renaming { services.updateUser { try $0.renameFavorite(id: renaming.id, to: newName) } } } label: {
                Text("Sichern", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("Abbrechen", bundle: .module) }
        }
    }

    // MARK: Sections

    @ViewBuilder private var myStops: some View {
        KGSectionHeader(Text("Meine Haltestellen", bundle: .module)).padding(.horizontal, KGSpace.large)
            .padding(.top, KGSpace.xl).padding(.bottom, KGSpace.small)
        if stops.isEmpty {
            KGEmptyState(.curious, title: Text("Noch keine Haltestelle gemerkt", bundle: .module),
                         message: Text("Tippe auf den Stern bei einer Haltestelle oder halte sie in der Suche gedrückt.",
                                       bundle: .module))
                .padding(.vertical, KGSpace.large)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, favorite in
                    if case let .station(id, _, _) = favorite.target {
                        FavoriteStopRow(services: services, favorite: favorite, stationID: id, now: now)
                            .overlay(alignment: .bottom) {
                                if index < stops.count - 1 { Rectangle().fill(KGColor.line).frame(height: 1) }
                            }
                    }
                }
            }
            .kgGlassCard(in: .kgRounded(KGRadius.card))
            .padding(.horizontal, KGSpace.screen)
        }
    }

    private var myPlaces: some View {
        VStack(alignment: .leading, spacing: 0) {
            KGSectionHeader(Text("Meine Orte", bundle: .module)).padding(.horizontal, KGSpace.large)
                .padding(.top, KGSpace.xl).padding(.bottom, KGSpace.small)
            VStack(spacing: 0) {
                ForEach(places) { favorite in
                    Button { services.openOnMap(favorite.target) } label: {
                        HStack(spacing: KGSpace.medium) {
                            KGIconView(.pinFilled, size: 18).foregroundStyle(KGColor.white)
                                .frame(width: 32, height: 32).background(KGColor.live, in: .circle)
                            Text(verbatim: favorite.displayName).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                            Spacer()
                            KGIconView(.chevronRight, size: 14).foregroundStyle(KGColor.chevron)
                        }
                        .padding(.horizontal, KGSpace.screen)
                        .frame(minHeight: 56)
                        .contentShape(.rect)
                    }
                    .buttonStyle(KGRowPressStyle())
                }
            }
            .kgGlassCard(in: .kgRounded(KGRadius.card))
            .padding(.horizontal, KGSpace.screen)
        }
    }

    private var recentLink: some View {
        let count = { _ = services.userVersion; return (try? services.user?.recent().count) ?? 0 }()
        // Inside the menu's own stack, so it stays in the sheet.
        return NavigationLink(value: MoreRoute.recent) {
            HStack(spacing: KGSpace.medium) {
                KGIconView(.history, size: 18).foregroundStyle(KGColor.ink)
                    .frame(width: 32, height: 32).background(KGColor.pressed, in: .circle)
                Text("Zuletzt gesucht", bundle: .module).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                Spacer()
                Text(count, format: .number).kgFont(.callout).foregroundStyle(KGColor.ink3)
                KGIconView(.chevronRight, size: 14).foregroundStyle(KGColor.chevron)
            }
            .padding(.horizontal, KGSpace.screen)
            .frame(minHeight: KGSize.searchBar)
            .kgGlassCard(in: .kgRounded(KGRadius.search))
            .contentShape(.rect)
        }
        .buttonStyle(KGPressStyle())
        .padding(.horizontal, KGSpace.screen)
        .padding(.top, KGSpace.xl)
        .accessibilityIdentifier("recentLink")
    }

    /// The next connection for each set slot, from here (or the old town).
    private func planQuick() async {
        let user = services.user
        let transit = services.transit
        let start = services.routeStart
        var result: [Favorite.Slot: Journey?] = [:]
        for slot in Favorite.Slot.allCases {
            guard let favorite = try? user?.slot(slot) else { continue }
            let request = PlanRequest(from: start, to: Endpoint(name: favorite.target.name,
                                                                coordinate: favorite.target.coordinate), time: .now)
            let journeys = await Task.detached(priority: .utility) { (try? transit.plan(request)) ?? [] }.value
            result[slot] = JourneyPlanner.ranked(journeys, by: .fastest, arriveBy: false).first
        }
        quick = result
    }
}

/// A "Schnell los" card: slot icon and name, the first line and where it stops, duration, "Los"; or, without
/// an address, "Noch keine Adresse" and "Festlegen".
private struct QuickCard: View {
    let services: AppServices
    let slot: Favorite.Slot
    let journey: Journey?
    let now: Date

    private var favorite: Favorite? {
        _ = services.userVersion
        return try? services.user?.slot(slot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KGSpace.small) {
                KGIconView(icon, size: 16).foregroundStyle(tint)
                    .frame(width: 32, height: 32).background(background, in: .circle)
                title.kgFont(.bodyStrong.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink)
            }
            if let favorite {
                if let journey, let ride = journey.firstRide {
                    HStack(spacing: KGSpace.xs) {
                        KGLineBadge(ride.line.name, size: .small)
                        Text(verbatim: ride.boarding.station.shortName).lineLimit(1)
                    }
                    .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    .padding(.top, KGSpace.compact)
                } else {
                    Text(verbatim: favorite.target.name).kgFont(.caption.weighted(KGFont.regular))
                        .foregroundStyle(KGColor.ink2).lineLimit(1).padding(.top, KGSpace.compact)
                }
                HStack {
                    if let journey {
                        Text("\(journey.minutes) Min.", bundle: .module).kgFont(.title.weighted(KGFont.bold))
                            .foregroundStyle(KGColor.ink)
                    }
                    Spacer()
                    Button { go(to: favorite) } label: {
                        Text("Los", bundle: .module).kgFont(.callout.weighted(KGFont.bold)).foregroundStyle(KGColor.white)
                            .padding(.horizontal, KGSpace.medium).frame(minHeight: 32)
                            .background(KGColor.coral, in: .kgRounded(KGRadius.compact))
                    }
                    .buttonStyle(KGPressStyle())
                }
                .padding(.top, KGSpace.compact)
            } else {
                Text("Noch keine Adresse", bundle: .module).kgFont(.caption.weighted(KGFont.regular))
                    .foregroundStyle(KGColor.ink2).padding(.top, KGSpace.compact)
                Button { services.selectTab?(.map); services.router.home(); services.wantsSearch = true } label: {
                    Text("Festlegen", bundle: .module).kgFont(.footnote.weighted(KGFont.extraBold))
                        .foregroundStyle(KGColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .overlay(RoundedRectangle(cornerRadius: KGRadius.compact)
                            .strokeBorder(KGColor.chevron, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                }
                .buttonStyle(KGPressStyle())
                .padding(.top, KGSpace.mediumLarge)
            }
        }
        .padding(.vertical, KGSpace.medium)
        .padding(.horizontal, KGSpace.mediumLarge)
        .frame(width: 168, alignment: .leading)
        .kgGlassCard(in: .kgRounded(KGRadius.card))
        .overlay(RoundedRectangle(cornerRadius: KGRadius.card, style: .continuous).stroke(KGColor.line, lineWidth: 1))
        .kgShadow(.card, in: .kgRounded(KGRadius.card))
        .accessibilityElement(children: .contain)
    }

    private func go(to favorite: Favorite) {
        services.openOnMap(favorite.target)
    }

    private var title: Text {
        switch slot {
        case .home: Text("Zuhause", bundle: .module)
        case .work: Text("Arbeit", bundle: .module)
        case .uni: Text("Uni", bundle: .module)
        }
    }

    private var icon: KGIcon {
        switch slot {
        case .home: .home
        case .work: .work
        case .uni: .uniCap
        }
    }

    private var tint: Color {
        switch slot {
        case .home: KGColor.location
        case .work: KGColor.lineText
        case .uni: KGColor.liveText
        }
    }

    private var background: Color {
        switch slot {
        case .home: KGColor.locationTint
        case .work: KGColor.lineTint
        case .uni: KGColor.liveTint
        }
    }
}

/// A saved stop with its next two buses as grey pills (screen 12).
private struct FavoriteStopRow: View {
    let services: AppServices
    let favorite: Favorite
    let stationID: Int
    let now: Date

    var body: some View {
        let next = (try? services.transit.departures(at: stationID, from: now, limit: 2)) ?? []
        Button { services.openOnMap(favorite.target) } label: {
            VStack(alignment: .leading, spacing: KGSpace.small) {
                HStack {
                    Text(verbatim: favorite.displayName).kgFont(.bodyStrong.weighted(KGFont.extraBold))
                        .foregroundStyle(KGColor.ink)
                    Spacer()
                    KGIconView(.chevronRight, size: 14).foregroundStyle(KGColor.chevron)
                }
                if next.isEmpty {
                    Text("Heute fährt hier nichts mehr.", bundle: .module).kgFont(.caption.weighted(KGFont.regular))
                        .foregroundStyle(KGColor.ink2)
                } else {
                    HStack(spacing: KGSpace.small) {
                        ForEach(next) { departure in
                            HStack(spacing: KGSpace.small) {
                                KGLineBadge(departure.line.name, size: .small)
                                KGMinutes(departure.expected, now: now, isLive: departure.status.isLive)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, KGSpace.compact)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .kgGlassCard(in: .kgRounded(KGRadius.medium))
                        }
                    }
                }
            }
            .padding(.vertical, KGSpace.medium)
            .padding(.horizontal, KGSpace.screen)
            .contentShape(.rect)
        }
        .buttonStyle(KGRowPressStyle())
        .accessibilityIdentifier("favoriteStop")
    }
}

/// Edit mode (S16.4): drag to reorder, swipe or tap to remove, tap to rename.
private struct EditFavoritesList: View {
    let services: AppServices
    let favorites: [Favorite]
    let onRename: (Favorite) -> Void

    var body: some View {
        List {
            ForEach(favorites) { favorite in
                Button { onRename(favorite) } label: {
                    HStack {
                        Text(verbatim: favorite.displayName).kgFont(.bodyMedium).foregroundStyle(KGColor.ink)
                        Spacer()
                        KGIconView(.feedback, size: 16).foregroundStyle(KGColor.ink3)
                    }
                }
                .accessibilityHint(Text("Umbenennen", bundle: .module))
                .listRowBackground(KGColor.glassFill)
            }
            .onMove { from, to in services.updateUser { try $0.moveFavorites(from: from, to: to) } }
            .onDelete { offsets in
                for index in offsets { services.updateUser { try $0.removeFavorite(id: favorites[index].id) } }
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .scrollContentBackground(.hidden)
    }
}
