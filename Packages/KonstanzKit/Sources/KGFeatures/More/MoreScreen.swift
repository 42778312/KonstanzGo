import KGCore
import KGDesign
import SwiftUI
import UserNotifications

/// The address "Hilfe & Feedback" writes to (the same as the Android app's privacy policy).
enum AppInfo {
    static let supportEmail = "konstant@werkflow.cc"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// The menu's own screens.
enum MoreRoute: Hashable { case favorites, recent, offline, privacy, about }

/// Screen 13 (Mehr), opened from Seeri in the map's search bar as a half sheet: the offline status on top;
/// Favoriten; notifications, alarm lead time; language (the app is always dark); privacy, help, about; the version
/// (plan S17.1).
struct MoreScreen: View {
    let services: AppServices
    let onReplayOnboarding: () -> Void
    @State private var path: [MoreRoute] = []
    @State private var notifications = false
    @AppStorage("alarm.minutes") private var alarmMinutes = 2
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: KGSpace.large) {
                    Text("Mehr", bundle: .module).kgFont(.display.sized(34)).foregroundStyle(KGColor.ink)
                        .padding(.horizontal, KGSpace.xxs)
                        .accessibilityAddTraits(.isHeader)
                    OfflineCard(info: services.transit.timetableInfo) { path.append(.offline) }
                        .riseIn(after: 0)
                    KGSettingsGroup {
                        KGSettingsRow(Text("Favoriten", bundle: .module), icon: .star, tile: KGColor.warn) {
                            path.append(.favorites)
                        }
                        .accessibilityIdentifier("openFavorites")
                    }
                    .riseIn(after: 0.05)
                    KGSettingsGroup {
                        KGSettingsRow(Text("Mitteilungen", bundle: .module), icon: .bell, tile: KGColor.tileRed,
                                      isOn: Binding { notifications } set: { setNotifications($0) })
                        alarmRow
                    }
                    .riseIn(after: 0.1)
                    KGSettingsGroup {
                        KGSettingsRow(Text("Sprache", bundle: .module), icon: .globe, tile: KGColor.tileIndigo,
                                      value: Text(verbatim: Locale.current.localizedString(
                                          forLanguageCode: Locale.current.language.languageCode?.identifier ?? "de") ?? "")) {
                            openSettings()
                        }
                    }
                    .riseIn(after: 0.2)
                    KGSettingsGroup {
                        KGSettingsRow(Text("Datenschutz", bundle: .module), icon: .shield, tile: KGColor.live) {
                            path.append(.privacy)
                        }
                        KGSettingsRow(Text("Hilfe & Feedback", bundle: .module), icon: .feedback, tile: KGColor.coral) {
                            if let url = URL(string: "mailto:\(AppInfo.supportEmail)?subject=KonstanzGo%20\(AppInfo.version)") {
                                openURL(url)
                            }
                        }
                        KGSettingsRow(Text("Über KonstanzGo", bundle: .module), icon: .live, tile: KGColor.tileBlack) {
                            path.append(.about)
                        }
                        KGSettingsRow(Text("Tour mit Seeri", bundle: .module), icon: .map, tile: KGColor.coral) {
                            services.showsMenu = false
                            services.wantsTour = true
                        }
                        .accessibilityIdentifier("startTour")
                        KGSettingsRow(Text("Einführung ansehen", bundle: .module), icon: .history, tile: KGColor.location,
                                      action: onReplayOnboarding)
                            .accessibilityIdentifier("replayOnboarding")
                    }
                    .riseIn(after: 0.3)
                    VStack(spacing: KGSpace.xs) {
                        SeeriLogo(size: 40)
                        Text("KonstanzGo · Version \(AppInfo.version)", bundle: .module)
                            .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, KGSpace.small)
                }
                .padding(.horizontal, KGSpace.screen)
                .padding(.top, KGSpace.small)
                .padding(.bottom, KGSpace.large)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .kgHideNavigationBar()
            .navigationDestination(for: MoreRoute.self) { route in
                Group {
                    switch route {
                    case .favorites:
                        SavedScreen(services: services)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                BackLink(title: Text("Mehr", bundle: .module)) { path.removeLast() }
                                    .padding(.horizontal, KGSpace.screen)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                    case .recent:
                        RecentScreen(services: services) { path.removeLast() }
                    case .offline: OfflineDataScreen(services: services) { path.removeLast() }
                    case .privacy: PrivacyScreen(services: services) { path.removeLast() }
                    case .about: AboutScreen(info: services.transit.timetableInfo) { path.removeLast() }
                    }
                }
                .kgHideNavigationBar()
            }
        }
        .task(id: scenePhase) { await readNotificationState() }
    }

    private var alarmRow: some View {
        Menu {
            Picker(selection: $alarmMinutes) {
                ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) Min. vorher", bundle: .module).tag($0) }
            } label: { EmptyView() }
        } label: {
            KGSettingsRow(Text("Abfahrtsalarm", bundle: .module), icon: .timer, tile: KGColor.warn,
                          value: Text("\(alarmMinutes) Min. vorher", bundle: .module)) {}
                .allowsHitTesting(false)
        }
    }

    private func readNotificationState() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifications = status == .authorized || status == .provisional
    }

    /// On while refused in iOS → the app's notification settings (S17.2).
    private func setNotifications(_ on: Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if on, status == .notDetermined {
                notifications = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            } else {
                openNotificationSettings()
            }
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }

    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #endif
    }
}

/// The offline card on 13 (S17.3a): ring, "Offline-Daten ›", status line. No refresh button: data comes
/// with app updates (0.2.4).
private struct OfflineCard: View {
    let info: TimetableInfo?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: KGSpace.mediumLarge) {
                ZStack {
                    Circle().stroke(KGColor.liveTint, lineWidth: 6)
                    Circle().trim(from: 0, to: 1).stroke(KGColor.live, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    KGIconView(.check, size: 22).foregroundStyle(KGColor.liveText)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline-Daten ›", bundle: .module).kgFont(.bodyMedium).foregroundStyle(KGColor.location)
                    OfflineStatusText(info: info).kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                }
                Spacer()
            }
            .padding(KGSpace.screen)
            .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
        }
        .buttonStyle(KGPressStyle())
        .accessibilityIdentifier("offlineCard")
    }
}

/// "Fahrplan bis 12. Dez. 2026 · bereit ohne Netz", or the warning in the last 14 days.
struct OfflineStatusText: View {
    let info: TimetableInfo?

    var body: some View {
        if let info, let end = Calendar.konstanz.date(from: info.validUntil) {
            if end.timeIntervalSinceNow < 14 * 86_400 {
                Text("Fahrplan endet bald · Bitte App aktualisieren", bundle: .module)
            } else {
                Text("Fahrplan bis \(end, format: .dateTime.day().month().year()) · bereit ohne Netz", bundle: .module)
            }
        } else {
            Text("Offline-Daten fehlen", bundle: .module)
        }
    }
}

/// Screen 24 (Offline-Daten): total size, status, the parts with their real sizes, the bundled area. No
/// download or update controls: everything comes with the app (plan S17.3).
struct OfflineDataScreen: View {
    let services: AppServices
    let onBack: () -> Void

    private var parts: [(name: Text, bytes: Int64, color: Color)] {
        let data = services.data
        func size(_ url: URL) -> Int64 {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            else { return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
            var total: Int64 = 0
            for case let file as URL in enumerator {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }
        let file = { (url: URL) -> Int64 in Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return [
            (Text("Karte", bundle: .module), size(data.mapFolder), KGColor.coral),
            (Text("Fahrpläne", bundle: .module), file(data.timetable), KGColor.lineFill),
            (Text("Haltestellen & Wege", bundle: .module), file(data.walkGraph) + file(data.searchIndex), KGColor.live),
        ]
    }

    var body: some View {
        let parts = self.parts
        let total = parts.reduce(0) { $0 + $1.bytes }
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.large) {
                BackLink(title: Text("Mehr", bundle: .module), action: onBack)
                Text("Offline-Daten", bundle: .module).kgFont(.display.weighted(KGFont.bold)).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: KGSpace.screen) {
                    HStack(spacing: KGSpace.screen) {
                        VStack(spacing: 0) {
                            Text(verbatim: "\(total / 1_000_000)").kgFont(.titleL.sized(26))
                            Text(verbatim: "MB").kgFont(.caption.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink2)
                        }
                        .frame(width: 104, height: 104)
                        .overlay(Circle().stroke(KGColor.live, lineWidth: 8).padding(4))
                        VStack(alignment: .leading, spacing: KGSpace.xxs) {
                            KGTag(Text("Alles aktuell", bundle: .module), tone: .live)
                            Text("Bereit ohne Netz", bundle: .module).kgFont(.bodyStrong.weighted(KGFont.extraBold))
                            OfflineStatusText(info: services.transit.timetableInfo)
                                .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        }
                        .foregroundStyle(KGColor.ink)
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 3) {
                            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                                part.color.frame(width: max(4, (proxy.size.width - 6) * CGFloat(part.bytes) / CGFloat(max(total, 1))))
                            }
                        }
                    }
                    .frame(height: 12)
                    .clipShape(.capsule)
                    KGFlowLayout(spacing: KGSpace.mediumLarge, lineSpacing: KGSpace.xs) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            HStack(spacing: 5) {
                                Circle().fill(part.color).frame(width: 8, height: 8)
                                part.name + Text(verbatim: " \(ByteCountFormatter.string(fromByteCount: part.bytes, countStyle: .file))")
                            }
                            .kgFont(.caption.weighted(KGFont.bold)).foregroundStyle(KGColor.ink2)
                        }
                    }
                }
                .padding(KGSpace.screen)
                .background(KGColor.glassFill, in: .kgRounded(KGRadius.cardLarge))
                KGSectionHeader(Text("Gebiete", bundle: .module))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Konstanz Stadt", bundle: .module).kgFont(.body.weighted(KGFont.extraBold))
                        Text("In der App enthalten", bundle: .module).kgFont(.caption.weighted(KGFont.regular))
                            .foregroundStyle(KGColor.ink2)
                    }
                    .foregroundStyle(KGColor.ink)
                    Spacer()
                    KGIconView(.check, size: 18).foregroundStyle(KGColor.liveText)
                }
                .padding(.horizontal, KGSpace.screen)
                .frame(minHeight: 62)
                .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
                Text("Neue Fahrpläne kommen mit App-Updates. Die App lädt nie selbst etwas aus dem Netz.", bundle: .module)
                    .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink3)
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.bottom, KGSpace.large)
        }
        .background(Color.clear)
    }
}

/// Screen 25 (Datenschutz): the three promises, the policy in the app, and deleting the history (plan S17.4).
/// The design's statistics and crash-report switches are left out: the app collects nothing (0.3).
struct PrivacyScreen: View {
    let services: AppServices
    let onBack: () -> Void
    @State private var confirming = false
    @State private var showsPolicy = false
    @State private var cleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.large) {
                BackLink(title: Text("Mehr", bundle: .module), action: onBack)
                Text("Deine Daten bleiben bei dir", bundle: .module).kgFont(.display.weighted(KGFont.bold))
                    .foregroundStyle(KGColor.ink).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    promise(.locate, KGColor.location, KGColor.locationTint, Text("Standort nur auf dem iPhone", bundle: .module),
                            Text("Er wird nie an uns gesendet.", bundle: .module))
                    promise(.noTracking, KGColor.ink2, KGColor.pressed, Text("Keine Werbung, kein Tracking", bundle: .module),
                            Text("Einfach Bus fahren.", bundle: .module))
                    promise(.history, KGColor.lineText, KGColor.lineTint, Text("Suchverlauf bleibt lokal", bundle: .module),
                            Text("Du kannst ihn jederzeit löschen.", bundle: .module))
                }
                .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
                KGButton(Text("Datenschutzerklärung lesen", bundle: .module), kind: .secondary) { showsPolicy = true }
                KGButton(cleared ? Text("Verlauf gelöscht", bundle: .module) : Text("Verlauf löschen", bundle: .module),
                         icon: .trash, kind: .secondary) { confirming = true }
                    .disabled(cleared)
                    .accessibilityIdentifier("clearHistory")
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.bottom, KGSpace.large)
        }
        .background(Color.clear)
        .confirmationDialog(Text("Suchverlauf und Fahrten löschen?", bundle: .module), isPresented: $confirming,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                services.updateUser { try $0.clearHistory() }
                cleared = true
            } label: { Text("Verlauf löschen", bundle: .module) }
        }
        .sheet(isPresented: $showsPolicy) { PolicyText() }
        .sensoryFeedback(KGHaptic.warning, trigger: cleared)
    }

    private func promise(_ icon: KGIcon, _ tint: Color, _ background: Color, _ title: Text, _ detail: Text) -> some View {
        HStack(spacing: KGSpace.mediumLarge) {
            KGIconView(icon, size: 20).foregroundStyle(tint).frame(width: 44, height: 44).background(background, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                title.kgFont(.body.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink)
                detail.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, KGSpace.screen)
        .frame(minHeight: 72)
        .accessibilityElement(children: .combine)
    }
}

/// The privacy policy, bundled so it reads offline.
private struct PolicyText: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KGSpace.medium) {
                    Text("Datenschutzerklärung", bundle: .module).kgFont(.titleL)
                    Text("""
                        KonstanzGo arbeitet vollständig offline. Fahrpläne, Karte und Suche sind in der App enthalten.

                        Wir erheben, speichern und übertragen keine personenbezogenen Daten. Es gibt keine Werbung, \
                        keine Analyse- oder Tracking-Dienste und kein Benutzerkonto.

                        Dein Standort wird nur auf deinem iPhone verwendet, um Haltestellen in deiner Nähe und Wege \
                        zu zeigen. Er verlässt das Gerät nie.

                        Favoriten, Suchverlauf, Alarme und Fahrten werden nur auf deinem iPhone gespeichert. Du \
                        kannst den Verlauf unter Mehr › Datenschutz löschen; beim Löschen der App wird alles entfernt.

                        Abfahrtsalarme sind Mitteilungen, die dein iPhone selbst plant.

                        Kontakt: \(AppInfo.supportEmail)
                        """, bundle: .module)
                        .kgFont(.body).foregroundStyle(KGColor.ink)
                }
                .padding(KGSpace.large)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Fertig", bundle: .module) }
                }
            }
        }
    }
}

/// Über (plan R3): what the app is, that it is not official, data sources and licences.
struct AboutScreen: View {
    let info: TimetableInfo?
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.large) {
                BackLink(title: Text("Mehr", bundle: .module), action: onBack)
                HStack(spacing: KGSpace.medium) {
                    SeeriLogo(size: 56)
                    VStack(alignment: .leading) {
                        Wordmark(size: 28)
                        Text("Version \(AppInfo.version)", bundle: .module).kgFont(.caption).foregroundStyle(KGColor.ink2)
                    }
                }
                Text("KonstanzGo ist keine offizielle App der Stadtwerke Konstanz oder der NVBW.", bundle: .module)
                    .kgFont(.body).foregroundStyle(KGColor.ink)
                KGSectionHeader(Text("Daten", bundle: .module))
                source(Text("Fahrplan", bundle: .module),
                       "\(info?.attribution ?? "Datensatz der NVBW GmbH"), Datenlizenz Deutschland – Namensnennung – Version 2.0")
                source(Text("Karte, Orte und Wege", bundle: .module), "© OpenStreetMap contributors (ODbL), via Protomaps")
                KGSectionHeader(Text("Software", bundle: .module))
                source(Text("Schrift", bundle: .module), "Figtree – SIL Open Font License 1.1")
                source(Text("Karte", bundle: .module), "MapLibre Native – BSD 2-Clause")
                source(Text("Datenbank", bundle: .module), "GRDB.swift – MIT")
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.bottom, KGSpace.large)
        }
        .background(Color.clear)
    }

    private func source(_ title: Text, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.kgFont(.callout).foregroundStyle(KGColor.ink)
            Text(verbatim: detail).kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
        }
        .padding(KGSpace.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.glassFill, in: .kgRounded(KGRadius.medium))
    }
}

/// "‹ Mehr": the blue back link of 18, 24, 25.
struct BackLink: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                KGIconView(.back, size: 22)
                title.kgFont(.bodyMedium)
            }
            .foregroundStyle(KGColor.location)
            .frame(minHeight: KGSize.touch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.leading, -KGSpace.xs)
        .accessibilityIdentifier("backLink")
    }
}
