import AppIntents
import KGCore
import KGDesign
import KGFeatures
import SwiftUI

/// "Wann kommt mein Bus?": the next bus at the first saved stop, spoken and as a card (plan X4.1, X4.3).
struct NextBusIntent: AppIntent {
    static let title: LocalizedStringResource = "Wann kommt mein Bus?"
    static let description = IntentDescription("Sagt dir, wann der nächste Bus an deiner Haltestelle kommt.")

    @Parameter(title: "Haltestelle")
    var stop: StopEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let timetable = WidgetData.timetable,
              let station = stop.flatMap({ timetable.station(id: $0.id) }) ?? WidgetData.defaultStation else {
            return .result(dialog: "Ich finde gerade keine Haltestelle.", view: EmptyView().eraseToAny())
        }
        let departures = (try? timetable.departures(at: station.id, from: .now, limit: 3)) ?? []
        guard let next = departures.first else {
            return .result(dialog: "An \(station.shortName) fährt heute nichts mehr.", view: EmptyView().eraseToAny())
        }
        let minutes = max(0, Int(next.scheduled.timeIntervalSinceNow / 60))
        let dialog: IntentDialog = minutes == 0
            ? "Dein Bus \(next.line.name) fährt jetzt an der Haltestelle \(station.shortName)."
            : "Dein Bus \(next.line.name) kommt in \(minutes) Minuten an der Haltestelle \(station.shortName)."
        return .result(dialog: dialog, view: NextBusSnippet(station: station.shortName, departures: departures).eraseToAny())
    }
}

/// "Abfahrten an <Haltestelle>" opens the stop in the app (X4.1).
struct OpenStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Abfahrten an einer Haltestelle"
    static let openAppWhenRun = true

    @Parameter(title: "Haltestelle")
    var stop: StopEntity

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        DeepLink.pending = URL(string: "konstanzgo://stop/\(stop.id)")
        return .result()
    }
}

/// "Bus nach Hause" / "Weg zur Uni": opens the connections there (X4.1).
struct RouteToSlotIntent: AppIntent {
    static let title: LocalizedStringResource = "Bus nach Hause"
    static let openAppWhenRun = true

    @Parameter(title: "Ziel", default: .home)
    var slot: SlotEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.pending = URL(string: "konstanzgo://route/\(slot.rawValue)")
        return .result()
    }
}

enum SlotEntity: String, AppEnum {
    case home, work, uni

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ziel"
    static let caseDisplayRepresentations: [SlotEntity: DisplayRepresentation] = [
        .home: "Zuhause", .work: "Arbeit", .uni: "Uni",
    ]
}

/// Phrases that work without setup, German and English (X4.2).
struct KonstanzGoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextBusIntent(), phrases: [
            "Wann kommt mein Bus mit \(.applicationName)?",
            "Nächster Bus mit \(.applicationName)",
            "When is my bus in \(.applicationName)?",
        ], shortTitle: "Nächster Bus", systemImageName: "bus")
        AppShortcut(intent: RouteToSlotIntent(), phrases: [
            "Bus nach Hause mit \(.applicationName)",
            "\(.applicationName) nach Hause",
            "Bus home with \(.applicationName)",
        ], shortTitle: "Nach Hause", systemImageName: "house")
        AppShortcut(intent: OpenStopIntent(), phrases: [
            "Abfahrten an \(\.$stop) in \(.applicationName)",
            "Departures at \(\.$stop) in \(.applicationName)",
        ], shortTitle: "Abfahrten", systemImageName: "clock")
    }
}

/// The card Siri shows: "Sternenplatz" and the next buses (screen 27).
private struct NextBusSnippet: View {
    let station: String
    let departures: [Departure]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SeeriLogo(size: 26)
                Text(verbatim: station).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
            }
            ForEach(departures) { departure in
                HStack(spacing: 8) {
                    KGLineBadge(departure.line.name, size: .small)
                    Text(verbatim: departure.headsign).kgFont(.footnote).foregroundStyle(KGColor.ink).lineLimit(1)
                    Spacer()
                    Text(departure.scheduled, style: .relative).kgFont(.footnote.weighted(KGFont.extraBold))
                        .monospacedDigit().foregroundStyle(KGColor.ink)
                }
            }
        }
        .padding()
    }
}

/// Hands a link from an intent to the running app.
@MainActor
enum DeepLink {
    static var pending: URL? {
        didSet { if let pending { NotificationCenter.default.post(name: .kgDeepLink, object: pending) } }
    }
}

extension View {
    func eraseToAny() -> AnyView { AnyView(self) }
}
