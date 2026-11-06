import Foundation
import KGCore
import Observation

/// Opens the offline data off the main thread while the start animation plays (plan S1.2).
@MainActor
@Observable
public final class TransitLoader {
    public private(set) var transit: OfflineTransit?
    public private(set) var failed = false
    private(set) var data: BundledData?

    public init(data: BundledData?) {
        self.data = data
        guard let data else {
            failed = true
            return
        }
        Task {
            var loaded = await Task.detached(priority: .userInitiated) { try? OfflineTransit(data: data) }.value
            if data.overlay != nil {
                if loaded == nil {
                    // A downloaded set that doesn't open: back to what the app shipped with, right now.
                    DataStore.shared.rollBack()
                    let bundled = data.bundled
                    self.data = bundled
                    loaded = await Task.detached(priority: .userInitiated) { try? OfflineTransit(data: bundled) }.value
                } else {
                    DataStore.shared.confirm()
                }
            }
            self.transit = loaded
            self.failed = loaded == nil
        }
    }
}
