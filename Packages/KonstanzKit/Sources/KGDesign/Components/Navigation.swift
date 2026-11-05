import SwiftUI

// MARK: - Map sheet (B17)

/// The map's bottom sheet stops: peek (handle and title), medium (screen 07, top at y 470 of 844) and large.
public enum KGSheetDetent {
    public static let peek = PresentationDetent.height(118)
    public static let medium = PresentationDetent.height(374)
    public static let large = PresentationDetent.large
    public static let all: Set<PresentationDetent> = [peek, medium, large]
}

extension View {
    /// Shows `content` in the native sheet configured as the map sheet: three stops, the map stays usable
    /// behind it up to the medium stop, radius 20, our own 36 × 5 handle (`KGSheetHandle`), not dismissable by
    /// dragging (the map always has a sheet).
    public func kgMapSheet<Content: View>(isPresented: Binding<Bool>, detent: Binding<PresentationDetent>,
                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) {
            VStack(spacing: 0) {
                KGSheetHandle()
                content()
            }
            .presentationDetents(KGSheetDetent.all, selection: detent)
            .presentationBackgroundInteraction(.enabled(upThrough: KGSheetDetent.medium))
            .presentationCornerRadius(KGRadius.card)
            .presentationDragIndicator(.hidden)
            .presentationBackground(KGColor.surface)
            .interactiveDismissDisabled()
        }
    }
}

/// The sheet's grab handle: 36 × 5, `handle` grey, 8 pt from the top, 14 pt above the content.
public struct KGSheetHandle: View {
    public init() {}

    public var body: some View {
        Capsule().fill(KGColor.handle)
            .frame(width: KGSize.sheetHandle.width, height: KGSize.sheetHandle.height)
            .padding(.top, KGSpace.small)
            .padding(.bottom, KGSpace.mediumLarge)
            .accessibilityHidden(true)
    }
}

/// A sheet's look without presenting it: white, radius 20 on top, the sheet shadow, the handle. For the
/// design-system screen and snapshot tests, and for screens that draw their sheet inline (screen 23).
public struct KGSheetSurface<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: KGRadius.card, topTrailingRadius: KGRadius.card,
                                           style: .continuous)
        VStack(spacing: 0) {
            KGSheetHandle()
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .kgGlass(in: shape)
        .kgShadow(.sheet, in: shape)
    }
}

// MARK: - Floating tab bar (B18)

/// One tab of the floating tab bar.
public struct KGTab<ID: Hashable>: Identifiable {
    public var id: ID
    public var title: Text
    public var icon: KGIcon

    public init(id: ID, title: Text, icon: KGIcon) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

/// The app's own tab bar from screen 07: a glass pill 26 pt above the bottom safe area, 5 pt padding,
/// items 96 × 54. The chosen item sits on a grey capsule with a coral, tint-filled icon; the capsule slides.
public struct KGFloatingTabBar<ID: Hashable>: View {
    @Binding var selection: ID
    let tabs: [KGTab<ID>]
    @Namespace private var capsule
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(selection: Binding<ID>, tabs: [KGTab<ID>]) {
        _selection = selection
        self.tabs = tabs
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let selected = tab.id == selection
                Button {
                    withAnimation(KGMotion.animation(KGMotion.slide, reduceMotion: reduceMotion)) {
                        selection = tab.id
                    }
                } label: {
                    VStack(spacing: 2) {
                        KGIconView(tab.icon, size: 22, fill: selected ? KGColor.coralTint : nil)
                            .foregroundStyle(selected ? KGColor.coral : KGColor.ink3)
                        tab.title
                            .kgFont(selected ? .tab.weighted(KGFont.bold) : .tab.weighted(KGFont.semiBold))
                            .foregroundStyle(selected ? KGColor.ink : KGColor.ink3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: KGSize.tabItem.width * widthScale)
                    .frame(minHeight: KGSize.tabItem.height)
                    .background {
                        if selected {
                            Capsule().fill(KGColor.pressed).matchedGeometryEffect(id: "selected", in: capsule)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityValue(Text("Tab \(index + 1) von \(tabs.count)", bundle: .kgDesign))
            }
        }
        .padding(KGSize.tabBarPadding)
        .kgGlass(in: Capsule())
        .kgShadow(.tabBar, in: Capsule())
        .sensoryFeedback(KGHaptic.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    /// At accessibility sizes the items widen a little so the labels stay legible.
    private var widthScale: CGFloat { typeSize.isAccessibilitySize ? 1.15 : 1 }
}

// MARK: - Timeline (B20)

/// One stop on a trip's timeline (screens 11, 17). The rail is drawn by the list behind the dots.
public struct KGTimelineStop: View {
    public enum State: Sendable {
        /// Already passed: grey text, small coral dot.
        case past
        /// The bus is here now: coral ring that pulses, bold name, "jetzt".
        case current
        /// Still to come: white dot with a grey ring.
        case coming
        /// Where you get off: black diamond, bold.
        case last
        /// Where you get on (screen 17): black dot in a coral ring, bold.
        case first
    }

    let name: String
    let time: Date
    let state: State
    /// The bus doesn't stop here at the moment (a closed stop): an X, the name struck through.
    let isSkipped: Bool
    @SwiftUI.State private var pulsing = false

    public init(_ name: String, time: Date, state: State, isSkipped: Bool = false) {
        self.isSkipped = isSkipped
        self.name = name
        self.time = time
        self.state = state
    }

    public var body: some View {
        HStack(spacing: KGSpace.mediumLarge) {
            Group {
                if isSkipped {
                    KGIconView(.close, size: 11).foregroundStyle(KGColor.white)
                        .frame(width: 20, height: 20)
                        .background(KGColor.coralDeep, in: .kgRounded(6))
                } else {
                    marker
                }
            }
            .frame(width: 22, height: 22)
            Text(verbatim: name)
                .kgFont(bold ? .body.weighted(KGFont.bold) : .body)
                .strikethrough(isSkipped)
                .foregroundStyle(state == .past || isSkipped ? KGColor.ink3 : KGColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            (isSkipped ? Text("hält nicht", bundle: .kgDesign) : timeText)
                .kgFont(.footnote.weighted(bold ? KGFont.bold : KGFont.regular))
                .monospacedDigit()
                .foregroundStyle(isSkipped ? KGColor.ink2 : timeColor)
        }
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
    }

    private var bold: Bool { state != .past && state != .coming }

    private var timeText: Text {
        state == .current ? Text("jetzt", bundle: .kgDesign) : Text(verbatim: KGStrings.clock(time))
    }

    private var timeColor: Color {
        switch state {
        case .past: KGColor.ink3
        case .coming: KGColor.ink2
        case .current, .last, .first: KGColor.ink
        }
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .past:
            Circle().fill(KGColor.coral)
        case .current:
            ZStack {
                Circle().fill(KGColor.coral)
                    .scaleEffect(pulsing ? 1.8 : 1).opacity(pulsing ? 0 : 0.5)
                Circle().fill(KGColor.surface).padding(3)
                Circle().strokeBorder(KGColor.coral, lineWidth: 4).padding(3)
            }
            .kgLoop(.livePulse, phase: $pulsing)
        case .coming:
            Circle().fill(KGColor.surface).overlay(Circle().strokeBorder(KGColor.chevron, lineWidth: 3))
                .frame(width: 12, height: 12)
        case .last:
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(KGColor.ink)
                .frame(width: 14, height: 14).rotationEffect(.degrees(45))
        case .first:
            Circle().fill(KGColor.ink)
                .overlay(Circle().strokeBorder(KGColor.surface, lineWidth: 3))
                .padding(2)
                .background(Circle().fill(KGColor.coral))
                .frame(width: 20, height: 20)
        }
    }
}

/// A rail with stops: grey line, coral up to `progress` (0 … 1 of the rail), then the stops on top.
public struct KGTimeline<Content: View>: View {
    let progress: Double
    let content: Content

    public init(progress: Double, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.content = content()
    }

    public var body: some View {
        content
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    let rail = max(0, proxy.size.height - 38)
                    ZStack(alignment: .top) {
                        Capsule().fill(KGColor.line).frame(width: 4, height: rail)
                        Capsule().fill(KGColor.coral).frame(width: 4, height: rail * min(max(progress, 0), 1))
                    }
                    .frame(width: 22, alignment: .top)
                    .offset(y: 19)
                }
                .frame(width: 22)
                .accessibilityHidden(true)
            }
    }
}
