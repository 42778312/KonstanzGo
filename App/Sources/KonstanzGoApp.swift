import KGCore
import KGDesign
import KGFeatures
import SwiftUI

@main
struct KonstanzGoApp: App {
    /// Read once at launch; nil if the bundled data is missing or broken (shown as an error).
    private let timetable: TimetableInfo? = {
        guard let data = BundledData(bundle: .main) else { return nil }
        return try? TimetableInfo.read(from: data.timetable)
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "KGDesignSystem") {
                DesignSystemScreen()
            } else {
                RootView(info: timetable)
            }
            #else
            RootView(info: timetable)
            #endif
        }
    }
}
