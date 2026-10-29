import AppIntents
import KGCore
import KGDesign
import SwiftUI
import WidgetKit

struct StopWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Haltestelle"
    static let description = IntentDescription("Die nächsten Abfahrten an einer Haltestelle.")

    @Parameter(title: "Haltestelle")
    var stop: StopEntity?
}

struct StopEntry: TimelineEntry {
    let date: Date
    let stationID: Int?
    let name: String
    let departures: [Departure]
}

/// One entry per departure for the next hours, so the minutes count down with no app or network
/// (plan X3.5).
struct StopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StopEntry {
        StopEntry(date: .now, stationID: nil, name: "Sternenplatz", departures: [])
    }

    func snapshot(for configuration: StopWidgetIntent, in context: Context) async -> StopEntry {
        entries(for: configuration, now: .now).first ?? placeholder(in: context)
    }

    func timeline(for configuration: StopWidgetIntent, in context: Context) async -> Timeline<StopEntry> {
        let entries = entries(for: configuration, now: .now)
        return Timeline(entries: entries, policy: .after(entries.last?.date ?? .now.addingTimeInterval(900)))
    }

    private func entries(for configuration: StopWidgetIntent, now: Date) -> [StopEntry] {
        guard let timetable = WidgetData.timetable,
              let station = configuration.stop.flatMap({ timetable.station(id: $0.id) }) ?? WidgetData.defaultStation
        else { return [StopEntry(date: now, stationID: nil, name: "KonstanzGo", departures: [])] }
        let upcoming = (try? timetable.departures(at: station.id, from: now, limit: 24, within: 4)) ?? []
        var result = [StopEntry(date: now, stationID: station.id, name: station.shortName,
                                departures: Array(upcoming.prefix(3)))]
        for (index, departure) in upcoming.enumerated() where index < 20 {
            let after = departure.scheduled.addingTimeInterval(60)
            result.append(StopEntry(date: after, stationID: station.id, name: station.shortName,
                                    departures: Array(upcoming.dropFirst(index + 1).prefix(3))))
        }
        return result
    }
}

/// "Haltestelle" (medium): the stop and its next three buses (screen 26).
struct StopWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "stop", intent: StopWidgetIntent.self, provider: StopProvider()) { entry in
            StopWidgetView(entry: entry)
                .containerBackground(KGColor.surface, for: .widget)
                .widgetURL(entry.stationID.map { URL(string: "konstanzgo://stop/\($0)") } ?? nil)
        }
        .configurationDisplayName(Text("Haltestelle"))
        .description(Text("Die nächsten Abfahrten an einer Haltestelle."))
        .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct StopWidgetView: View {
    let entry: StopEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.departures.first {
                Text("\(next.line.name) \(next.headsign) · \(next.scheduled, style: .relative)")
            } else {
                Text(entry.name)
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(entry.departures.first?.line.name ?? "–").font(.headline)
                if let next = entry.departures.first {
                    Text(next.scheduled, style: .timer).font(.caption2).multilineTextAlignment(.center)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.headline).lineLimit(1)
                ForEach(entry.departures.prefix(2)) { departure in
                    HStack {
                        Text("\(departure.line.name) \(departure.headsign)").lineLimit(1)
                        Spacer()
                        Text(departure.scheduled, style: .relative).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        default:
            medium
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: entry.name).kgFont(.bodyStrong).foregroundStyle(KGColor.ink).lineLimit(1)
                Spacer()
                SeeriLogo(size: 22)
            }
            if entry.departures.isEmpty {
                Spacer()
                Text("Heute fährt hier nichts mehr.").kgFont(.footnote).foregroundStyle(KGColor.ink2)
                Spacer()
            } else {
                ForEach(entry.departures) { departure in
                    HStack(spacing: 8) {
                        KGLineBadge(departure.line.name, size: .small)
                        Text(verbatim: departure.headsign).kgFont(.footnote.weighted(KGFont.medium))
                            .foregroundStyle(KGColor.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(departure.scheduled, style: .relative)
                            .kgFont(.footnote.weighted(KGFont.extraBold)).monospacedDigit()
                            .foregroundStyle(KGColor.ink).multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80, alignment: .trailing)
                    }
                    .frame(minHeight: 26)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
