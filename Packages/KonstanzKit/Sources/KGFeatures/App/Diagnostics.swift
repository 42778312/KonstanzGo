import Foundation
#if os(iOS)
import MetricKit
#endif

/// Crash and hang reports from iOS, kept on the phone. Nothing is sent: the user can share them from About.
public final class Diagnostics: NSObject, @unchecked Sendable {
    public static let shared = Diagnostics()
    /// Reports kept, newest first by name.
    static let keep = 5

    let folder: URL

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "diagnostics", directoryHint: .isDirectory)) {
        self.folder = folder
        super.init()
    }

    public func start() {
        #if os(iOS)
        MXMetricManager.shared.add(self)
        #endif
    }

    /// The reports to share, oldest first.
    public var reports: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func save(_ report: Data, at date: Date = .now) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? report.write(to: folder.appending(path: "report-\(Int(date.timeIntervalSince1970)).json"), options: .atomic)
        for old in reports.dropLast(Self.keep) { try? FileManager.default.removeItem(at: old) }
    }
}

#if os(iOS)
extension Diagnostics: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { save(payload.jsonRepresentation()) }
    }
}
#endif
