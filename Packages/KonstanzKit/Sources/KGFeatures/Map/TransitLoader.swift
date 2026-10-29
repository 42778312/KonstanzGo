import Foundation
import KGCore
import Observation

/// Opens the offline data off the main thread while the start animation plays (plan S1.2).
@MainActor
@Observable
public final class TransitLoader {
    public private(set) var transit: OfflineTransit?
    public private(set) var failed = false
    let data: BundledData?

    public init(data: BundledData?) {
        self.data = data
        guard let data else {
            failed = true
            return
        }
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { try? OfflineTransit(data: data) }.value
            self.transit = loaded
            self.failed = loaded == nil
        }
    }
}
