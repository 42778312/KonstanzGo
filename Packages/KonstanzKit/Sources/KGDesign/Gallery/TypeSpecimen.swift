import SwiftUI

/// Every text style with a sample from the design, for the design-system screen and its snapshot test.
public struct TypeSpecimen: View {
    static let samples: [(String, KGTextStyle, String)] = [
        ("hero 40", .hero, "Alles bereit!"),
        ("display 32", .display, "Kein Netz? Kein Problem!"),
        ("titleL 28", .titleL, "Favoriten"),
        ("title 22", .title, "In deiner Nähe"),
        ("headline 19", .headline, "14:21 – 14:35"),
        ("bodyStrong 17", .bodyStrong, "Sternenplatz"),
        ("bodyMedium 17", .bodyMedium, "Wohin möchtest du?"),
        ("body 16", .body, "Universität"),
        ("button 16", .button, "Los geht's"),
        ("callout 15", .callout, "Alle"),
        ("footnote 14", .footnote, "2 Min."),
        ("badge 14", .badge, "9A"),
        ("caption 13", .caption, "Haltestelle · 2 Min. zu Fuß"),
        ("overline 12", .overline, "Ergebnisse"),
        ("tab 11", .tab, "Favoriten"),
        ("minutes 17", .minutes, "3 Min. 11 Min."),
        ("bigMinutes 44", .bigMinutes(44), "11 Min."),
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.samples, id: \.0) { name, style, sample in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sample).kgFont(style).foregroundStyle(KGColor.ink)
                        .fixedSize(horizontal: false, vertical: true)  // wrap, never cut off (rule 5)
                    Text(verbatim: name).kgFont(.caption).foregroundStyle(KGColor.ink3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KGColor.surface)
    }
}

#Preview("Type") {
    ScrollView { TypeSpecimen() }
}

#Preview("Type, AX3") {
    ScrollView { TypeSpecimen() }
        .dynamicTypeSize(.accessibility3)
}
