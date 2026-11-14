import Foundation

/// Counters and gauges, rendered in the Prometheus text format for `/metrics`. Kept by hand: the server needs a
/// dozen numbers, not a metrics framework.
public actor Metrics {
    private var counters: [String: [String: Int]] = [:]
    private var gauges: [String: Double] = [:]

    public init() {}

    public func count(_ name: String, label: String? = nil, by amount: Int = 1) {
        counters[name, default: [:]][label ?? "", default: 0] += amount
    }

    public func set(_ name: String, _ value: Double) { gauges[name] = value }

    public func counter(_ name: String, label: String? = nil) -> Int { counters[name]?[label ?? ""] ?? 0 }

    public func gauge(_ name: String) -> Double? { gauges[name] }

    public func render() -> String {
        var lines: [String] = []
        for (name, values) in counters.sorted(by: { $0.key < $1.key }) {
            lines.append("# TYPE \(name) counter")
            for (label, value) in values.sorted(by: { $0.key < $1.key }) {
                let key = label.isEmpty ? name : "\(name){\(labelName(for: name))=\"\(label)\"}"
                lines.append("\(key) \(value)")
            }
        }
        for (name, value) in gauges.sorted(by: { $0.key < $1.key }) {
            lines.append("# TYPE \(name) gauge")
            lines.append("\(name) \(value)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func labelName(for counter: String) -> String {
        counter.hasPrefix("upstream_requests") ? "status" : "reason"
    }
}
