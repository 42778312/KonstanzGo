import Foundation
import Testing
@testable import KGFeatures

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test func keepsOnlyTheNewestReports() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = Diagnostics(folder: folder)
        #expect(diagnostics.reports.isEmpty)
        for index in 1...7 { diagnostics.save(Data("{}".utf8), at: Date(timeIntervalSince1970: TimeInterval(1_000 + index))) }
        #expect(diagnostics.reports.map(\.lastPathComponent) == (3...7).map { "report-\(1_000 + $0).json" })
    }
}
