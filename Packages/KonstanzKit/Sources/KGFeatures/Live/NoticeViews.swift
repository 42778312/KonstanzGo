import KGCore
import KGDesign
import SwiftUI

extension EnvironmentValues {
    /// Which stops aren't served right now, for timelines anywhere in the app.
    @Entry var stopClosures = StopClosures()
}

extension ServiceNotice {
    /// The stops it closes by name ("Brüelstraße, Schulthaißstraße"), or nil.
    func stopNames(_ transit: OfflineTransit) -> String? {
        let names = stations.compactMap { transit.station(id: $0)?.shortName }
        return names.isEmpty ? nil : ListFormatter.localizedString(byJoining: names)
    }
}

/// Seeri speaks up by the search bar when there's something new from the operator: what's affected, a tap for
/// the details. Goes after a few seconds; each notice is announced once.
struct SeeriNoticeBubble: View {
    let services: AppServices
    @Binding var isSpeaking: Bool
    let onOpen: () -> Void
    @AppStorage("live.seenNotices") private var seen = ""
    @State private var shown: [ServiceNotice] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var live: LiveModel { services.live }
    private var unseen: [ServiceNotice] {
        let known = Set(seen.split(separator: "\n").map(String.init))
        return live.active.filter { !known.contains($0.seenKey) }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if !shown.isEmpty {
                Button {
                    finish()
                    onOpen()
                } label: {
                    HStack(alignment: .top, spacing: KGSpace.small) {
                        KGIconView(.bell, size: 18).foregroundStyle(KGColor.warn).padding(.top, 2)
                        message.kgFont(.callout).foregroundStyle(KGColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        KGIconView(.chevronRight, size: 13).foregroundStyle(KGColor.chevron).padding(.top, 4)
                    }
                    .padding(.horizontal, KGSpace.medium)
                    .padding(.vertical, KGSpace.compact)
                    .contentShape(.rect)
                }
                .buttonStyle(KGPressStyle())
                .kgGlass(in: .kgRounded(KGRadius.card))
                .kgShadow(.floating, in: .kgRounded(KGRadius.card))
                .overlay(alignment: .bottomTrailing) {
                    BubbleTail().fill(.thinMaterial).frame(width: 18, height: 9)
                        .offset(x: -24, y: 9)
                }
                .accessibilityHint(Text("Öffnet die Meldungen", bundle: .module))
                .accessibilityIdentifier("seeriNotice")
                .transition(reduceMotion ? .opacity
                    : .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.warning, trigger: shown.isEmpty) { _, isEmpty in !isEmpty }
        .onDisappear { isSpeaking = false }
        .task(id: unseen.map(\.seenKey)) {
            guard !unseen.isEmpty else { return }
            // Let the map settle first, so the message is noticed.
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(KGMotion.pop) { shown = unseen }
            isSpeaking = true
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private var message: Text {
        // A closed stop matters most: name it, whatever else is new.
        if let names = shown.first(where: \.closesStops)?.stopNames(services.transit) {
            return shown.count == 1 ? Text("Achtung, gerade kein Halt: \(names).", bundle: .module)
                : Text("Achtung, gerade kein Halt: \(names). Mehr in den Meldungen.", bundle: .module)
        }
        guard shown.count == 1, let notice = shown.first else {
            return Text("\(shown.count) neue Meldungen zu den Bussen. Schau kurz rein.", bundle: .module)
        }
        if let line = notice.lines.first {
            return Text("Neue Meldung zu Linie \(line). Schau kurz rein.", bundle: .module)
        }
        return Text("Neue Meldung zu den Bussen. Schau kurz rein.", bundle: .module)
    }

    private func finish() {
        guard !shown.isEmpty else { return }
        let known = seen.split(separator: "\n").map(String.init) + shown.map(\.seenKey)
        // Only what's still running, so the list doesn't grow for ever.
        let running = Set(live.notices.map(\.seenKey))
        seen = known.filter(running.contains).joined(separator: "\n")
        withAnimation(KGMotion.pop) { shown = [] }
        isSpeaking = false
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Every running notice, in a sheet over the map (a tap on the map closes it): what's affected, until when, and where to go instead.
struct NoticesPanel: View {
    let services: AppServices
    let onStation: (Int) -> Void
    let onClose: () -> Void

    private var live: LiveModel { services.live }
    /// Closures first, then soonest over.
    private var notices: [ServiceNotice] {
        live.active.sorted { first, second in
            if first.closesStops != second.closesStops { return first.closesStops }
            return (first.end(after: live.now) ?? .distantFuture) < (second.end(after: live.now) ?? .distantFuture)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KGSpace.medium) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meldungen", bundle: .module).kgFont(.title).foregroundStyle(KGColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        status.kgFont(.footnote.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                            .accessibilityIdentifier("noticesStatus")
                    }
                    Spacer()
                    // Seeri brought the news, and tapping Seeri again puts them away.
                    Button(action: onClose) {
                        SeeriAlive(notices.isEmpty ? .happy : .focused, detail: .compact,
                                   sirenFlashing: notices.isEmpty ? nil : false)
                            .frame(width: 46, height: 50)
                            .frame(width: 54, height: 58)
                            .contentShape(.rect)
                    }
                    .buttonStyle(KGPressStyle())
                    .accessibilityLabel(Text("Schließen", bundle: .module))
                    .accessibilityIdentifier("closeNotices")
                }
                if notices.isEmpty {
                    KGEmptyState(.happy, title: Text("Alles läuft nach Plan", bundle: .module),
                                 message: Text("Gerade gibt es keine Meldungen zu den Bussen.", bundle: .module))
                        .padding(.top, KGSpace.large)
                } else {
                    ForEach(notices) { notice in
                        NoticeCard(services: services, notice: notice, now: live.now, onStation: onStation)
                    }
                }
            }
            .padding(.horizontal, KGSpace.large)
            .padding(.top, KGSpace.large)
            .padding(.bottom, KGSpace.xl)
        }
        .scrollIndicators(.hidden)
    }

    /// "Stand: 19:25", and that it's the last known one when offline.
    private var status: Text {
        guard let updated = live.updated else {
            return Text("Noch keine Daten. Dafür braucht die App einmal Internet.", bundle: .module)
        }
        let time = KGStrings.clock(updated)
        return live.isOnline ? Text("Stand: \(time)", bundle: .module)
            : Text("Offline · letzter Stand: \(time)", bundle: .module)
    }
}

/// One notice: an X for closed stops, the lines, the operator's words, the end, the alternatives.
struct NoticeCard: View {
    let services: AppServices
    let notice: ServiceNotice
    let now: Date
    let onStation: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            HStack(spacing: KGSpace.small) {
                if notice.closesStops {
                    ClosedStopMark(size: 26)
                } else {
                    KGIconView(.bell, size: 18).foregroundStyle(KGColor.warn).frame(width: 26, height: 26)
                }
                title.kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !cityLines.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: KGSpace.xs) {
                        ForEach(cityLines, id: \.self) { KGLineBadge($0, size: .small) }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Text(verbatim: notice.text).kgFont(.callout.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let end = notice.end(after: now) {
                Text("Bis \(KGStrings.shortDay(end)), \(KGStrings.clock(end))", bundle: .module)
                    .kgFont(.caption).foregroundStyle(KGColor.ink2)
            }
            if !notice.alternatives.isEmpty {
                AlternativeStops(services: services, ids: notice.alternatives, onStation: onStation)
                    .padding(.top, KGSpace.xxs)
            }
        }
        .padding(KGSpace.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.glassFill, in: .kgRounded(KGRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("noticeCard")
    }

    private var cityLines: [String] { notice.lines.filter { $0.count <= 5 } }

    private var title: Text {
        if notice.closesStops, let names = notice.stopNames(services.transit) {
            return Text("Kein Halt: \(names)", bundle: .module)
        }
        if notice.lines.count == 1, let line = notice.lines.first {
            return Text("Linie \(line)", bundle: .module)
        }
        return Text("Mehrere Linien", bundle: .module)
    }
}

/// "Stattdessen": the stops to use, each opening with its departures.
struct AlternativeStops: View {
    let services: AppServices
    let ids: [Int]
    let onStation: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.xs) {
            Text("Stattdessen", bundle: .module).kgFont(.caption).foregroundStyle(KGColor.ink2)
            ScrollView(.horizontal) {
                HStack(spacing: KGSpace.xs) {
                    ForEach(ids, id: \.self) { id in
                        if let station = services.transit.station(id: id) {
                            Button { onStation(id) } label: {
                                HStack(spacing: KGSpace.xxs) {
                                    KGIconView(.bus, size: 13).foregroundStyle(KGColor.coral)
                                    Text(verbatim: station.shortName).kgFont(.footnote).foregroundStyle(KGColor.ink)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, KGSpace.compact)
                                .frame(minHeight: 36)
                                .background(KGColor.glassFill, in: Capsule())
                            }
                            .buttonStyle(KGPressStyle())
                            .accessibilityIdentifier("alternativeStop")
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// A tapped stop that isn't served: why, until when, where to go instead.
struct ClosureBanner: View {
    let services: AppServices
    let notice: ServiceNotice
    let onStation: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.small) {
            HStack(alignment: .top, spacing: KGSpace.small) {
                ClosedStopMark(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wird nicht angefahren", bundle: .module).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                    if let end = notice.end(after: services.live.now) {
                        Text("Bis \(KGStrings.shortDay(end)), \(KGStrings.clock(end))", bundle: .module)
                            .kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
                    }
                }
            }
            AlternativeStops(services: services, ids: notice.alternatives, onStation: onStation)
        }
        .padding(KGSpace.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.glassFill, in: .kgRounded(KGRadius.medium))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("closureBanner")
    }
}

/// The X of a stop that isn't served, the same as on the map.
struct ClosedStopMark: View {
    let size: CGFloat

    var body: some View {
        KGIconView(.close, size: size * 0.5).foregroundStyle(KGColor.white)
            .frame(width: size, height: size)
            .background(KGColor.coralDeep, in: .kgRounded(size * 0.28))
            .accessibilityHidden(true)
    }
}
