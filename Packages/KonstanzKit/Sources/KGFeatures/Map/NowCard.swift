import KGCore
import KGDesign
import SwiftUI

/// "Jetzt": the next buses at the nearest and saved stops, and when to leave for them, with no taps. It floats over
/// the map above the search bar, so the map stays the main view, and folds away when the user wants the map alone.
struct NowCard: View {
    let services: AppServices
    let onStop: (Int) -> Void
    /// The card's height, for what must sit above it.
    let onHeight: (CGFloat) -> Void
    @AppStorage("now.folded") private var folded = false
    @State private var candidates: [NowCandidate] = []
    @State private var stops: [NowStop] = []
    @State private var loaded = false
    @State private var now = Date.now

    /// A new position (about 50 m), a change to saved stops or coming back to the app starts again.
    private struct Trigger: Hashable {
        var latitude: Int?
        var longitude: Int?
        var saved: Int
        var active: Bool
    }

    private var trigger: Trigger {
        let point = services.here?.coordinate
        return Trigger(latitude: point.map { Int($0.latitude * 2_000) }, longitude: point.map { Int($0.longitude * 3_000) },
                       saved: services.userVersion, active: services.isActive)
    }

    var body: some View {
        Group {
            if services.transit.timetableInfo?.validity() == .ended {
                EmptyView()
            } else if folded {
                foldedPill
            } else if !stops.isEmpty {
                card
            } else if loaded, let hint {
                hint
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        .task(id: trigger) { await follow() }
        .animation(KGMotion.pop, value: folded)
    }

    // MARK: Data

    private var savedStops: [Int] {
        ((try? services.user?.favorites()) ?? []).compactMap {
            if case let .station(id, _, _) = $0.target { id } else { nil }
        }
    }

    /// The timetable first; then, while the app is in front, what's really happening. The minutes and the
    /// advice move on with the clock in between.
    private func follow() async {
        guard services.isActive else { return }
        let transit = services.transit, point = services.here?.coordinate, saved = savedStops
        let found = await Task.detached(priority: .userInitiated) {
            NowBoard.candidates(in: transit, near: point, saved: saved, at: .now, walker: transit.walker)
        }.value
        guard !Task.isCancelled else { return }
        candidates = found.map { candidate in
            var known = candidate
            known.departures = services.live.instant(candidate.departures)
            return known
        }
        refresh()
        loaded = true
        var tick = 0
        while !Task.isCancelled {
            if tick % 2 == 0, !folded { await readLive() }
            guard !Task.isCancelled else { return }
            refresh()
            tick += 1
            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func readLive() async {
        let shown = Set(stops.map(\.id))
        for index in candidates.indices where shown.contains(candidates[index].station.id) {
            let fresh = await services.live.live(candidates[index].departures, atStation: candidates[index].station.id)
            guard !Task.isCancelled, index < candidates.count else { return }
            candidates[index].departures = fresh
        }
    }

    private func refresh() {
        now = .now
        withAnimation(KGMotion.pop) { stops = NowBoard.stops(from: candidates, now: now) }
    }

    // MARK: Views

    private var foldedPill: some View {
        Button { folded = false } label: {
            HStack(spacing: KGSpace.xs) {
                Text("Jetzt", bundle: .module).kgFont(.callout)
                KGIconView(.chevronRight, size: 12).rotationEffect(.degrees(-90))
            }
            .foregroundStyle(KGColor.ink)
            .padding(.horizontal, KGSpace.medium)
            .frame(minHeight: 40)
            .kgGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(KGPressStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Nächste Busse zeigen", bundle: .module))
        .accessibilityIdentifier("nowUnfold")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 { Rectangle().fill(KGColor.line).frame(height: 1) }
                stopView(stop, isFirst: index == 0)
            }
        }
        .padding(.horizontal, KGSpace.medium)
        .padding(.vertical, KGSpace.small)
        .kgGlass(in: .kgRounded(KGRadius.card))
        .kgShadow(.search, in: .kgRounded(KGRadius.card))
        .accessibilityIdentifier("nowCard")
    }

    private func stopView(_ stop: NowStop, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: KGSpace.xs) {
                if stop.isSaved { KGIconView(.star, size: 13).foregroundStyle(KGColor.warn) }
                Text(verbatim: stop.station.shortName).kgFont(.callout).foregroundStyle(KGColor.ink).lineLimit(1)
                    .accessibilityLabel(Text(verbatim: Self.spoken(stop.station.shortName)))
                if let walk = stop.walkMinutes, walk > 1 {
                    Text("\(walk) Min. zu Fuß", bundle: .module).kgFont(.caption.weighted(KGFont.regular))
                        .foregroundStyle(KGColor.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
                if isFirst {
                    Button { folded = true } label: {
                        KGIconView(.chevronRight, size: 12).rotationEffect(.degrees(90)).foregroundStyle(KGColor.ink2)
                            .frame(width: 32, height: 28).contentShape(.rect)
                    }
                    .buttonStyle(KGPressStyle())
                    .accessibilityLabel(Text("Einklappen", bundle: .module))
                    .accessibilityIdentifier("nowFold")
                }
            }
            ForEach(stop.rows) { row in
                Button { onStop(stop.id) } label: { rowView(row).contentShape(.rect) }
                    .buttonStyle(KGPressStyle())
                    .accessibilityLabel(rowLabel(row, stop: stop))
                    .accessibilityIdentifier("nowRow")
            }
        }
    }

    private func rowView(_ row: NowRow) -> some View {
        HStack(spacing: KGSpace.small) {
            KGLineBadge(row.departure.line.name, size: .small)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.departure.headsign).kgFont(.bodyStrong).foregroundStyle(KGColor.ink).lineLimit(1)
                if let note = note(row) {
                    note.kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(noteColor(row)).lineLimit(1)
                }
            }
            Spacer(minLength: KGSpace.xs)
            KGMinutes(row.departure.expected, now: now, isLive: row.departure.status.isLive)
        }
        .frame(minHeight: 40)
    }

    private func note(_ row: NowRow) -> Text? {
        let delay = row.departure.status.delayMinutes
        let late: Text? = delay > 0 ? Text("+\(delay) Min.", bundle: .module)
            : delay < 0 ? Text("\(-delay) Min. früher", bundle: .module) : nil
        let advice: Text? = switch row.advice {
        case let .leaveIn(minutes): Text("Los in \(minutes) Min.", bundle: .module)
        case .leaveNow: Text("Jetzt los", bundle: .module)
        case .hurry: Text("Zügig gehen", bundle: .module)
        case .tooLate, nil: nil
        }
        if let advice, let late { return advice + Text(verbatim: " · ") + late }
        return advice ?? late
    }

    private func noteColor(_ row: NowRow) -> Color {
        switch row.advice {
        case .hurry: KGColor.warn
        case .leaveNow: KGColor.liveText
        default: row.departure.status.delayMinutes == 0 ? KGColor.ink2 : KGColor.warn
        }
    }

    private func rowLabel(_ row: NowRow, stop: NowStop) -> String {
        var parts = [KGStrings.departure(line: row.departure.line.name, destination: row.departure.headsign,
                                         platform: row.departure.platform.code,
                                         minutes: KGMinutesValue(departure: row.departure.expected, now: now),
                                         isLive: row.departure.status.isLive),
                     String(localized: "ab \(Self.spoken(stop.station.shortName))", bundle: .module)]
        switch row.advice {
        case let .leaveIn(minutes): parts.append(String(localized: "Los in \(minutes) Min.", bundle: .module))
        case .leaveNow: parts.append(String(localized: "Jetzt los", bundle: .module))
        case .hurry: parts.append(String(localized: "Zügig gehen", bundle: .module))
        case .tooLate, nil: break
        }
        return parts.joined(separator: ", ")
    }

    /// Nothing to show: says why, when the user can do something about it.
    /// The stop's name for VoiceOver: "Konzilstr./Theater" reads as "Konzilstraße, Theater".
    static func spoken(_ name: String) -> String {
        name.replacingOccurrences(of: "str.", with: "straße").replacingOccurrences(of: "/", with: ", ")
    }

    private var hint: AnyView? {
        let location = services.location
        if services.here != nil {
            return AnyView(message(Text("Gerade fährt hier nichts mehr.", bundle: .module)))
        }
        guard location.coordinate == nil else { return nil }  // Outside Konstanz, with nothing saved.
        switch location.access {
        case .unknown:
            return AnyView(Button { location.requestAccess() } label: {
                message(Text("Erlaube deinen Standort, dann zeige ich dir die nächste Haltestelle.", bundle: .module))
            }
            .buttonStyle(KGPressStyle())
            .accessibilityIdentifier("nowAskLocation"))
        case .denied, .allowed:
            return nil
        }
    }

    private func message(_ text: Text) -> some View {
        text.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KGSpace.medium)
            .kgGlass(in: .kgRounded(KGRadius.card))
    }
}
