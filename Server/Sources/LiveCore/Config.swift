import Foundation

/// Everything the server is told, from environment variables only. Defaults are safe for local runs.
public struct LiveConfig: Sendable {
    public var port: Int
    public var logLevel: String
    public var timetablePath: String
    /// Comma-separated stop gids to poll instead of the computed hub list. Empty = computed.
    public var hubStops: [String]
    public var upstreamEnabled: Bool
    public var upstreamMaxRPS: Double
    public var pollIntervalSeconds: Double
    public var contactEmail: String
    public var publicURL: String
    /// When set, `/metrics` needs `Authorization: Bearer <token>`.
    public var metricsToken: String?
    public var version: String

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        func value(_ key: String) -> String? {
            environment[key].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        port = value("PORT").flatMap(Int.init) ?? 8080
        logLevel = value("LOG_LEVEL") ?? "info"
        timetablePath = value("TIMETABLE_PATH") ?? "/app/data/timetable.db"
        hubStops = (value("HUB_STOPS") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        upstreamEnabled = (value("LIVE_UPSTREAM_ENABLED") ?? "true").lowercased() != "false"
        // Never above 1 request per second, whatever the environment says.
        upstreamMaxRPS = min(max(value("UPSTREAM_MAX_RPS").flatMap(Double.init) ?? 1, 0.05), 1)
        pollIntervalSeconds = max(value("POLL_INTERVAL_SECONDS").flatMap(Double.init) ?? 30, 10)
        contactEmail = value("CONTACT_EMAIL") ?? ""
        publicURL = value("PUBLIC_URL") ?? "https://github.com/42778312/KonstanzGo"
        metricsToken = value("METRICS_TOKEN")
        version = value("LIVE_VERSION") ?? "dev"
    }

    /// `KonstanzGo-Live/<version> (+<url>; <email>)`, so NVBW can contact us instead of blocking us.
    public var userAgent: String {
        let contact = contactEmail.isEmpty ? publicURL : "\(publicURL); \(contactEmail)"
        return "KonstanzGo-Live/\(version) (+\(contact))"
    }
}
