import Testing
@testable import TalkboardCore

@Suite("Caregiver authentication")
@MainActor
struct CaregiverControllerTests {
    @Test("launch starts locked without prompting for authentication")
    func lockedAtLaunch() {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        #expect(!controller.isUnlocked)
        #expect(!controller.isAuthenticating)
        #expect(!controller.isGuidedAccessEnabled)
        #expect(!controller.authenticationFailed)
        #expect(auth.requests.isEmpty)
        #expect(auth.cancelCount == 0)
    }

    @Test("only a successful authentication unlocks and an unlocked request does not prompt again")
    func success() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        #expect(!controller.isUnlocked)
        #expect(controller.isAuthenticating)
        auth.resolve(0, true)
        await task.value
        #expect(controller.isUnlocked)
        #expect(!controller.isAuthenticating)
        #expect(!controller.authenticationFailed)
        auth.immediateResult = false
        await controller.requestUnlock()
        auth.immediateResult = nil
        #expect(auth.requests.count == 1)
    }

    @Test("failure stays locked and a fresh attempt clears the failure before retrying")
    func failureAndRetry() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let first = Task { await controller.requestUnlock() }
        await auth.started(1)
        auth.resolve(0, false)
        await first.value
        #expect(!controller.isUnlocked)
        #expect(!controller.isAuthenticating)
        #expect(controller.authenticationFailed)
        let retry = Task { await controller.requestUnlock() }
        await auth.started(2)
        #expect(!controller.authenticationFailed)
        auth.resolve(1, true)
        await retry.value
        #expect(controller.isUnlocked)
    }

    @Test("repeated requests during authentication share the pending attempt")
    func overlappingRequests() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let first = Task { await controller.requestUnlock() }
        await auth.started(1)
        auth.immediateResult = false
        await controller.requestUnlock()
        auth.immediateResult = nil
        #expect(auth.requests.count == 1)
        auth.resolve(0, true)
        await first.value
    }

    @Test("locking revokes unlocked access and cancels native authentication")
    func explicitLock() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        auth.resolve(0, true)
        await task.value
        controller.lock()
        #expect(!controller.isUnlocked)
        #expect(!controller.isAuthenticating)
        #expect(!controller.authenticationFailed)
        #expect(auth.cancelCount == 1)
    }

    @Test("completion after cancellation cannot unlock or show a stale failure", arguments: [true, false])
    func cancelledCompletion(succeeded: Bool) async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        controller.lock()
        #expect(!controller.isAuthenticating)
        #expect(auth.cancelCount == 1)
        auth.resolve(0, succeeded)
        await task.value
        #expect(!controller.isUnlocked)
        #expect(!controller.authenticationFailed)
    }

    @Test("backgrounding cancels a pending attempt and prevents background prompts")
    func backgroundWhilePending() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        controller.setApplicationActive(false)
        #expect(!controller.isAuthenticating)
        #expect(auth.cancelCount == 1)
        auth.immediateResult = false
        await controller.requestUnlock()
        auth.immediateResult = nil
        #expect(auth.requests.count == 1)
        controller.setApplicationActive(true)
        auth.resolve(0, true)
        await task.value
        #expect(!controller.isUnlocked)
        #expect(!controller.authenticationFailed)
    }

    @Test("backgrounding revokes granted access and foregrounding never restores it")
    func backgroundWhileUnlocked() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        auth.resolve(0, true)
        await task.value
        controller.setApplicationActive(true)
        #expect(controller.isUnlocked)
        controller.setApplicationActive(false)
        #expect(!controller.isUnlocked)
        controller.setApplicationActive(true)
        #expect(!controller.isUnlocked)
        let retry = Task { await controller.requestUnlock() }
        await auth.started(2)
        auth.resolve(1, true)
        await retry.value
        #expect(controller.isUnlocked)
    }

    @Test("Guided Access active at launch prevents authentication")
    func guidedAtLaunch() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth, guidedAccessEnabled: true)
        #expect(controller.isGuidedAccessEnabled)
        auth.immediateResult = false
        await controller.requestUnlock()
        auth.immediateResult = nil
        #expect(auth.requests.isEmpty)
        #expect(!controller.isUnlocked)
        #expect(!controller.authenticationFailed)
    }

    @Test("Guided Access revokes pending authentication and later completion stays stale", arguments: [true, false])
    func guidedWhilePending(succeeded: Bool) async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        controller.setGuidedAccessEnabled(true)
        #expect(controller.isGuidedAccessEnabled)
        #expect(!controller.isAuthenticating)
        #expect(auth.cancelCount == 1)
        auth.immediateResult = false
        await controller.requestUnlock()
        auth.immediateResult = nil
        #expect(auth.requests.count == 1)
        controller.setGuidedAccessEnabled(false)
        #expect(!controller.isGuidedAccessEnabled)
        auth.resolve(0, succeeded)
        await task.value
        #expect(!controller.isUnlocked)
        #expect(!controller.authenticationFailed)
    }

    @Test("Guided Access revokes granted access and disabling it needs a fresh authentication")
    func guidedWhileUnlocked() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        auth.resolve(0, true)
        await task.value
        controller.setGuidedAccessEnabled(false)
        #expect(controller.isUnlocked)
        controller.setGuidedAccessEnabled(true)
        #expect(!controller.isUnlocked)
        controller.setGuidedAccessEnabled(false)
        #expect(!controller.isUnlocked)
        let retry = Task { await controller.requestUnlock() }
        await auth.started(2)
        auth.resolve(1, true)
        await retry.value
        #expect(controller.isUnlocked)
    }

    @Test("a stale result cannot finish a newer pending request", arguments: [true, false])
    func oldResultWhileNewPending(succeeded: Bool) async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let old = Task { await controller.requestUnlock() }
        await auth.started(1)
        controller.lock()
        let current = Task { await controller.requestUnlock() }
        await auth.started(2)
        auth.resolve(0, succeeded)
        await old.value
        #expect(controller.isAuthenticating)
        #expect(!controller.isUnlocked)
        #expect(!controller.authenticationFailed)
        auth.resolve(1, true)
        await current.value
        #expect(controller.isUnlocked)
    }

    @Test("a stale failure after a newer success cannot revoke granted access")
    func oldResultAfterNewSuccess() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let old = Task { await controller.requestUnlock() }
        await auth.started(1)
        controller.lock()
        let current = Task { await controller.requestUnlock() }
        await auth.started(2)
        auth.resolve(1, true)
        await current.value
        auth.resolve(0, false)
        await old.value
        #expect(controller.isUnlocked)
        #expect(!controller.isAuthenticating)
        #expect(!controller.authenticationFailed)
    }

    @Test("locking clears a failure rather than carrying it into child mode")
    func lockClearsFailure() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        auth.resolve(0, false)
        await task.value
        controller.lock()
        #expect(!controller.authenticationFailed)
    }

    @Test("a cancelled caller cannot unlock even if the authenticator succeeds")
    func cancelledCaller() async {
        let auth = CaregiverAuthSpy()
        let controller = CaregiverController(authenticator: auth)
        let task = Task { await controller.requestUnlock() }
        await auth.started(1)
        task.cancel()
        auth.resolve(0, true)
        await task.value
        #expect(!controller.isUnlocked)
        #expect(!controller.isAuthenticating)
        #expect(!controller.authenticationFailed)
    }
}

@MainActor
private final class CaregiverAuthSpy: CaregiverAuthenticating {
    var requests: [CheckedContinuation<Bool, Never>?] = []
    var cancelCount = 0
    var immediateResult: Bool?
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func authenticate() async -> Bool {
        if let immediateResult { requests.append(nil); return immediateResult }
        return await withCheckedContinuation { continuation in
            requests.append(continuation)
            let ready = observers.filter { $0.0 <= requests.count }
            observers.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func started(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func resolve(_ index: Int, _ result: Bool) {
        let continuation = requests[index]
        requests[index] = nil
        continuation?.resume(returning: result)
    }

    func cancel() { cancelCount += 1 }
}
