import KGDesign
import SwiftUI

/// The map's sheet with three stops (plan B17). Our own rather than the system sheet, so the floating tab bar
/// stays on top of it and the map stays usable: peek (title only), medium (screen 07: top at 470 of 844) and
/// large. Dragging moves it, a flick goes to the next stop.
enum SheetDetent: CaseIterable { case peek, medium, large }

struct MapSheet<Content: View>: View {
    @Binding var detent: SheetDetent
    /// The sheet's visible height, reported for the map's insets and the buttons above it.
    @Binding var height: CGFloat
    let showsSeeri: Bool
    let content: Content
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(detent: Binding<SheetDetent>, height: Binding<CGFloat>, showsSeeri: Bool,
         @ViewBuilder content: () -> Content) {
        _detent = detent
        _height = height
        self.showsSeeri = showsSeeri
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            // The design's stops are fractions of the whole 844 pt screen, safe areas included.
            let full = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let resting = Self.height(detent, full: full)
            let current = min(max(resting - drag, Self.height(.peek, full: full)), Self.height(.large, full: full))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                KGSheetSurface {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: current)
                // Behind the sheet: only Seeri's head shows over the edge, as in the design.
                .background(alignment: .topTrailing) {
                    if showsSeeri, drag == 0, detent != .large {
                        PeekingSeeri().offset(x: -22, y: -50)
                    }
                }
                .gesture(dragGesture(full: full))
            }
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: current, initial: true) { _, value in height = value }
            .animation(KGMotion.animation(KGMotion.sheet, reduceMotion: reduceMotion), value: detent)
        }
    }

    static func height(_ detent: SheetDetent, full: CGFloat) -> CGFloat {
        switch detent {
        case .peek: 160
        case .medium: full * 374 / 844
        case .large: full - 120
        }
    }

    private func dragGesture(full: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let resting = Self.height(detent, full: full)
                let target = resting - value.predictedEndTranslation.height
                detent = SheetDetent.allCases.min {
                    abs(Self.height($0, full: full) - target) < abs(Self.height($1, full: full) - target)
                } ?? detent
            }
    }
}

/// Seeri looking over the sheet's top edge, bobbing (k-peek, screen 07).
private struct PeekingSeeri: View {
    @State private var peek = false

    var body: some View {
        Seeri(.happy, detail: .peek)
            .frame(width: 62, height: 66)
            .offset(y: peek ? -6 : 0)
            .rotationEffect(.degrees(peek ? -3 : 0))
            .kgLoop(.seeriPeek, phase: $peek)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
