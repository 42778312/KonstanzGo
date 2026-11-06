import SwiftUI

/// The app's glass, the colour of the map's search field: a real blur of what's behind under a deep blue-grey, with a
/// faint light along the top. Every sheet, menu and full screen stands on this.
public struct KGGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        if reduceTransparency {
            KGColor.surface
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [KGColor.glassTint.opacity(0.84), KGColor.glassTintDeep.opacity(0.88)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [.white.opacity(0.03), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14))
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// A card or group of rows on glass: a pane of light, brighter where light falls on it, with a soft bright edge.
    /// Gradients instead of another blur, so long lists stay smooth over the moving map.
    public func kgGlassCard<S: Shape>(in shape: S) -> some View {
        background {
            shape.fill(LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0.025)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .kgGlassEdge(in: shape)
    }

    /// Only the bright edge, for controls that bring their own fill.
    public func kgGlassEdge<S: Shape>(in shape: S) -> some View {
        overlay {
            shape.stroke(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}
