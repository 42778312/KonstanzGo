import Foundation
import KGCore
import Testing

/// Checks what ends up inside the built app, not the repo: the data folder must be bundled.
@Suite("App bundle")
struct AppBundleTests {
    @Test func dataFolderIsBundled() throws {
        let data = try #require(BundledData(bundle: .main), "Data/ is not in the app bundle")
        for url in data.allFiles {
            #expect(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) is not bundled")
        }
    }

    @Test func bundledTimetableOpens() throws {
        let data = try #require(BundledData(bundle: .main))
        let info = try TimetableInfo.read(from: data.timetable)
        #expect(info.stations > 100)
    }

    @Test func bundleIdentifierIsFinal() {
        // Can never change after the first App Store upload.
        #expect(Bundle.main.bundleIdentifier == "de.konstanzgo.app")
    }
}
