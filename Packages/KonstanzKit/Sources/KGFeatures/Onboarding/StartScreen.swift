import KGDesign
import SwiftUI

/// Screen 01, kept short on purpose: the logo, Seeri and the name appear at once (a quick fade), and the
/// app moves on after half a second. Only the first launch shows it; later launches open the map straight
/// away (plan S1, changed after testing on a phone: the full animation made people wait).
public struct StartScreen: View {
    let onDone: () -> Void
    @State private var shown = false

    public init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    /// How long the start screen stays.
    static let length = 0.6

    public var body: some View {
        GeometryReader { proxy in
            // The design's frame is the whole 844 pt screen, safe areas included.
            let scale = (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) / 844
            ZStack(alignment: .top) {
                KGColor.coral.ignoresSafeArea()
                KGColor.startSea
                    .frame(height: 144 * scale)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(KGColor.white).frame(width: 180, height: 180)
                        Seeri(.excited, sign: "GO!")
                            .frame(width: 160, height: 170)
                            .padding(.top, 8)
                    }
                    .frame(height: 180)
                    .padding(.top, 228 * scale - proxy.safeAreaInsets.top)
                    Wordmark(size: 44, on: .coral)
                        .padding(.top, 32 * scale)
                    Text("Dein Bus durch Konstanz", bundle: .module)
                        .kgFont(.primaryButton)
                        .foregroundStyle(KGColor.white)
                        .padding(.top, KGSpace.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.96)
            }
        }
        .contentShape(.rect)
        .onTapGesture { onDone() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("KonstanzGo. Dein Bus durch Konstanz", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .task {
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
            try? await Task.sleep(for: .seconds(Self.length))
            onDone()
        }
    }
}

/// The design's wave line: "q 20 −a 40 0 t 40 0 …", repeating every 80 pt, starting 80 pt off screen.
enum Wave {
    static func path(width: CGFloat, amplitude: CGFloat, shift: CGFloat, closed: Bool) -> Path {
        Path { path in
            var x = -80 + shift
            path.move(to: pt(x, 0))
            var up = true
            while x < width + 80 {
                path.addQuadCurve(to: pt(x + 40, 0), control: pt(x + 20, up ? -amplitude : amplitude))
                x += 40
                up.toggle()
            }
            if closed {
                path.addLine(to: pt(x, 20))
                path.addLine(to: pt(-80 + shift, 20))
                path.closeSubpath()
            }
        }
    }
}
