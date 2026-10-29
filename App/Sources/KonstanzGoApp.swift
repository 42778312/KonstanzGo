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

    /// The real permission prompts; UI tests answer them with `-KGPermissions allow|deny` (debug builds).
    private let permissions: PermissionAsking = {
        #if DEBUG
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
                RootView(info: timetable, data: BundledData(bundle: .main), permissions: permissions)
            }
            #else
            RootView(info: timetable, data: BundledData(bundle: .main), permissions: permissions)
            #endif
        }
    }
}
