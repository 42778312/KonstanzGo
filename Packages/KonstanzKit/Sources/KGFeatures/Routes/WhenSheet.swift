import KGCore
import KGDesign
import SwiftUI

/// Screen 19 (Wann & wie): now / leave at / arrive by, day and time wheels, what to prefer, and a button that
/// says what will happen (plan S9). "Barrierefrei" stays hidden until there is wheelchair data (0.3).
struct WhenSheet: View {
    enum Mode: Int { case now, depart, arrive }

    let onSearch: (PlanQuery) -> Void
    private let original: PlanQuery
    @State private var mode: Mode
    @State private var date: Date
    @State private var preference: RoutePreference
    @Environment(\.dismiss) private var dismiss

    init(query: PlanQuery, onSearch: @escaping (PlanQuery) -> Void) {
        original = query
        self.onSearch = onSearch
        switch query.when {
        case .now:
            _mode = State(initialValue: .now)
            _date = State(initialValue: Self.rounded(.now))
        case let .departAt(date):
            _mode = State(initialValue: .depart)
            _date = State(initialValue: date)
        case let .arriveBy(date):
            _mode = State(initialValue: .arrive)
            _date = State(initialValue: date)
        }
        _preference = State(initialValue: query.preference)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Wann & wie", bundle: .module).kgFont(.titleL.sized(26)).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                KGRoundIconButton(.close, label: Text("Schließen", bundle: .module), surface: .plain) { dismiss() }
            }
            KGSegmentedControl(selection: $mode, options: [(.now, Text("Jetzt", bundle: .module)),
                                                         (.depart, Text("Abfahrt", bundle: .module)),
                                                         (.arrive, Text("Ankunft", bundle: .module))], size: .large)
                .padding(.top, KGSpace.mediumLarge)
            KGTimeWheel(date: $date, today: .now, daysBack: 0)
                .padding(.top, KGSpace.medium)
                .opacity(mode == .now ? 0.35 : 1)
                .disabled(mode == .now)
                .animation(.easeOut(duration: 0.25), value: mode)
            KGSectionHeader(Text("Bevorzugen", bundle: .module)).padding(.top, KGSpace.medium)
            VStack(spacing: KGSpace.compact) {
                option(.fastest, Text("Schnellste", bundle: .module), Text("Früheste Ankunft", bundle: .module),
                       icon: .fastest)
                option(.leastWalking, Text("Wenig laufen", bundle: .module), Text("Kürzere Fußwege", bundle: .module),
                       icon: .walk)
                option(.fewestTransfers, Text("Wenig umsteigen", bundle: .module),
                       Text("Möglichst in einem Bus", bundle: .module), icon: .bus)
            }
            .padding(.top, KGSpace.small)
            Spacer(minLength: KGSpace.large)
            KGButton(buttonTitle) { onSearch(query) }
                .accessibilityIdentifier("searchWhen")
        }
        .padding(.horizontal, KGSpace.large)
        .padding(.top, KGSpace.large)
        .padding(.bottom, KGSpace.compact)
        .presentationDetents([.large])
        .kgGlassSheet()
        .presentationCornerRadius(KGRadius.card)
        .onChange(of: mode) { _, new in
            if new != .now, date < .now { date = Self.rounded(.now) }
        }
    }

    private func option(_ value: RoutePreference, _ title: Text, _ subtitle: Text, icon: KGIcon) -> some View {
        KGOptionCard(title, subtitle: subtitle, icon: icon, isSelected: preference == value) { preference = value }
    }

    private var query: PlanQuery {
        var copy = original
        copy.preference = preference
        switch mode {
        case .now: copy.when = .now
        case .depart: copy.when = .departAt(date)
        case .arrive: copy.when = .arriveBy(date)
        }
        return copy
    }

    /// "Jetzt suchen" / "Ab heute 15:00 suchen" / "Ankunft heute 15:00 suchen" (S9.6).
    private var buttonTitle: Text {
        let day = Calendar.konstanz.isDateInToday(date) ? String(localized: "heute", bundle: .module)
            : Calendar.konstanz.isDateInTomorrow(date) ? String(localized: "morgen", bundle: .module)
            : KGStrings.shortDay(date)
        switch mode {
        case .now: return Text("Jetzt suchen", bundle: .module)
        case .depart: return Text("Ab \(day) \(KGStrings.clock(date)) suchen", bundle: .module)
        case .arrive: return Text("Ankunft \(day) \(KGStrings.clock(date)) suchen", bundle: .module)
        }
    }

    /// The next full five minutes.
    static func rounded(_ date: Date) -> Date {
        let minutes = Calendar.konstanz.component(.minute, from: date)
        let add = (5 - minutes % 5) % 5
        let next = date.addingTimeInterval(TimeInterval(add * 60))
        return Calendar.konstanz.date(bySetting: .second, value: 0, of: next) ?? next
    }
}

/// Screen 20: "Mein Standort → Universität · Heute · ab 15:00 · Schnellste", Seeri driving past the town
/// with speed lines, "Seeri sucht deine Verbindung …", a filling bar and placeholder cards.
struct FindingView: View {
    let query: PlanQuery
    let onBack: () -> Void
    @State private var fill = false
    @State private var start = Date.now

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KGSpace.xs) {
                Button(action: onBack) {
                    KGIconView(.back, size: 22).foregroundStyle(KGColor.ink)
                        .frame(width: KGSize.touch, height: KGSize.touch)
                }
                .buttonStyle(KGPressStyle())
                .accessibilityLabel(Text("Zurück", bundle: .module))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(query.from.name) → \(query.to.name)").kgFont(.body.weighted(KGFont.extraBold))
                        .lineLimit(1)
                    Text(verbatim: summary).kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                }
                .foregroundStyle(KGColor.ink)
                Spacer()
            }
            .padding(.leading, KGSpace.xxs)
            .frame(minHeight: KGSize.searchBar)
            .kgGlassCard(in: .kgRounded(KGRadius.search))
            .kgShadow(.floating, in: .kgRounded(KGRadius.search))
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, 11)
            TimelineView(.animation) { timeline in
                DrivingScene(time: timeline.date.timeIntervalSince(start))
            }
            .frame(height: 280)
            .clipShape(.kgRounded(28))
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, KGSpace.xl)
            Text("Seeri sucht deine Verbindung …", bundle: .module)
                .kgFont(.titleL.sized(24)).foregroundStyle(KGColor.ink)
                .padding(.top, KGSpace.xl)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KGColor.line)
                    Capsule().fill(KGColor.coral).frame(width: proxy.size.width * (fill ? 1 : 0.05))
                }
            }
            .frame(height: 16)
            .padding(.horizontal, 40)
            .padding(.top, KGSpace.large)
            Spacer()
        }
        .onAppear {
            start = .now
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 2.6)) { fill = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Seeri sucht deine Verbindung", bundle: .module))
    }

    private var summary: String {
        let when: String = switch query.when {
        case .now: String(localized: "Jetzt", bundle: .module)
        case let .departAt(date): String(localized: "ab \(KGStrings.clock(date))", bundle: .module)
        case let .arriveBy(date): String(localized: "an \(KGStrings.clock(date))", bundle: .module)
        }
        let preference: String = switch query.preference {
        case .fastest: String(localized: "Schnellste", bundle: .module)
        case .leastWalking: String(localized: "Wenig laufen", bundle: .module)
        case .fewestTransfers: String(localized: "Wenig umsteigen", bundle: .module)
        }
        return "\(when) · \(preference)"
    }
}

/// Seeri on a road by the lake, the road markings rushing past (k-city, k-road, k-speed).
private struct DrivingScene: View {
    let time: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            KGColor.locationTint
            KGColor.mapWater.frame(height: 90).offset(y: 190)
            KGColor.seeriDark.frame(height: 40).offset(y: 214)
            Canvas { context, size in
                let shift = CGFloat((time * 120).truncatingRemainder(dividingBy: 60))
                var x = -shift
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 232, width: 30, height: 4)), with: .color(KGColor.white))
                    x += 60
                }
                for (index, line) in [(70.0, 150.0, 34.0), (60, 170, 46), (76, 190, 28)].enumerated() {
                    let cycle = ((time + Double(index) * 0.27) / 0.8).truncatingRemainder(dividingBy: 1)
                    let rect = CGRect(x: line.0 - 30 * cycle, y: line.1, width: line.2, height: 4)
                    context.opacity = 1 - cycle
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(index == 1 ? KGColor.lineFill : KGColor.coral))
                }
            }
            Seeri(.focused, sign: "GO")
                .frame(width: 110, height: 117)
                .offset(x: 110, y: 104 + CGFloat(sin(time * 12)) * 1.5)
        }
        .accessibilityHidden(true)
    }
}

/// Screen 23 (Keine Verbindung): Seeri asleep, why, and what to do (plan S14).
struct NoRouteView: View {
    let services: AppServices
    let query: PlanQuery
    let onChooseTime: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                KGRoundIconButton(.back, label: Text("Zurück", bundle: .module)) { services.router.back() }
                Spacer()
            }
            .padding(.horizontal, KGSpace.screen)
            .padding(.top, 11)
            Spacer()
            KGEmptyState(.sleepy, title: Text("Keine Verbindung gefunden", bundle: .module), message: reason,
                         hint: firstBus) {
                KGButton(Text("Ziel ändern", bundle: .module), kind: .secondary) {
                    services.router.back()
                }
                KGButton(Text("Andere Zeit wählen", bundle: .module), action: onChooseTime)
            }
            Spacer()
        }
    }

    /// The reason in words (S14.4).
    private var reason: Text {
        let request = query.request()
        if query.from.coordinate.distance(to: query.to.coordinate) < 150 {
            return Text("Start und Ziel liegen direkt nebeneinander. Da bist du zu Fuß schneller.", bundle: .module)
        }
        if let info = services.transit.timetableInfo,
           let end = Calendar.konstanz.date(from: info.validUntil), request.time > end.addingTimeInterval(86_400) {
            return Text("Der Fahrplan in der App reicht nur bis \(KGStrings.shortDay(end)). Bitte aktualisiere die App.",
                        bundle: .module)
        }
        if services.transit.stations(near: query.to.coordinate, within: 1_500, limit: 1).isEmpty {
            return Text("Am Ziel gibt es im Umkreis von 1,5 km keine Haltestelle.", bundle: .module)
        }
        return Text("Um \(KGStrings.clock(request.time)) fährt leider kein Bus nach \(query.to.name). Seeri schläft gerade.",
                    bundle: .module)
    }

    /// "Erster Bus morgen um 05:42" between the stops nearest to start and target (S14.2).
    private var firstBus: Text? {
        let transit = services.transit
        guard let from = transit.stations(near: query.from.coordinate, within: 1_500, limit: 1).first?.0,
              let to = transit.stations(near: query.to.coordinate, within: 1_500, limit: 1).first?.0 else { return nil }
        let today = ServiceDay(query.request().time)
        for (offset, day) in [today, today.adding(days: 1)].enumerated() {
            guard let first = try? transit.store.firstDirectDeparture(from: from.id, to: to.id, on: day),
                  first.scheduled > query.request().time else { continue }
            return offset == 0 ? Text("Erster Bus heute um \(KGStrings.clock(first.scheduled))", bundle: .module)
                               : Text("Erster Bus morgen um \(KGStrings.clock(first.scheduled))", bundle: .module)
        }
        return nil
    }
}
