import KGCore
import KGDesign
import KGFeatures
import SwiftUI

@main
struct KonstanzGoApp: App {
    /// Read once at launch; nil if the bundled data is missing or broken (shown as an error).
    private let timetable: TimetableInfo?
    /// The bundle, plus any newer data downloaded since.
    private let data: BundledData?

    init() {
        let data = BundledData.forApp()
        self.data = data
        timetable = data.flatMap { try? TimetableInfo.read(from: $0.timetable) }
    }

    /// The real permission prompts; UI tests answer them with `-KGPermissions allow|deny` (debug builds).
    private let permissions: PermissionAsking = {
        #if DEBUG
        // `-KGFreshInstall YES`: like a first launch after installing (onboarding, saved things, map layers).
        if UserDefaults.standard.bool(forKey: "KGFreshInstall") {
            for key in ["onboarding.finished", "onboarding.step", "map.showsStops", "map.showsVehicles", "alarm.minutes"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let store = try? UserStore.shared() {
                try? store.clearHistory()
                for favorite in (try? store.favorites()) ?? [] { try? store.removeFavorite(id: favorite.id) }
            }
        }
        if UserDefaults.standard.bool(forKey: "KGResetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "onboarding.finished")
            UserDefaults.standard.removeObject(forKey: "onboarding.step")
        }
        switch UserDefaults.standard.string(forKey: "KGPermissions") {
        case "allow": return FixedPermissions(allow: true)
        case "deny": return FixedPermissions(allow: false)
        default: break
        }
        #endif
        return SystemPermissions()
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "KGDesignSystem") {
                DesignSystemScreen()
            } else {
                RootView(info: timetable, data: data, permissions: permissions)
            }
            #else
            RootView(info: timetable, data: data, permissions: permissions)
            #endif
        }
    }
}
