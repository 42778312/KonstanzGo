import Foundation

/// Text the components write themselves (units, VoiceOver sentences), German first, from this package's
/// string catalog. Kept as plain strings so tests can read them.
public enum KGStrings {
    /// "Linie 9A".
    public static func line(_ line: String) -> String {
        String(localized: "Linie \(line)", bundle: .kgDesign)
    }

    /// "14:35": 24-hour clock in Konstanz time, as the timetable is.
    public static func clock(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        style.locale = Locale(identifier: "de_DE")
        return date.formatted(style)
    }

    /// "Linie 9A nach Universität, Steig A, in 3 Minuten, laut Fahrplan" (B11).
    public static func departure(line: String, destination: String, platform: String?, minutes: KGMinutesValue,
                                 isLive: Bool) -> String {
        var parts = [String(localized: "Linie \(line) nach \(destination)", bundle: .kgDesign)]
        if let platform { parts.append(String(localized: "Steig \(platform)", bundle: .kgDesign)) }
        parts.append(minutes.spoken)
        parts.append(isLive ? String(localized: "live", bundle: .kgDesign)
                            : String(localized: "laut Fahrplan", bundle: .kgDesign))
        return parts.joined(separator: ", ")
    }
}

extension KGStrings {
    /// "2 Minuten zu Fuß, Linie 9A, 1 Minute zu Fuß" for a leg strip.
    public static func legs(_ legs: [KGLeg]) -> String {
        legs.map { leg in
            switch leg {
            case let .walk(minutes): String(localized: "\(minutes) Minuten zu Fuß", bundle: .kgDesign)
            case let .bus(number): line(number)
            }
        }
        .joined(separator: ", ")
    }
}

extension KGStrings {
    /// A catalog string in the language of `locale` (the view's locale), not the process's.
    public static func text(_ key: String.LocalizationValue, locale: Locale) -> String {
        var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.kgDesign.bundleURL))
        resource.locale = locale
        return String(localized: resource)
    }
}
