import KGCore
import KGDesign
import SwiftUI

/// The weather over the map in glass, where "Offline bereit" was (Apple Maps' corner): the sky's symbol and the
/// temperature at DWD's Konstanz station. Fresh while online; offline, the last reading.
struct WeatherChip: View {
    let reading: WeatherReading

    var body: some View {
        let night = SunPosition.isNight(at: reading.observed)
        HStack(spacing: KGSpace.xs) {
            Image(systemName: reading.condition.symbol(night: night))
                .symbolRenderingMode(.multicolor)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 20)
                .contentTransition(.symbolEffect(.replace))
            Text(verbatim: reading.degrees)
                .kgFont(.callout.weighted(KGFont.semiBold))
                .foregroundStyle(KGColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, KGSpace.small)
        .frame(minHeight: 40)
        .kgGlass(in: .kgRounded(KGRadius.medium))
        .kgShadow(.floating, in: .kgRounded(KGRadius.medium))
        .animation(KGMotion.pop, value: reading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Wetter in Konstanz: \(reading.degrees), \(Self.name(reading.condition))", bundle: .module))
        .accessibilityValue(Text("Gemessen um \(KGStrings.clock(reading.observed))", bundle: .module))
        .accessibilityIdentifier("weather")
    }

    static func name(_ condition: WeatherCondition) -> Text {
        switch condition {
        case .clear: Text("klar", bundle: .module)
        case .partlyCloudy: Text("teils bewölkt", bundle: .module)
        case .cloudy: Text("bewölkt", bundle: .module)
        case .fog: Text("Nebel", bundle: .module)
        case .drizzle: Text("Nieselregen", bundle: .module)
        case .rain: Text("Regen", bundle: .module)
        case .heavyRain: Text("starker Regen", bundle: .module)
        case .sleet: Text("Schneeregen", bundle: .module)
        case .snow: Text("Schnee", bundle: .module)
        case .hail: Text("Graupel", bundle: .module)
        case .thunder: Text("Gewitter", bundle: .module)
        case .wind: Text("Sturmböen", bundle: .module)
        }
    }
}
