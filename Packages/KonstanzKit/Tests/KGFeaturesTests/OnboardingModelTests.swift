import Foundation
import Testing
@testable import KGFeatures

/// Onboarding's steps, what is kept across launches, and what "Erlauben" / "Später" do (plan S3.7, S3.8).
@MainActor
@Suite("Onboarding")
struct OnboardingModelTests {
    let defaults: UserDefaults

    init() {
        let name = "onboarding-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
    }

    @Test func startsAtWelcome() {
        let model = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        #expect(model.step == .welcome)
        #expect(!model.isFinished)
    }

    @Test func goesForwardAndBack() {
        let model = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        model.next()
        model.next()
        #expect(model.step == .search)
        model.back()
        #expect(model.step == .offline)
        #expect(!model.movedForward)
        model.back()
        model.back()
        #expect(model.step == .welcome)
    }

    @Test func comesBackToTheSameStepAfterARestart() {
        let first = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        first.next()
        first.next()
        let second = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        #expect(second.step == .search)
    }

    @Test func allowAsksForWhatIsSwitchedOn() async {
        let model = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        model.wantsLocation = false
        await model.allow()
        #expect(model.step == .ready)
        #expect(!model.locationAllowed)
        #expect(model.notificationsAllowed)
    }

    @Test func refusedPermissionsAreNotShownAsOn() async {
        let model = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: false))
        await model.allow()
        #expect(model.step == .ready)
        #expect(!model.notificationsAllowed)
    }

    @Test func laterAsksNothing() {
        let model = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        model.later()
        #expect(model.step == .ready)
        #expect(!model.locationAllowed)
        #expect(!model.notificationsAllowed)
    }

    @Test func finishedShowsOnlyOnce() {
        let model = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        model.later()
        model.finish()
        let again = OnboardingModel(defaults: defaults, permissions: FixedPermissions(allow: true))
        #expect(again.isFinished)
        again.reset()
        #expect(!again.isFinished)
        #expect(again.step == .welcome)
    }
}
