import SwiftUI
import TalkboardCore

/// App controls use the reserved band; speech has no caregiver authorization gate.
struct CaregiverControls: View {
    let controller: CaregiverController
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            if !controller.isGuidedAccessEnabled {
                if controller.isUnlocked {
                    Text("Caregiver mode")
                        .accessibilityIdentifier("caregiver-unlocked")
                    Button("Edit board", systemImage: "pencil", action: onEdit)
                        .accessibilityIdentifier("caregiver-edit")
                    Button("Lock", systemImage: "lock.fill") { controller.lock() }
                        .accessibilityIdentifier("caregiver-lock")
                } else if controller.isAuthenticating {
                    Button("Cancel", systemImage: "xmark") { controller.lock() }
                        .accessibilityIdentifier("caregiver-cancel")
                } else {
                    if controller.authenticationFailed {
                        Text("Not unlocked. Try again.")
                            .font(.callout)
                            .accessibilityIdentifier("caregiver-failed")
                    }
                    Button("Caregiver", systemImage: "lock") {
                        Task { await controller.requestUnlock() }
                    }
                    .accessibilityIdentifier("caregiver-unlock")
                }
            }
        }
        .buttonStyle(.bordered)
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
