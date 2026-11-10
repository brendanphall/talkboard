import Foundation
import LocalAuthentication
import Testing
import TalkboardCore
import UIKit
@testable import Talkboard

@Suite("Caregiver native integration", .serialized)
@MainActor
struct AppleCaregiverTests {
    @Test("system context can be constructed and invalidated without presenting authentication")
    func systemContext() {
        let context = AppleCaregiverAuthenticator.makeSystemContext()
        #expect(context is LAContext)
        context.invalidate()
        let auth = AppleCaregiverAuthenticator()
        auth.cancel()
    }

    @Test("authentication requests device owner policy and a fresh native context")
    func policyAndFreshContext() async {
        var contexts: [AuthenticationContextSpy] = []
        let auth = AppleCaregiverAuthenticator(makeContext: {
            let context = AuthenticationContextSpy(); contexts.append(context); return context
        })
        #expect(await auth.authenticate())
        #expect(await auth.authenticate())
        #expect(contexts.count == 2)
        #expect(contexts.allSatisfy { $0.checked == [.deviceOwnerAuthentication] })
        #expect(contexts.allSatisfy { $0.evaluated == [.deviceOwnerAuthentication] })
        #expect(contexts.allSatisfy { !$0.reason.isEmpty })
    }

    @Test("unavailable authentication fails closed without presenting a challenge")
    func unavailable() async {
        let context = AuthenticationContextSpy(); context.available = false
        let auth = AppleCaregiverAuthenticator(makeContext: { context })
        #expect(await !auth.authenticate())
        #expect(context.evaluated.isEmpty)
    }

    @Test("native failure returns false and cancellation invalidates the active context")
    func failureAndCancellation() async {
        let context = AuthenticationContextSpy(); context.result = false
        let auth = AppleCaregiverAuthenticator(makeContext: { context })
        #expect(await !auth.authenticate())
        context.hold = true
        let task = Task { await auth.authenticate() }
        for _ in 0..<100 where context.reply == nil { await Task.yield() }
        auth.cancel()
        #expect(context.invalidations == 1)
        context.finish(false)
        #expect(await !task.value)
        auth.cancel()
        #expect(context.invalidations == 1)
    }

    @Test("old native completion does not clear the context for a newer attempt")
    func overlappingNativeCompletions() async {
        let first = AuthenticationContextSpy(); first.hold = true
        let second = AuthenticationContextSpy(); second.hold = true
        var created = 0
        let auth = AppleCaregiverAuthenticator(makeContext: { created += 1; return created == 1 ? first : second })
        let old = Task { await auth.authenticate() }
        for _ in 0..<100 where first.reply == nil { await Task.yield() }
        auth.cancel()
        let new = Task { await auth.authenticate() }
        for _ in 0..<100 where second.reply == nil { await Task.yield() }
        first.finish(true); _ = await old.value
        auth.cancel()
        #expect(second.invalidations == 1)
        second.finish(false); _ = await new.value
    }

    @Test("background revokes access and rejects requests until foreground")
    func background() async {
        let controller = CaregiverController(authenticator: ImmediateCaregiverAuth())
        let service = AppleCaregiverService(controller: controller, guidedAccess: { false })
        await controller.requestUnlock()
        #expect(controller.isUnlocked)
        service.background()
        #expect(!controller.isUnlocked)
        await controller.requestUnlock()
        #expect(!controller.isUnlocked)
        service.foreground()
        await controller.requestUnlock()
        #expect(controller.isUnlocked)
    }

    @Test("Guided Access status is read at startup and notifications revoke caregiver access")
    func guidedAccess() async {
        let center = NotificationCenter()
        var guided = true
        let controller = CaregiverController(authenticator: ImmediateCaregiverAuth())
        let service = AppleCaregiverService(controller: controller, notifications: center, guidedAccess: { guided })
        #expect(controller.isGuidedAccessEnabled)
        await controller.requestUnlock()
        #expect(!controller.isUnlocked)
        guided = false
        service.refreshGuidedAccess()
        await controller.requestUnlock()
        #expect(controller.isUnlocked)
        guided = true
        center.post(name: UIAccessibility.guidedAccessStatusDidChangeNotification, object: nil)
        for _ in 0..<100 where controller.isUnlocked { await Task.yield() }
        #expect(controller.isGuidedAccessEnabled)
        #expect(!controller.isUnlocked)
        service.background()
        guided = false
        service.foreground()
        #expect(!controller.isGuidedAccessEnabled)
        await controller.requestUnlock()
        #expect(controller.isUnlocked)
    }
}

@MainActor
private final class AuthenticationContextSpy: NativeAuthenticationContext {
    var available = true
    var result = true
    var hold = false
    var checked: [LAPolicy] = []
    var evaluated: [LAPolicy] = []
    var reason = ""
    var invalidations = 0
    var reply: (@Sendable (Bool, (any Error)?) -> Void)?
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        checked.append(policy); return available
    }
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        evaluated.append(policy); reason = localizedReason
        if hold { self.reply = reply } else { reply(result, nil) }
    }
    func invalidate() { invalidations += 1 }
    func finish(_ success: Bool) { let callback = reply; reply = nil; callback?(success, nil) }
}

@MainActor
private final class ImmediateCaregiverAuth: CaregiverAuthenticating {
    func authenticate() async -> Bool { true }
    func cancel() {}
}
