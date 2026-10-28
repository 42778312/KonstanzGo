import SwiftUI

/// The design's shadows (CSS box-shadow: x, y, blur, colour). SwiftUI's radius is about half the CSS blur.
/// In dark mode shadows do not show on near-black, so a hairline outline takes their place (plan A3.5).
public enum KGShadow: Sendable, CaseIterable {
    /// 0 2 8 rgba(0,0,0,.10): cards.
    case card
    /// 0 4 14 rgba(0,0,0,.12): map buttons and chips over the map.
    case floating
    /// 0 6 20 /.10 + 0 1 3 /.08: the map's search bar.
    case search
    /// 0 -8 30 /.12: the bottom sheet.
    case sheet
    /// 0 10 30 /.14 + 0.5 pt inner line: the floating tab bar.
    case tabBar
    /// 0 4 10 rgba(120,20,30,.3): the red bus markers.
    case bus

    struct Layer {
        var color: Color
        var radius: CGFloat
        var y: CGFloat
    }

    var layers: [Layer] {
        let black = Color.black
        switch self {
        case .card: return [Layer(color: black.opacity(0.10), radius: 4, y: 2)]
        case .floating: return [Layer(color: black.opacity(0.12), radius: 7, y: 4)]
        case .search: return [Layer(color: black.opacity(0.10), radius: 10, y: 6),
                              Layer(color: black.opacity(0.08), radius: 1.5, y: 1)]
        case .sheet: return [Layer(color: black.opacity(0.12), radius: 15, y: -8)]
        case .tabBar: return [Layer(color: black.opacity(0.14), radius: 15, y: 10)]
        case .bus: return [Layer(color: Color(KGColorValue(0x78141E)).opacity(0.3), radius: 5, y: 4)]
        }
    }
}

extension View {
    /// The design's shadow in light mode; a hairline outline in `shape` in dark mode.
    public func kgShadow<S: Shape>(_ shadow: KGShadow, in shape: S) -> some View {
        modifier(KGShadowModifier(shadow: shadow, shape: shape))
    }
}

private struct KGShadowModifier<S: Shape>: ViewModifier {
    let shadow: KGShadow
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        } else {
            shadow.layers.reduce(AnyView(content)) { view, layer in
                AnyView(view.shadow(color: layer.color, radius: layer.radius, x: 0, y: layer.y))
            }
            .overlay {
                if shadow == .tabBar { shape.stroke(Color.black.opacity(0.08), lineWidth: 0.5) }
            }
        }
    }
}
