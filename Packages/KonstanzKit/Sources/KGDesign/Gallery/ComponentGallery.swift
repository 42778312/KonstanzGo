import SwiftUI

/// Every component in its states, filled with the design's own examples (plan A8, Part B). Split in parts so
/// each snapshot stays a readable size.
public struct ComponentGallery: View {
    public enum Part: String, CaseIterable, Sendable {
        case buttons, transit, controls, journey, feedback, map
    }

    let part: Part

    public init(_ part: Part) {
        self.part = part
    }

    /// Wed 28 Oct 2026 14:18 in Konstanz, the moment the design's numbers are true.
    static let now: Date = {
        var parts = DateComponents(year: 2026, month: 10, day: 28, hour: 14, minute: 18)
        parts.timeZone = TimeZone(identifier: "Europe/Berlin")
        return Calendar.kgKonstanz.date(from: parts) ?? .distantPast
    }()

    static func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    public var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.large) {
            switch part {
            case .buttons: ButtonsPart()
            case .transit: TransitPart()
            case .controls: ControlsPart()
            case .journey: JourneyPart()
            case .feedback: FeedbackPart()
            case .map: MapPart()
            }
        }
        .padding(KGSpace.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.card)
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(verbatim: text).kgFont(.caption).foregroundStyle(KGColor.ink3) }
}

private struct ButtonsPart: View {
    var body: some View {
        Caption("Primär · Laden · Deaktiviert")
        KGButton(Text(verbatim: "Los geht's")) {}
        KGButton(Text(verbatim: "Alarm stellen"), icon: .bell) {}
        KGButton(Text(verbatim: "Jetzt suchen"), isLoading: true) {}
        KGButton(Text(verbatim: "Losfahren")) {}.disabled(true)
        Caption("Sekundär · Umriss")
        KGButton(Text(verbatim: "Neue Suche"), kind: .secondary) {}
        HStack(spacing: KGSpace.compact) {
            KGButton(Text(verbatim: "Merken"), icon: .star, kind: .outline) {}
            KGButton(Text(verbatim: "Teilen"), icon: .share, kind: .outline) {}
        }
        Caption("Chips · Rund · Text")
        HStack(spacing: KGSpace.small) {
            KGChip(Text(verbatim: "Jetzt"), isOn: true) {}
            KGChip(Text(verbatim: "Später")) {}
            KGChip(Text(verbatim: "Barrierefrei"), icon: .accessibility) {}
        }
        HStack(spacing: KGSpace.medium) {
            KGRoundIconButton(.back, label: Text(verbatim: "Zurück")) {}
            KGRoundIconButton(.star, label: Text(verbatim: "Favorit")) {}
            KGRoundIconButton(.swap, label: Text(verbatim: "Tauschen"), surface: .plain) {}
            KGRoundIconButton(.close, label: Text(verbatim: "Schließen"), surface: .plain) {}
            KGTextButton(Text(verbatim: "Alle")) {}
        }
    }
}

private struct TransitPart: View {
    let now = ComponentGallery.now

    var body: some View {
        Caption("Linien S · M · L · Kachel")
        HStack(spacing: KGSpace.small) {
            ForEach(KGLineBadge.Size.allCases, id: \.self) { KGLineBadge("9A", size: $0) }
            KGLineBadge("1")
            KGLineBadge("13/4")
        }
        Caption("Minuten · Fuß · Status · Tags")
        HStack(spacing: KGSpace.medium) {
            KGMinutes(ComponentGallery.at(0.5), now: now)
            KGMinutes(ComponentGallery.at(3), now: now)
            KGMinutes(ComponentGallery.at(75), now: now)
            KGLiveDot()
            KGMinutes(ComponentGallery.at(3), now: now, isLive: true)
            KGWalkChip(minutes: 2)
        }
        HStack(spacing: KGSpace.small) {
            KGStatusPill(Text(verbatim: "Offline bereit"))
            KGStatusPill(Text(verbatim: "Fahrplan endet bald"), isWarning: true)
        }
        HStack(spacing: KGSpace.small) {
            KGTag(Text(verbatim: "Schnellste"))
            KGTag(Text(verbatim: "Wenig laufen"), tone: .live)
            KGTag(Text(verbatim: "Geschätzt"), tone: .neutral)
        }
        Caption("Haltestelle (07)")
        KGStopCard(name: "Sternenplatz", walkMinutes: 2, departures: [
            KGDepartureItem(id: "a", line: "9A", destination: "Universität", departure: ComponentGallery.at(3)),
            KGDepartureItem(id: "b", line: "1", destination: "Staad", departure: ComponentGallery.at(6)),
            KGDepartureItem(id: "c", line: "5", destination: "Petershausen", departure: ComponentGallery.at(11)),
        ], now: now)
        Caption("Abfahrten (09)")
        VStack(spacing: 0) {
            KGDepartureRow(line: "9A", destination: "Universität", platform: "A", departure: ComponentGallery.at(3),
                           now: now, style: .large)
            Rectangle().fill(KGColor.line).frame(height: 1)
            KGDepartureRow(line: "1", destination: "Staad", platform: "B", departure: ComponentGallery.at(6),
                           now: now, style: .large)
            Rectangle().fill(KGColor.line).frame(height: 1)
            KGDepartureRow(line: "5", destination: "Petershausen", departure: ComponentGallery.at(72),
                           now: now, style: .large)
        }
        .padding(.horizontal, KGSpace.large)
        .background(KGColor.surface, in: .kgRounded(KGRadius.card))
    }
}

private struct ControlsPart: View {
    @State private var view = 0
    @State private var mode = 1
    @State private var prefer = 0
    @State private var notifications = true
    @State private var accessible = false
    @State private var search = "Uni"
    @State private var date = ComponentGallery.at(42)

    var body: some View {
        Caption("Suche (07, 08)")
        KGMapSearchBar {}
        KGSearchField(text: $search) {}
        Caption("Umschalter (09, 19)")
        KGSegmentedControl(selection: $view, options: [(0, Text(verbatim: "Abfahrten")), (1, Text(verbatim: "Linien"))])
        KGSegmentedControl(selection: $mode, options: [(0, Text(verbatim: "Jetzt")), (1, Text(verbatim: "Abfahrt")),
                                                       (2, Text(verbatim: "Ankunft"))], size: .large)
        Caption("Wann (19)")
        KGTimeWheel(date: $date, today: ComponentGallery.now)
            .background(KGColor.surface, in: .kgRounded(KGRadius.card))
        KGSectionHeader(Text(verbatim: "Bevorzugen"))
        KGOptionCard(Text(verbatim: "Schnellste"), subtitle: Text(verbatim: "Früheste Ankunft"),
                     isSelected: prefer == 0) { prefer = 0 }
        KGOptionCard(Text(verbatim: "Wenig laufen"), subtitle: Text(verbatim: "Kürzere Fußwege"),
                     isSelected: prefer == 1) { prefer = 1 }
        KGToggleRow(Text(verbatim: "Barrierefrei"), isOn: $accessible, strong: true)
        Caption("Einstellungen (13)")
        KGSettingsGroup {
            KGSettingsRow(Text(verbatim: "Mitteilungen"), icon: .bell, tile: KGColor.tileRed, isOn: $notifications)
            KGSettingsRow(Text(verbatim: "Abfahrtsalarm"), icon: .timer, tile: KGColor.warn,
                          value: Text(verbatim: "2 Min. vorher")) {}
            KGSettingsRow(Text(verbatim: "Sprache"), icon: .globe, tile: KGColor.tileIndigo,
                          value: Text(verbatim: "Deutsch")) {}
            KGSettingsRow(Text(verbatim: "Darstellung"), icon: .appearance, tile: KGColor.tileBlack,
                          value: Text(verbatim: "Automatisch")) {}
            KGSettingsRow(Text(verbatim: "Datenschutz"), icon: .shield, tile: KGColor.live) {}
        }
        Caption("Onboarding (03)")
        KGStepProgress(step: 2, of: 4)
    }
}

private struct JourneyPart: View {
    @State private var tab = 0

    var body: some View {
        Caption("Verbindungen (10)")
        KGRouteCard(departure: ComponentGallery.at(3), arrival: ComponentGallery.at(17),
                    tag: (Text(verbatim: "Schnellste"), .line),
                    legs: [.walk(minutes: 2), .bus(line: "9A"), .walk(minutes: 1)],
                    note: Text(verbatim: "Fährt in 3 Min. ab Sternenplatz"), isSelected: true) {}
        KGRouteCard(departure: ComponentGallery.at(6), arrival: ComponentGallery.at(24),
                    legs: [.walk(minutes: 4), .bus(line: "1"), .bus(line: "5")],
                    note: Text(verbatim: "1× Umsteigen · ab Bahnhof")) {}
        Caption("Haltestellen (11)")
        KGTimeline(progress: 0.3) {
            VStack(spacing: 0) {
                KGTimelineStop("Sternenplatz", time: ComponentGallery.at(3), state: .past)
                KGTimelineStop("Petershausen", time: ComponentGallery.at(6), state: .current)
                KGTimelineStop("Jahnstraße", time: ComponentGallery.at(9), state: .coming)
                KGTimelineStop("Egg", time: ComponentGallery.at(13), state: .coming)
                KGTimelineStop("Universität", time: ComponentGallery.at(17), state: .last)
            }
        }
        .padding(.horizontal, KGSpace.screen)
        .padding(.vertical, KGSpace.xs)
        .background(KGColor.surface, in: .kgRounded(KGRadius.cardLarge))
        Caption("Tab-Leiste (07)")
        KGFloatingTabBar(selection: $tab, tabs: [
            KGTab(id: 0, title: Text(verbatim: "Karte"), icon: .map),
            KGTab(id: 1, title: Text(verbatim: "Favoriten"), icon: .star),
            KGTab(id: 2, title: Text(verbatim: "Einstellungen"), icon: .more),
        ])
        .frame(maxWidth: .infinity)
    }
}

private struct FeedbackPart: View {
    var body: some View {
        Caption("Sprechblasen (02, 22)")
        KGSpeechBubble(Text(verbatim: "Hallo, ich bin Seeri und bring dich durch ganz Konstanz."))
            .frame(maxWidth: .infinity)
        KGSpeechBubble(Text(verbatim: "Ich warte an Steig D"), size: .small)
        Caption("Hinweis")
        KGToast(Text(verbatim: "Verlauf gelöscht")) {}
            .frame(maxWidth: .infinity)
        Caption("Leer (23)")
        KGSheetSurface {
            KGEmptyState(.sleepy, title: Text(verbatim: "Keine Verbindung gefunden"),
                         message: Text(verbatim:
                             "Um 01:30 fährt leider kein Bus zur Insel Mainau. Seeri schläft gerade."),
                         hint: Text(verbatim: "Erster Bus 05:42")) {
                KGButton(Text(verbatim: "Ziel ändern"), kind: .secondary) {}
                KGButton(Text(verbatim: "Andere Zeit wählen")) {}
            }
            .padding(.bottom, KGSpace.xl)
        }
    }
}

private struct MapPart: View {
    var body: some View {
        Caption("Karte (07, 09)")
        ZStack(alignment: .topTrailing) {
            KGColor.mapLand
            HStack(alignment: .center, spacing: KGSpace.xl) {
                VStack(spacing: KGSpace.xl) {
                    KGBusMarker(line: "9A", heading: .degrees(70), animated: false)
                    KGBusMarker(line: "1", animated: false)
                }
                KGUserDot(heading: .degrees(30))
                VStack(spacing: KGSpace.small) {
                    KGStopMarker("Bahnhof")
                    KGStopMarker("Sternenplatz", isSelected: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(KGSpace.large)
            KGMapControls(onLayers: {}, onLocate: {}).padding(KGSpace.screen)
        }
        .frame(height: 260)
        .clipShape(.kgRounded(KGRadius.card))
        Caption("Blatt (07)")
        KGSheetSurface {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "In deiner Nähe").kgFont(.title).foregroundStyle(KGColor.ink)
                    Spacer()
                    KGTextButton(Text(verbatim: "Alle")) {}
                }
                KGStopCard(name: "Sternenplatz", walkMinutes: 2, departures: [
                    KGDepartureItem(id: "a", line: "9A", destination: "Universität", departure: ComponentGallery.at(3)),
                ], now: ComponentGallery.now)
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.bottom, KGSpace.large)
        }
    }
}

#Preview("Components") {
    ScrollView {
        ForEach(ComponentGallery.Part.allCases, id: \.self) { ComponentGallery($0) }
    }
}
