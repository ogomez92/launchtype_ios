import SwiftUI

/// Ask for the master password to open the vault.
///
/// It stays up while the password is being stretched — that takes about a
/// second at the cost the vault is written with, and a launcher that appears
/// to have frozen is worse than one that says what it is doing — and stays up
/// again if the password was wrong, so trying again is one field away.
struct VaultUnlockSheet: View {
    /// Returns whether the vault opened.
    var onUnlock: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var unlocking = false
    @State private var wrongPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Master password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(unlock)
                } footer: {
                    if wrongPassword {
                        Text("That is not the master password.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(unlocking)
            .overlay {
                if unlocking {
                    ProgressView("Unlocking")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .navigationTitle("Unlock the Vault")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(unlocking)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock", action: unlock)
                        .disabled(password.isEmpty || unlocking)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty, !unlocking else {
            return
        }
        Task {
            unlocking = true
            let opened = await onUnlock(password)
            unlocking = false
            if opened {
                dismiss()
            } else {
                wrongPassword = true
                password = ""
            }
        }
    }
}
