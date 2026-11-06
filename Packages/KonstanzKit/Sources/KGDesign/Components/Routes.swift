import SwiftUI

/// One part of a journey for `KGLegStrip`.
public enum KGLeg: Hashable, Sendable {
    case walk(minutes: Int)
    case bus(line: String)
}

/// Walk › 9A › walk (B22): small grey walking icons with minutes, line badges, grey chevrons between.
/// Wraps onto more lines at large text sizes instead of cutting.
public struct KGLegStrip: View {
    let legs: [KGLeg]

    public init(_ legs: [KGLeg]) {
        self.legs = legs
    }

    public var body: some View {
        KGFlowLayout(spacing: KGSpace.xs, lineSpacing: KGSpace.xs) {
            ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                HStack(spacing: KGSpace.xs) {
                    if index > 0 {
                        KGIconView(.chevronRight, size: 12).foregroundStyle(KGColor.chevron)
                    }
                    switch leg {
                    case let .walk(minutes):
                        HStack(spacing: 2) {
                            KGIconView(.walk, size: 14)
                            Text(minutes, format: .number).kgFont(.caption.weighted(KGFont.regular))
                        }
                        .foregroundStyle(KGColor.ink2)
                    case let .bus(line):
                        KGLineBadge(line, size: .small)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KGStrings.legs(legs))
    }
}

/// A connection (B21, screen 10): "14:21 – 14:35", tag, duration, legs, and a note under them. Selected = black
/// 2 pt border.
public struct KGRouteCard: View {
    let departure: Date
    let arrival: Date
    let tag: (title: Text, tone: KGTag.Tone)?
    let legs: [KGLeg]
    let note: Text?
    let noteIsLive: Bool
    let isSelected: Bool
    let action: () -> Void

    public init(departure: Date, arrival: Date, tag: (title: Text, tone: KGTag.Tone)? = nil, legs: [KGLeg],
                note: Text? = nil, noteIsLive: Bool = false, isSelected: Bool = false, action: @escaping () -> Void) {
        self.departure = departure
        self.arrival = arrival
        self.tag = tag
        self.legs = legs
        self.note = note
        self.noteIsLive = noteIsLive
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: KGSpace.small) { times; tagView; Spacer(minLength: 0); duration }
                    VStack(alignment: .leading, spacing: KGSpace.xxs) {
                        times
                        HStack(spacing: KGSpace.small) { tagView; duration }
                    }
                }
                KGLegStrip(legs).padding(.top, KGSpace.compact)
                if let note {
                    note.kgFont(noteIsLive ? .footnote : .footnote.weighted(KGFont.regular))
                        .foregroundStyle(noteIsLive ? KGColor.liveText : KGColor.ink2)
                        .padding(.top, KGSpace.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, KGSpace.mediumLarge)
            .padding(.horizontal, KGSpace.screen)
            .kgGlassCard(in: .kgRounded(KGRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: KGRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? KGColor.ink : KGColor.line, lineWidth: 2)
            }
            .contentShape(.kgRounded(KGRadius.card))
            .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(KGPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var times: some View {
        Text(verbatim: KGStrings.clock(departure) + " – " + KGStrings.clock(arrival))
            .kgFont(.title.weighted(KGFont.extraBold)).monospacedDigit()
            .foregroundStyle(KGColor.ink)
            .accessibilityLabel(Text("\(KGStrings.clock(departure)) bis \(KGStrings.clock(arrival))",
                                     bundle: .kgDesign))
    }

    @ViewBuilder private var tagView: some View {
        if let tag { KGTag(tag.title, tone: tag.tone) }
    }

    private var duration: some View {
        let minutes = Int((arrival.timeIntervalSince(departure) / 60).rounded())
        return Text("\(minutes) Min.", bundle: .kgDesign).kgFont(.callout).foregroundStyle(KGColor.ink2)
            .accessibilityLabel(Text("\(minutes) Minuten insgesamt", bundle: .kgDesign))
    }
}

/// Lays children out left to right and wraps onto new lines when they don't fit.
public struct KGFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    public init(spacing: CGFloat, lineSpacing: CGFloat) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
