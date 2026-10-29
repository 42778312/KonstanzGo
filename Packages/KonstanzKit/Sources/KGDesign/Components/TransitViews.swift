import SwiftUI

/// The yellow line-number capsule (B6). Sizes from the artboards: small 24 high / 32 wide / 13 pt
/// (headers, search results, route cards), medium 26 / 36 / 14 (stop cards), large 28 / 40 / 15 (stop screen),
/// big 38 / 52 / 21 tile (departure details, radius 12).
public struct KGLineBadge: View {
    public enum Size: Sendable, CaseIterable {
        case small, medium, large, big

        var height: CGFloat {
            switch self {
            case .small: 24
            case .medium: KGSize.badgeHeight
            case .large: 28
            case .big: 38
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .small: 32
            case .medium: KGSize.badgeMinWidth
            case .large: 40
            case .big: 52
            }
        }

        var style: KGTextStyle {
            switch self {
            case .small: .badge.sized(13)
            case .medium: .badge
            case .large: .badge.sized(15)
            case .big: .badge.weighted(KGFont.bold).sized(21)
            }
        }

        var padding: CGFloat {
            switch self {
            case .small, .big: KGSpace.small
            case .medium: 9
            case .large: KGSpace.compact
            }
        }
    }

    let line: String
    let size: Size
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ line: String, size: Size = .medium) {
        self.line = line
        self.size = size
    }

    public var body: some View {
        let scale = typeSize.kgBadgeScale
        Text(verbatim: line)
            .kgFont(size.style)
            .foregroundStyle(KGColor.onLine)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size.padding)
            .frame(minWidth: size.minWidth * scale, minHeight: size.height * scale)
            .background(KGColor.lineFill, in: shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(KGStrings.line(line))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .big ? KGRadius.medium : size.height * typeSize.kgBadgeScale / 2,
                         style: .continuous)
    }
}

extension DynamicTypeSize {
    /// Badges and chips grow with the text but less than it, so rows stay readable at AX sizes.
    var kgBadgeScale: CGFloat {
        switch self {
        case .xSmall, .small, .medium, .large: 1
        case .xLarge: 1.06
        case .xxLarge: 1.12
        case .xxxLarge: 1.18
        default: 1.4
        }
    }
}

/// Minutes until a departure (B7): "jetzt" under one minute, "3 Min." up to an hour, then the clock time
/// "14:35". Fixed-width digits; the number rolls when it changes. Green only for live data (plan 0.3).
public struct KGMinutes: View {
    public enum Style: Sendable {
        /// 17 ExtraBold in one run: "3 Min." (stop cards, lists).
        case compact
        /// Big number + small unit, as the stop screen: "3" 24 ExtraBold, "Min." 13 SemiBold.
        case large
    }

    let departure: Date
    let now: Date
    let isLive: Bool
    let style: Style

    public init(_ departure: Date, now: Date, isLive: Bool = false, style: Style = .compact) {
        self.departure = departure
        self.now = now
        self.isLive = isLive
        self.style = style
    }

    public var body: some View {
        let value = KGMinutesValue(departure: departure, now: now)
        Group {
            switch (value, style) {
            case let (.minutes(count), .large):
                HStack(alignment: .firstTextBaseline, spacing: KGSpace.xxs) {
                    Text(count, format: .number).kgFont(.bigMinutes(24))
                    Text("Min.", bundle: .kgDesign).kgFont(.caption.weighted(KGFont.semiBold))
                }
            default:
                value.text.kgFont(style == .large ? .bigMinutes(24) : .minutes)
            }
        }
        .foregroundStyle(isLive ? KGColor.liveText : KGColor.ink)
        .contentTransition(.numericText(countsDown: true))
        .animation(.default, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.spoken)
    }
}

/// What `KGMinutes` shows, separate from the view so it can be tested.
public enum KGMinutesValue: Hashable, Sendable {
    case now
    case minutes(Int)
    case clock(Date)

    /// From 60 minutes on the clock time is clearer than a big number.
    public static let clockFrom = 60

    public init(departure: Date, now: Date) {
        let minutes = Int((departure.timeIntervalSince(now) / 60).rounded(.down))
        if minutes < 1 {
            self = .now
        } else if minutes < Self.clockFrom {
            self = .minutes(minutes)
        } else {
            self = .clock(departure)
        }
    }

    public var text: Text {
        switch self {
        case .now: Text("jetzt", bundle: .kgDesign)
        case let .minutes(count): Text("\(count) Min.", bundle: .kgDesign)
        case let .clock(date): Text(verbatim: KGStrings.clock(date))
        }
    }

    /// For VoiceOver: "jetzt", "in 3 Minuten", "um 14:35".
    public var spoken: String {
        switch self {
        case .now: String(localized: "jetzt", bundle: .kgDesign)
        case let .minutes(count): String(localized: "in \(count) Minuten", bundle: .kgDesign)
        case let .clock(date): String(localized: "um \(KGStrings.clock(date))", bundle: .kgDesign)
        }
    }
}

/// The live dot (B8): 8 pt green dot with a ring that grows to 2.6× and fades (k-live, 1.3 s). Decoration only.
public struct KGLiveDot: View {
    @State private var pulsing = false

    public init() {}

    public var body: some View {
        ZStack {
            Circle().fill(KGColor.live)
                .scaleEffect(pulsing ? 2.6 : 1)
                .opacity(pulsing ? 0 : 0.6)
            Circle().fill(KGColor.live)
        }
        .frame(width: 8, height: 8)
        .kgLoop(.livePulse, phase: $pulsing)
        .accessibilityHidden(true)
    }
}

/// Walking time chip (B9): walking person + "2 Min." in a white capsule, 26 high, 13 SemiBold.
public struct KGWalkChip: View {
    let minutes: Int

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public var body: some View {
        HStack(spacing: KGSpace.xxs) {
            KGIconView(.walk, size: 13)
            Text("\(minutes) Min.", bundle: .kgDesign).kgFont(.caption.weighted(KGFont.semiBold))
        }
        .foregroundStyle(KGColor.ink2)
        .padding(.leading, KGSpace.small)
        .padding(.trailing, KGSpace.compact)
        .frame(minHeight: KGSize.badgeHeight)
        .background(KGColor.surface, in: .capsule)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(minutes) Minuten zu Fuß", bundle: .kgDesign))
    }
}

/// The status pill over the map (B10): green check in a circle + "Offline bereit", white capsule, 34 high,
/// 14 SemiBold, floating shadow. `warning` turns the circle orange ("Fahrplan endet bald").
public struct KGStatusPill: View {
    let title: Text
    let isWarning: Bool

    public init(_ title: Text, isWarning: Bool = false) {
        self.title = title
        self.isWarning = isWarning
    }

    public var body: some View {
        HStack(spacing: KGSpace.xs) {
            KGIconView(isWarning ? .timer : .check, size: 11)
                .foregroundStyle(KGColor.white)
                .frame(width: 20, height: 20)
                .background(isWarning ? KGColor.warn : KGColor.live, in: .circle)
            title.kgFont(.footnote).foregroundStyle(KGColor.ink)
        }
        .padding(.leading, KGSpace.small)
        .padding(.trailing, KGSpace.medium)
        .frame(minHeight: 34)
        .background(KGColor.surface, in: .capsule)
        .kgShadow(.floating, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A small tag (route card "Schnellste", "Wenig laufen"; "Erster Bus 05:42"): 22 high capsule, 12 Bold.
public struct KGTag: View {
    public enum Tone: Sendable { case line, live, neutral }

    let title: Text
    let tone: Tone

    public init(_ title: Text, tone: Tone = .line) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        title
            .kgFont(.caption.weighted(KGFont.bold).sized(12))
            .foregroundStyle(foreground)
            .padding(.horizontal, KGSpace.small)
            .frame(minHeight: 22)
            .background(background, in: .capsule)
    }

    private var foreground: Color {
        switch tone {
        case .line: KGColor.lineText
        case .live: KGColor.liveText
        case .neutral: KGColor.ink2
        }
    }

    private var background: Color {
        switch tone {
        case .line: KGColor.lineTint
        case .live: KGColor.liveTint
        case .neutral: KGColor.card
        }
    }
}

/// One departure (B11). `compact`: 44 high, inside stop cards (screen 07). `large`: 64 high with the platform
/// under the destination and big minutes (screen 09). Dividers are the list's job (between rows only).
/// VoiceOver reads one sentence: "Linie 9A nach Universität, Steig A, in 3 Minuten, laut Fahrplan".
public struct KGDepartureRow: View {
    public enum Style: Sendable { case compact, large }

    let line: String
    let destination: String
    let platform: String?
    let departure: Date
    let now: Date
    let isLive: Bool
    let style: Style

    public init(line: String, destination: String, platform: String? = nil, departure: Date, now: Date,
                isLive: Bool = false, style: Style = .compact) {
        self.line = line
        self.destination = destination
        self.platform = platform
        self.departure = departure
        self.now = now
        self.isLive = isLive
        self.style = style
    }

    public var body: some View {
        HStack(spacing: style == .large ? KGSpace.medium : KGSpace.compact) {
            KGLineBadge(line, size: style == .large ? .large : .medium)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: destination)
                    .kgFont(style == .large ? .bodyMedium : .body)
                    .foregroundStyle(KGColor.ink)
                if style == .large, let platform {
                    Text("Steig \(platform)", bundle: .kgDesign).kgFont(.caption).foregroundStyle(KGColor.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isLive { KGLiveDot().padding(.trailing, 2) }
            KGMinutes(departure, now: now, isLive: isLive, style: style == .large ? .large : .compact)
        }
        .padding(.vertical, KGSpace.xxs)
        .frame(minHeight: style == .large ? 64 : KGSize.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KGStrings.departure(line: line, destination: destination, platform: platform,
                                                minutes: KGMinutesValue(departure: departure, now: now),
                                                isLive: isLive))
    }
}

/// One departure for `KGStopCard` and lists.
public struct KGDepartureItem: Identifiable, Sendable {
    public var id: String
    public var line: String
    public var destination: String
    public var platform: String?
    public var departure: Date
    public var isLive: Bool

    public init(id: String, line: String, destination: String, platform: String? = nil, departure: Date,
                isLive: Bool = false) {
        self.id = id
        self.line = line
        self.destination = destination
        self.platform = platform
        self.departure = departure
        self.isLive = isLive
    }
}

/// A stop with its next departures (B12): card fill, radius 20, name 17 Bold, walk chip, up to 3 rows
/// separated by hairlines.
public struct KGStopCard: View {
    let name: String
    let walkMinutes: Int?
    let departures: [KGDepartureItem]
    let now: Date

    public init(name: String, walkMinutes: Int?, departures: [KGDepartureItem], now: Date) {
        self.name = name
        self.walkMinutes = walkMinutes
        self.departures = departures
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: name).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: KGSpace.small)
                if let walkMinutes { KGWalkChip(minutes: walkMinutes) }
            }
            .padding(.bottom, KGSpace.xxs)
            ForEach(Array(departures.prefix(3).enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(KGColor.line).frame(height: 1) }
                KGDepartureRow(line: item.line, destination: item.destination, platform: item.platform,
                               departure: item.departure, now: now, isLive: item.isLive)
            }
        }
        .padding(.top, KGSpace.medium)
        .padding(.horizontal, KGSpace.mediumLarge)
        .padding(.bottom, KGSpace.xs)
        .background(KGColor.card, in: .kgRounded(KGRadius.card))
        .accessibilityElement(children: .contain)
    }
}
