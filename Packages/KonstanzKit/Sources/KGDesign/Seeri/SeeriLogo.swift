import SwiftUI

/// The logo tile: Seeri's face in white on a coral rounded square, with the lake's wave
/// (the map's search bar, app icon, widgets). Drawn from AppMap's 100 × 100 grid.
public struct SeeriLogo: View {
    let size: CGFloat

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 100
            context.scaleBy(x: scale, y: scale)
            context.fill(Path(roundedRect: CGRect(x: 20, y: 22, width: 60, height: 42), cornerRadius: 15),
                         with: .color(KGColor.white))
            for x in [40.0, 60.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 6, y: 35, width: 12, height: 12)), with: .color(.black))
            }
            let smile = (try? SVGPath.path("M 43 52 Q 50 58 57 52")) ?? Path()
            context.stroke(smile, with: .color(.black), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            let wave = (try? SVGPath.path("M 16 79 q 8.5 -8 17 0 t 17 0 t 17 0 t 17 0")) ?? Path()
            context.stroke(wave, with: .color(KGColor.white), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }
        .frame(width: size * 32 / 38, height: size * 32 / 38)
        .frame(width: size, height: size)
        .background(KGColor.coral, in: .kgRounded(size * 11 / 38))
        .accessibilityHidden(true)
    }
}

/// Every expression and detail level, for the design-system screen and its snapshot.
public struct SeeriGallery: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: KGSpace.large) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: KGSpace.medium) {
                ForEach(Seeri.Expression.allCases, id: \.self) { expression in
                    VStack(spacing: KGSpace.xxs) {
                        Seeri(expression).frame(height: 76)
                        Text(verbatim: expression.rawValue).kgFont(.caption).foregroundStyle(KGColor.ink3)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: KGSpace.large) {
                Seeri(.spooky, hat: .witch).frame(height: 96)
                Seeri(.happy, detail: .peek).frame(height: 66)
                Seeri(.happy, detail: .compact).frame(height: 44)
                Seeri(.excited, shadow: true).frame(height: 76)
                SeeriLogo()
            }
        }
        .padding(KGSpace.screen)
        .background(KGColor.surface)
    }
}

#Preview("Seeri") {
    SeeriGallery()
}
