import SwiftUI
import TalkboardCore

/// App controls use the reserved band; speech has no caregiver authorization gate.
struct CaregiverControls: View {
    let controller: CaregiverController
    var editLabel = "Edit home board"
    var onEdit: () -> Void = {}

    @State private var showingCredits = false

    var body: some View {
        HStack(spacing: 12) {
            if !controller.isGuidedAccessEnabled {
                Button("About", systemImage: "info.circle") { showingCredits = true }
                    .accessibilityIdentifier("about-demo")
            }
            Spacer()
            if !controller.isGuidedAccessEnabled {
                if controller.isUnlocked {
                    Text("Caregiver mode")
                        .accessibilityIdentifier("caregiver-unlocked")
                    Button(editLabel, systemImage: "pencil", action: onEdit)
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
        .sheet(isPresented: $showingCredits) { ArtworkCreditsView() }
        .onChange(of: controller.isGuidedAccessEnabled) { _, enabled in
            if enabled { showingCredits = false }
        }
    }
}
