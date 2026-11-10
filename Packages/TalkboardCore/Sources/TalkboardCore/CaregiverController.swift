import Foundation
import Observation

@MainActor
public protocol CaregiverAuthenticating: AnyObject {
    func authenticate() async -> Bool
    func cancel()
}

/// AAC-005: only caregiver actions use this gate. Speech never depends on it.
@MainActor
@Observable
public final class CaregiverController {
    public private(set) var sessionID: UUID?
    public private(set) var isUnlocked = false
    public private(set) var isAuthenticating = false
    public private(set) var isGuidedAccessEnabled: Bool
    public private(set) var authenticationFailed = false
    private var applicationActive = true
    private var attempt: UUID?
    private let authenticator: any CaregiverAuthenticating

    public init(authenticator: any CaregiverAuthenticating, guidedAccessEnabled: Bool = false) {
        self.authenticator = authenticator
        self.isGuidedAccessEnabled = guidedAccessEnabled
    }

    public func requestUnlock() async {
        guard applicationActive, !isGuidedAccessEnabled, !isUnlocked, !isAuthenticating else { return }
        let token = UUID()
        attempt = token
        isAuthenticating = true
        authenticationFailed = false
        let succeeded = await authenticator.authenticate()
        // Cancellation can finish after a fresh request. Only its owner may publish a result.
        guard attempt == token else { return }
        attempt = nil
        isAuthenticating = false
        guard !Task.isCancelled else { return }
        sessionID = succeeded ? token : nil
        isUnlocked = succeeded
        authenticationFailed = !succeeded
    }

    public func lock() {
        sessionID = nil
        attempt = nil
        isUnlocked = false
        isAuthenticating = false
        authenticationFailed = false
        authenticator.cancel()
    }

    public func setGuidedAccessEnabled(_ enabled: Bool) {
        isGuidedAccessEnabled = enabled
        if enabled { lock() }
    }

    /// Call with false for background, not transient inactivity caused by authentication.
    public func setApplicationActive(_ active: Bool) {
        applicationActive = active
        if !active { lock() }
    }
}
