import CryptoKit
import Foundation

/// Switches the owner can change without an app release (`config.json`, signed like the data). Every value has a
/// safe default and a limit, so a missing or mistaken file can't stop the app working.
public struct RemoteConfig: Codable, Equatable, Sendable {
    /// Off: no live requests at all; the app runs on the timetable.
    public var liveEnabled: Bool
    /// How often the map reads stops around it.
    public var stopReadSeconds: Int
    /// A message for everyone, shown once per id.
    public var bannerID: String?
    public var bannerDE: String?
    public var bannerEN: String?

    public static let standard = RemoteConfig(liveEnabled: true, stopReadSeconds: 30)
    static let stopReadLimits = 15...600

    public init(liveEnabled: Bool, stopReadSeconds: Int, bannerID: String? = nil, bannerDE: String? = nil, bannerEN: String? = nil) {
        self.liveEnabled = liveEnabled
        self.stopReadSeconds = min(max(stopReadSeconds, Self.stopReadLimits.lowerBound), Self.stopReadLimits.upperBound)
        self.bannerID = bannerID
        self.bannerDE = bannerDE
        self.bannerEN = bannerEN
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(liveEnabled: try values.decodeIfPresent(Bool.self, forKey: .liveEnabled) ?? true,
                  stopReadSeconds: try values.decodeIfPresent(Int.self, forKey: .stopReadSeconds) ?? 30,
                  bannerID: try values.decodeIfPresent(String.self, forKey: .bannerID),
                  bannerDE: try values.decodeIfPresent(String.self, forKey: .bannerDE),
                  bannerEN: try values.decodeIfPresent(String.self, forKey: .bannerEN))
    }

    /// The last settings read, or the standard ones.
    public static func cached(in store: DataStore = .shared) -> RemoteConfig {
        (try? Data(contentsOf: store.folder.appending(path: "config.json")))
            .flatMap { try? JSONDecoder().decode(RemoteConfig.self, from: $0) } ?? .standard
    }
}

extension DataSync {
    static let configInterval: TimeInterval = 3600

    /// Reads the settings at most once an hour. Nil when there's nothing new; a bad answer keeps the last ones.
    public func refreshConfig(now: Date = .now) async -> RemoteConfig? {
        guard let base = hostForConfig else { return nil }
        if let last = lastConfigCheck, now.timeIntervalSince(last) < Self.configInterval { return nil }
        do {
            guard let bytes = try await fetchForConfig(base.appending(path: "config.json"), nil).data,
                  let signature = try await fetchForConfig(base.appending(path: "config.sig"), nil).data,
                  isSignedForConfig(bytes, signature: signature) else { return nil }
            let config = try JSONDecoder().decode(RemoteConfig.self, from: bytes)
            try storeConfig(bytes)
            noteConfigCheck(now)
            return config
        } catch {
            return nil
        }
    }
}
