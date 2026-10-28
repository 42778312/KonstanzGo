import KGCore
import KGDesign
import SwiftUI

/// The app's first screen. For now (Milestone 0) it only proves the app starts and the bundled
/// timetable loads; the start animation and the map replace it in Milestone 2.
public struct RootView: View {
    let info: TimetableInfo?

    public init(info: TimetableInfo?) {
        self.info = info
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: "KonstanzGo")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("appTitle")
            if let info, let end = Calendar.konstanz.date(from: info.validUntil) {
                // Formatted by Text, so it follows the view's locale, not the device's.
                Text("Fahrplan bis \(end, format: .dateTime.day().month().year())", bundle: .module)
                    .accessibilityIdentifier("timetableStatus")
            } else {
                Text("Offline-Daten fehlen", bundle: .module)
                    .accessibilityIdentifier("timetableStatus")
            }
        }
        .padding()
    }
}

#Preview("Daten da") {
    RootView(info: TimetableInfo(
        feedVersion: "20261011",
        validFrom: DateComponents(year: 2026, month: 7, day: 12),
        validUntil: DateComponents(year: 2026, month: 12, day: 12),
        attribution: "Datensatz der NVBW GmbH",
        stations: 142, platforms: 263, cityLines: 18, trips: 3380
    ))
}

#Preview("Daten fehlen") {
    RootView(info: nil)
}
