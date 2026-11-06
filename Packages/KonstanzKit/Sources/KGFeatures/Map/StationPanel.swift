import KGCore
import KGDesign
import SwiftUI

/// A stop tapped on the map: name, platforms and walk, star and ✕; the lines as chips that scroll sideways;
/// the time to look from; the departures (time, line, destination, platform), each opening its trip.
struct StationPanel: View {
    let services: AppServices
    let station: Station
    let onClose: () -> Void
    /// Opens another stop (the alternatives to a closed one).
    var onStation: (Int) -> Void = { _ in }
    /// Departures from this moment instead of now (the intro at night, when nothing runs).
    var start: Date?
    @State private var lines: [Line] = []
    @State private var line: Line.ID?
    @State private var from = Date.now
    @State private var departures: [Departure] = []
    @State private var choosingTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let closure = services.live.notices(forStation: station.id).first(where: \.closesStops) {
                ClosureBanner(services: services, notice: closure, onStation: onStation).padding(.top, KGSpace.small)
            }
            lineChips.padding(.top, KGSpace.medium)
            HStack {
                Button { choosingTime = true } label: {
                    HStack(spacing: KGSpace.xs) {
                        KGIconView(.clock, size: 16)
                        timeTitle.kgFont(.callout.weighted(KGFont.bold))
                        KGIconView(.chevronRight, size: 12).rotationEffect(.degrees(90))
                    }
                    .foregroundStyle(KGColor.ink)
                    .padding(.horizontal, KGSpace.medium)
                    .frame(minHeight: 36)
                    .kgGlassCard(in: .kgRounded(KGRadius.compact))
                }
                .buttonStyle(KGPressStyle())
                .accessibilityIdentifier("stationTime")
                Spacer()
                // Honest about what the times are (plan 0.3).
                if departures.contains(where: \.status.isLive) {
                    HStack(spacing: KGSpace.xxs) {
                        Circle().fill(KGColor.live).frame(width: 8, height: 8)
                        Text("Live", bundle: .module)
                    }
                    .kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.live)
                    .accessibilityIdentifier("liveTimes")
                } else {
                    Label { Text("Fahrplanzeiten", bundle: .module) } icon: { KGIconView(.timer, size: 13) }
                        .kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.ink2)
                }
            }
            .padding(.top, KGSpace.medium)
            list
        }
        .padding(.horizontal, KGSpace.large)
        .task(id: station.id) {
            lines = (try? services.transit.lines(at: station.id)) ?? []
            line = nil
            from = start ?? .now
        }
        .task(id: "\(station.id)|\(line ?? -1)|\(from.timeIntervalSince1970)") { await followDepartures() }
        .sheet(isPresented: $choosingTime) { TimeSheet(date: $from) }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: KGSpace.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: station.shortName).kgFont(.title).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle).kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            Spacer()
            FavoriteButton(services: services,
                           target: .station(id: station.id, name: station.shortName, coordinate: station.coordinate))
            KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain, action: onClose)
                .accessibilityIdentifier("closeStation")
        }
    }

    /// "Haltestelle · Steige A–F · 2 Min. zu Fuß".
    private var subtitle: String {
        var parts = [String(localized: "Haltestelle", bundle: .module)]
        let codes = services.transit.store.platforms(of: station.id).compactMap(\.code).sorted()
        if let first = codes.first, let last = codes.last {
            parts.append(first == last ? String(localized: "Steig \(first)", bundle: .module)
                                       : String(localized: "Steige \(first)–\(last)", bundle: .module))
        }
        if services.here != nil {
            let minutes = max(1, Int((station.coordinate.distance(to: services.anchor) * 1.25 / 80).rounded(.up)))
            parts.append(String(localized: "\(minutes) Min. zu Fuß", bundle: .module))
        }
        return parts.joined(separator: " · ")
    }

    /// "Alle Linien", "Linie 1", "Linie 5" …: one chosen, scrolls sideways when there are many.
    private var lineChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: KGSpace.small) {
                KGChip(Text("Alle Linien", bundle: .module), isOn: line == nil) { line = nil }
                ForEach(lines) { item in
                    KGChip(Text("Linie \(item.name)", bundle: .module), isOn: line == item.id) { line = item.id }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("lineChips")
    }

    private var timeTitle: Text {
        let calendar = Calendar.konstanz
        let day = calendar.isDateInToday(from) ? String(localized: "Heute", bundle: .module)
            : calendar.isDateInTomorrow(from) ? String(localized: "Morgen", bundle: .module) : KGStrings.shortDay(from)
        return Text("\(day) ab \(KGStrings.clock(from))", bundle: .module)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if departures.isEmpty {
                    (services.transit.timetableInfo?.validity() == .ended
                        ? Text("Der Fahrplan ist abgelaufen", bundle: .module)
                        : Text("Keine Abfahrt in den nächsten Stunden.", bundle: .module))
                        .kgFont(.body).foregroundStyle(KGColor.ink2)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                ForEach(Array(departures.enumerated()), id: \.element.id) { index, departure in
                    Button {
                        services.sheetRequest = .trip(tripID: departure.tripID, day: ServiceDay(departure.scheduled),
                                                      fromStation: station.id)
                    } label: {
                        row(departure)
                    }
                    .buttonStyle(KGRowPressStyle())
                    .overlay(alignment: .bottom) {
                        if index < departures.count - 1 { Rectangle().fill(KGColor.line).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, KGSpace.medium)
            .kgGlassCard(in: .kgRounded(KGRadius.card))
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, KGSpace.medium, for: .scrollContent)
        .padding(.top, KGSpace.xs)
    }

    private func row(_ departure: Departure) -> some View {
        HStack(spacing: KGSpace.medium) {
            DepartureTime(departure: departure).frame(minWidth: 50, alignment: .leading)
            KGLineBadge(departure.line.name, size: .small)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: departure.headsign).kgFont(.bodyStrong)
                    .foregroundStyle(departure.isOff ? KGColor.ink2 : KGColor.ink).lineLimit(1)
                if let reason = departure.offReason {
                    reason.kgFont(.caption).foregroundStyle(KGColor.coral).lineLimit(1)
                } else if let detail = detail(departure) {
                    Text(verbatim: detail).kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            KGIconView(.chevronRight, size: 13).foregroundStyle(KGColor.chevron)
        }
        .frame(minHeight: 62)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KGStrings.departure(line: departure.line.name, destination: departure.headsign,
                                                platform: departure.platform.code,
                                                minutes: KGMinutesValue(departure: departure.expected, now: .now),
                                                isLive: departure.status.isLive)
                            + ", " + KGStrings.clock(departure.expected))
    }

    /// "Richtung Bahnhof · Steig B". The timetable stores the direction in English ("Towards Bahnhof",
    /// plan D10); the place name is kept and the word follows the app's language.
    private func detail(_ departure: Departure) -> String? {
        let direction = departure.platform.direction.map { text -> String in
            switch text {
            case "Towards city centre": return String(localized: "Richtung Zentrum", bundle: .module)
            case "Out of town": return String(localized: "Stadtauswärts", bundle: .module)
            case let text where text.hasPrefix("Towards "):
                return String(localized: "Richtung \(String(text.dropFirst("Towards ".count)))", bundle: .module)
            default: return text
            }
        }
        let parts = [direction, departure.platform.code.map {
            String(localized: "Steig \($0)", bundle: .module)
        }].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() -> [Departure] {
        let start = max(from, min(.now, from.addingTimeInterval(3600)))
        let all = (try? services.transit.departures(at: station.id, from: start, limit: 60)) ?? []
        return Array(all.filter { line == nil || $0.line.id == line }.prefix(30))
    }

    /// The timetable at once; then, for departures around now, what's really happening, every 30 s.
    private func followDepartures() async {
        // The real times at once, from what's already known; fresher ones replace them a moment later.
        departures = services.live.instant(load())
        guard abs(from.timeIntervalSinceNow) < 3600 else { return }
        while !Task.isCancelled {
            let shown = await services.live.live(load(), atStation: station.id)
            guard !Task.isCancelled else { return }
            withAnimation(KGMotion.pop) { departures = shown }
            try? await Task.sleep(for: .seconds(30))
        }
    }
}

extension Departure {
    /// This bus won't come to this stop.
    var isOff: Bool { status == .stopClosed || status == .cancelled }

    var offReason: Text? {
        switch status {
        case .stopClosed: Text("Hält hier gerade nicht", bundle: .module)
        case .cancelled: Text("Fällt aus", bundle: .module)
        case .scheduled, .live: nil
        }
    }
}

/// When the bus comes: the timetable time, struck through under the real one when it's late.
private struct DepartureTime: View {
    let departure: Departure

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: KGStrings.clock(departure.expected)).kgFont(.minutes)
                .strikethrough(departure.isOff)
                .foregroundStyle(departure.isOff ? KGColor.ink3
                    : departure.status.delayMinutes > 0 ? KGColor.warn
                    : departure.status.isLive ? KGColor.live : KGColor.ink)
                .contentTransition(.numericText())
            if departure.status.delayMinutes > 0 {
                Text(verbatim: KGStrings.clock(departure.scheduled)).kgFont(.caption.weighted(KGFont.regular))
                    .strikethrough().foregroundStyle(KGColor.ink3)
            }
        }
    }
}

/// Choosing the time a stop's departures start from: what's chosen in large type, shortcuts for the usual choices,
/// day and time wheels for the rest.
private struct TimeSheet: View {
    @Binding var date: Date
    @State private var draft: Date
    @Environment(\.dismiss) private var dismiss

    init(date: Binding<Date>) {
        _date = date
        _draft = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abfahrten ab", bundle: .module).kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    Text(verbatim: chosen).kgFont(.titleL.sized(30)).monospacedDigit().foregroundStyle(KGColor.ink)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("chosenTime")
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain) { dismiss() }
            }
            shortcuts
            KGTimeWheel(date: $draft.animation(KGMotion.pop), today: .now, daysBack: 0)
            HStack(spacing: KGSpace.compact) {
                KGButton(Text("Jetzt", bundle: .module), kind: .secondary) {
                    date = .now
                    dismiss()
                }
                .frame(maxWidth: 120)
                KGButton(Text("Abfahrten zeigen", bundle: .module)) {
                    date = draft
                    dismiss()
                }
                .accessibilityIdentifier("applyTime")
            }
        }
        .padding(.horizontal, KGSpace.large)
        .padding(.top, KGSpace.large)
        .padding(.bottom, KGSpace.compact)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .kgGlassSheet()
        .presentationCornerRadius(KGRadius.card)
    }

    /// "Heute, 17:30".
    private var chosen: String {
        let calendar = Calendar.konstanz
        let day = calendar.isDateInToday(draft) ? String(localized: "Heute", bundle: .module)
            : calendar.isDateInTomorrow(draft) ? String(localized: "Morgen", bundle: .module) : KGStrings.shortDay(draft)
        return "\(day), \(KGStrings.clock(draft))"
    }

    private var shortcuts: some View {
        let calendar = Calendar.konstanz
        let soon = calendar.dateInterval(of: .minute, for: .now)?.start ?? .now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now).flatMap {
            calendar.date(bySettingHour: 7, minute: 0, second: 0, of: $0)
        } ?? soon
        return ScrollView(.horizontal) {
            HStack(spacing: KGSpace.small) {
                shortcut(Text("In 15 Min.", bundle: .module), soon.addingTimeInterval(15 * 60))
                shortcut(Text("In 30 Min.", bundle: .module), soon.addingTimeInterval(30 * 60))
                shortcut(Text("In 1 Std.", bundle: .module), soon.addingTimeInterval(60 * 60))
                shortcut(Text("Morgen früh", bundle: .module), tomorrow)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func shortcut(_ title: Text, _ time: Date) -> some View {
        KGChip(title, isOn: abs(draft.timeIntervalSince(time)) < 60) {
            withAnimation(KGMotion.slide) { draft = time }
        }
        .sensoryFeedback(KGHaptic.selection, trigger: draft)
    }
}
