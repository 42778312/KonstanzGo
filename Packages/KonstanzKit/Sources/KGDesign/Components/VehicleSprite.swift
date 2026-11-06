import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The line number over a vehicle on the map: small, so the 3D vehicle stays the main thing. The vehicle's colour, with
/// a green dot when it reports live. `large` marks a bus on the user's own trip.
public struct KGVehicleLabel: View {
    let line: String
    let isTrain: Bool
    let isYellow: Bool
    let isLive: Bool
    let large: Bool

    public init(line: String, isTrain: Bool = false, isYellow: Bool = false, isLive: Bool = false, large: Bool = false) {
        self.line = line
        self.isTrain = isTrain
        self.isYellow = isYellow
        self.isLive = isLive
        self.large = large
    }

    private var fill: Color { isTrain ? KGColor.trainFill : isYellow ? KGColor.kreuzlingen : KGColor.coralDeep }

    public var body: some View {
        Text(verbatim: line)
            .font(.system(size: large ? 12 : 10, weight: .heavy, design: .rounded))
            .fixedSize()
            .foregroundStyle(!isTrain && isYellow ? Color.black : Color.white)
            .padding(.horizontal, large ? 6 : 4)
            .frame(minWidth: large ? 20 : 15, minHeight: large ? 18 : 14)
            .background(fill, in: .capsule)
            .overlay(Capsule().strokeBorder(KGColor.white, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isLive {
                    Circle().fill(KGColor.live)
                        .overlay(Circle().strokeBorder(KGColor.white, lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .offset(x: 2.5, y: -2.5)
                }
            }
            .environment(\.colorScheme, .light)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isTrain ? Text("Zug \(line), geschätzte Position", bundle: .kgDesign)
                                        : Text("Bus \(line), geschätzte Position", bundle: .kgDesign))
    }
}

#if canImport(UIKit)
/// The rendered 3D vehicles (Design/tools/make_vehicle_sprites.swift): one picture per 10° of heading.
public enum KGVehicleSprite {
    public static func image(named name: String) -> UIImage? {
        UIImage(named: name, in: .kgDesign, with: nil)
    }
}
#endif
