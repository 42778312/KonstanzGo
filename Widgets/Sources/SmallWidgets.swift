import KGCore
import KGDesign
import SwiftUI
import WidgetKit

// MARK: Nach Hause (small, X3.2)

struct HomeEntry: TimelineEntry {
    let date: Date
    /// nil: no home set; empty name: nothing runs.
    let line: String?
    let from: String?
    let departure: Date?
    let minutes: Int?
    let hasHome: Bool
}

/// The next direct bus from a saved stop to the stop nearest home.
struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: .now, line: "1", from: "Sternenplatz", departure: .now.addingTimeInterval(360), minutes: 18,
                  hasHome: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(entry(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let now = Date.now
        let first = entry(now: now)
        let next = first.departure.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [first], policy: .after(next)))
    }

    private func entry(now: Date) -> HomeEntry {
        guard let timetable = WidgetData.timetable, let home = try? WidgetData.user?.slot(.home) else {
            return HomeEntry(date: now, line: nil, from: nil, departure: nil, minutes: nil, hasHome: false)
        }
        guard let target = timetable.stations(near: home.target.coordinate, within: 1_500, limit: 1).first?.0 else {
            return HomeEntry(date: now, line: nil, from: nil, departure: nil, minutes: nil, hasHome: true)
        }
        let starts = ((try? WidgetData.user?.favorites()) ?? []).compactMap { favorite -> Int? in
            if case let .station(id, _, _) = favorite.target, id != target.id { return id }
            return nil
        }
        let best = starts.compactMap { start in try? timetable.nextDirectDeparture(from: start, to: target.id, after: now) }
            .min { $0.arrival < $1.arrival }
        guard let best else {
            return HomeEntry(date: now, line: nil, from: nil, departure: nil, minutes: nil, hasHome: true)
        }
        let minutes = Int((best.arrival.timeIntervalSince(best.departure.scheduled) / 60).rounded())
        return HomeEntry(date: now, line: best.departure.line.name,
                         from: timetable.station(id: best.departure.platform.stationID)?.shortName,
                         departure: best.departure.scheduled, minutes: minutes, hasHome: true)
    }
}

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "home", provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(KGColor.surface, for: .widget)
                .widgetURL(URL(string: "konstanzgo://route/home"))
        }
        .configurationDisplayName(Text("Nach Hause"))
        .description(Text("Der nächste Bus von deinen Haltestellen nach Hause."))
        .supportedFamilies([.systemSmall])
    }
}

struct HomeWidgetView: View {
    let entry: HomeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                KGIconView(.home, size: 14).foregroundStyle(KGColor.location)
                    .frame(width: 26, height: 26).background(KGColor.locationTint, in: .circle)
                Text("Nach Hause").kgFont(.callout.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink)
            }
            Spacer(minLength: 0)
            if let line = entry.line, let minutes = entry.minutes, let departure = entry.departure {
                Text("\(minutes) Min.").kgFont(.title.weighted(KGFont.bold)).foregroundStyle(KGColor.ink)
                HStack(spacing: 4) {
                    KGLineBadge(line, size: .small)
                    Text("ab \(departure, style: .time)").kgFont(.caption.weighted(KGFont.semiBold))
                        .foregroundStyle(KGColor.ink2)
                }
                if let from = entry.from {
                    Text(verbatim: from).kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        .lineLimit(1)
                }
            } else {
                Text(entry.hasHome ? "Gerade fährt kein Bus nach Hause." : "Lege in der App dein Zuhause fest.")
                    .kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Fahrten (small, X3.3)

struct TripsEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct TripsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripsEntry { TripsEntry(date: .now, count: 5) }

    func getSnapshot(in context: Context, completion: @escaping (TripsEntry) -> Void) {
        completion(TripsEntry(date: .now, count: (try? WidgetData.user?.tripsThisWeek()) ?? 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripsEntry>) -> Void) {
        let entry = TripsEntry(date: .now, count: (try? WidgetData.user?.tripsThisWeek()) ?? 0)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct TripsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "trips", provider: TripsProvider()) { entry in
            VStack(spacing: 6) {
                Seeri(entry.count >= 1 ? .joyful : .happy).frame(width: 64, height: 68)
                Text("\(entry.count) Fahrten").kgFont(.bodyStrong.weighted(KGFont.extraBold)).foregroundStyle(KGColor.ink)
                Text("diese Woche").kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .containerBackground(KGColor.surface, for: .widget)
        }
        .configurationDisplayName(Text("Fahrten"))
        .description(Text("Wie oft du diese Woche mit Seeri gefahren bist."))
        .supportedFamilies([.systemSmall])
    }
}
