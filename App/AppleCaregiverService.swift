import Combine
import Foundation
import LocalAuthentication
import TalkboardCore
import UIKit

@MainActor
protocol NativeAuthenticationContext: AnyObject {
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String,
                        reply: @escaping @Sendable (Bool, (any Error)?) -> Void)
    func invalidate()
}

extension LAContext: NativeAuthenticationContext {}

@MainActor
final class AppleCaregiverAuthenticator: CaregiverAuthenticating {
    private let makeContext: () -> any NativeAuthenticationContext
    private var context: (any NativeAuthenticationContext)?

    convenience init() { self.init(makeContext: Self.makeSystemContext) }

    static func makeSystemContext() -> any NativeAuthenticationContext { LAContext() }

    init(makeContext: @escaping () -> any NativeAuthenticationContext) {
        self.makeContext = makeContext
    }

    func authenticate() async -> Bool {
        let next = makeContext()
        guard next.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        context = next
        let success = await withCheckedContinuation { continuation in
            next.evaluatePolicy(.deviceOwnerAuthentication,
                                localizedReason: "Unlock caregiver controls. The speaking board stays available.") { success, _ in
                continuation.resume(returning: success)
            }
        }
        if context === next { context = nil }
        return success
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}

@MainActor
final class AppleCaregiverService {
    let controller: CaregiverController
    private let guidedAccess: () -> Bool
    private var notification: AnyCancellable?

    convenience init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--silent-speech-test") {
            if args.contains("--caregiver-success-test") || args.contains("--caregiver-failure-test") || args.contains("--caregiver-pending-test") {
                self.init(controller: CaregiverController(authenticator: PreviewCaregiverAuthenticator(
                    success: args.contains("--caregiver-success-test"), pending: args.contains("--caregiver-pending-test"))),
                          guidedAccess: { args.contains("--guided-access-test") })
                return
            }
        }
        #endif
        self.init(controller: CaregiverController(authenticator: AppleCaregiverAuthenticator()))
    }

    init(controller: CaregiverController, notifications center: NotificationCenter = .default,
         guidedAccess: @escaping () -> Bool = { UIAccessibility.isGuidedAccessEnabled }) {
        self.controller = controller
        self.guidedAccess = guidedAccess
        refreshGuidedAccess()
        notification = center.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGuidedAccess() }
            }
    }

    func refreshGuidedAccess() { controller.setGuidedAccessEnabled(guidedAccess()) }
    func background() { controller.setApplicationActive(false) }
    func foreground() {
        refreshGuidedAccess()
        controller.setApplicationActive(true)
    }
}

#if DEBUG
@MainActor
private final class PreviewCaregiverAuthenticator: CaregiverAuthenticating {
    let success: Bool
    let pending: Bool
    private var completion: CheckedContinuation<Bool, Never>?
    init(success: Bool, pending: Bool) { self.success = success; self.pending = pending }
    func authenticate() async -> Bool {
        if pending { return await withCheckedContinuation { completion = $0 } }
        return success
    }
    func cancel() { completion?.resume(returning: false); completion = nil }
}
#endif
