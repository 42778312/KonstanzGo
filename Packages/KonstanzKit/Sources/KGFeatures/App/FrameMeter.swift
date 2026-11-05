#if KGMETER && canImport(UIKit)
import UIKit

/// Test builds only (`OTHER_SWIFT_FLAGS=-DKGMETER`), never the App Store: Instruments can't record the phone,
/// so this measures smoothness itself. It guides through three gestures on screen, counts frames and hitches
/// (a frame taking over 1.5 times as long as it should), and writes Documents/meter.csv.
@MainActor
final class FrameMeter: NSObject {
    private static var running: FrameMeter?

    private struct Phase {
        let title: String
        let seconds: Double
        var frames = 0
        var hitches = 0
        var hitchTime = 0.0
        var worst = 0.0
    }

    private var phases = [Phase(title: "Get ready", seconds: 6), Phase(title: "1 Pan the map", seconds: 15),
                          Phase(title: "2 Pinch to zoom", seconds: 15), Phase(title: "3 Tap a stop, drag its list", seconds: 15)]
    private var index = 0
    private var phaseStart = 0.0
    private var last = 0.0
    private let window: UIWindow
    private let label = UILabel()
    private var link: CADisplayLink?

    static func start() {
        guard running == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let meter = FrameMeter(scene: scene)
        running = meter
        meter.begin()
    }

    private init(scene: UIWindowScene) {
        window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .clear
    }

    private func begin() {
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        label.textColor = .black
        label.backgroundColor = .systemYellow
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.frame = CGRect(x: 40, y: 58, width: window.bounds.width - 80, height: 34)
        window.rootViewController?.view.addSubview(label)
        window.isHidden = false
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard last > 0 else {
            phaseStart = now
            return
        }
        let delta = now - last
        phases[index].frames += 1
        phases[index].worst = max(phases[index].worst, delta)
        if delta > link.duration * 1.5 {
            phases[index].hitches += 1
            phases[index].hitchTime += delta - link.duration
        }
        let left = phases[index].seconds - (now - phaseStart)
        if left <= 0 {
            index += 1
            phaseStart = now
            if index == phases.count { return finish(link) }
        }
        label.text = "\(phases[index].title)  \(Int(max(left, 0).rounded(.up)))"
    }

    private func finish(_ link: CADisplayLink) {
        link.invalidate()
        var csv = "phase,seconds,fps,hitches,hitch_ms_per_s,worst_ms\n"
        for phase in phases.dropFirst() {
            let fps = Double(phase.frames) / phase.seconds
            csv += "\(phase.title),\(phase.seconds),\(Int(fps)),\(phase.hitches),"
            csv += "\(Int(phase.hitchTime * 1000 / phase.seconds)),\(Int(phase.worst * 1000))\n"
        }
        try? csv.write(to: URL.documentsDirectory.appending(path: "meter.csv"), atomically: true, encoding: .utf8)
        label.text = "Done, thanks"
    }
}
#endif
