import SwiftUI

/// Every text style with a sample from the design, for the design-system screen and its snapshot test.
public struct TypeSpecimen: View {
    struct Sample {
        let name: String
        let style: KGTextStyle
        let text: String
    }

    static let samples: [Sample] = [
        Sample(name: "hero 40", style: .hero, text: "Alles bereit"),
        Sample(name: "display 32", style: .display, text: "Kein Netz? Kein Problem."),
        Sample(name: "titleL 28", style: .titleL, text: "Favoriten"),
        Sample(name: "title 22", style: .title, text: "In deiner Nähe"),
        Sample(name: "headline 19", style: .headline, text: "14:21 – 14:35"),
        Sample(name: "bodyStrong 17", style: .bodyStrong, text: "Sternenplatz"),
        Sample(name: "bodyMedium 17", style: .bodyMedium, text: "Wohin möchtest du?"),
        Sample(name: "body 16", style: .body, text: "Universität"),
        Sample(name: "button 16", style: .button, text: "Los geht's"),
        Sample(name: "callout 15", style: .callout, text: "Alle"),
        Sample(name: "footnote 14", style: .footnote, text: "2 Min."),
        Sample(name: "badge 14", style: .badge, text: "9A"),
        Sample(name: "caption 13", style: .caption, text: "Haltestelle · 2 Min. zu Fuß"),
        Sample(name: "overline 12", style: .overline, text: "Ergebnisse"),
        Sample(name: "tab 11", style: .tab, text: "Favoriten"),
        Sample(name: "minutes 17", style: .minutes, text: "3 Min. 11 Min."),
        Sample(name: "bigMinutes 44", style: .bigMinutes(44), text: "11 Min."),
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.samples, id: \.name) { sample in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sample.text).kgFont(sample.style).foregroundStyle(KGColor.ink)
                        .fixedSize(horizontal: false, vertical: true)  // wrap, never cut off (rule 5)
                    Text(verbatim: sample.name).kgFont(.caption).foregroundStyle(KGColor.ink3)
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
