import Foundation
import Observation

/// Asks iOS for the two permissions onboarding offers. A protocol so previews, snapshot and UI tests can
/// answer without system dialogs.
@MainActor
public protocol PermissionAsking: AnyObject {
    /// Shows the location prompt (when in use); true when allowed.
    func requestLocation() async -> Bool
    /// Shows the notification prompt (alerts, sounds, time-sensitive); true when allowed.
    func requestNotifications() async -> Bool
}

/// Where the user is in onboarding (screens 02–06), kept in `UserDefaults` so closing the app in the middle
/// comes back to the same step, and onboarding shows only once (plan S3.7).
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome = 1, permissions, ready

        /// The progress bar counts the steps before "Alles bereit".
        public static let counted = 2
    }

    public private(set) var step: Step
    public private(set) var isFinished: Bool
    /// Which way the last move went, for the slide direction.
    public private(set) var movedForward = true
    public var wantsLocation = true
    public var wantsNotifications = true
    public private(set) var locationAllowed = false
    public private(set) var notificationsAllowed = false
    public private(set) var isAsking = false

    private let defaults: UserDefaults
    private let permissions: PermissionAsking

    static let stepKey = "onboarding.step"
    static let finishedKey = "onboarding.finished"
    static let notificationsKey = "onboarding.notificationsAllowed"

    public init(defaults: UserDefaults = .standard, permissions: PermissionAsking) {
        self.defaults = defaults
        self.permissions = permissions
        isFinished = defaults.bool(forKey: Self.finishedKey)
        step = Step(rawValue: defaults.integer(forKey: Self.stepKey)) ?? .welcome
        notificationsAllowed = defaults.bool(forKey: Self.notificationsKey)
    }

    public func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        move(to: following, forward: true)
    }

    public func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        move(to: previous, forward: false)
    }

    /// "Erlauben": asks for what is switched on, then shows "Alles bereit".
    public func allow() async {
        isAsking = true
        if wantsLocation { locationAllowed = await permissions.requestLocation() }
        if wantsNotifications { notificationsAllowed = await permissions.requestNotifications() }
        defaults.set(notificationsAllowed, forKey: Self.notificationsKey)
        isAsking = false
        move(to: .ready, forward: true)
    }

    /// "Später": no prompts now; the map and the alarms ask again when they need it.
    public func later() {
        move(to: .ready, forward: true)
    }

    /// "Losfahren".
    public func finish() {
        isFinished = true
        defaults.set(true, forKey: Self.finishedKey)
        defaults.removeObject(forKey: Self.stepKey)
    }

    /// Start again from the first step (debug menu, UI tests).
    public func reset() {
        isFinished = false
        defaults.removeObject(forKey: Self.finishedKey)
        move(to: .welcome, forward: false)
    }

    private func move(to newStep: Step, forward: Bool) {
        movedForward = forward
        step = newStep
        defaults.set(newStep.rawValue, forKey: Self.stepKey)
    }
}
