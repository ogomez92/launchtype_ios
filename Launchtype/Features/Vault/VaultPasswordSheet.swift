import SwiftUI

/// Choose a master password: for a vault that does not exist yet, or to
/// replace the one it has.
///
/// The confirmation field is not ceremony here — there is no reset and no
/// recovery, so a password typed wrong once is a vault nobody can open again.
struct VaultPasswordSheet: View {
    enum Purpose {
        case setup
        case change

        var title: String {
            switch self {
            case .setup: "Set Up the Vault"
            case .change: "Change the Master Password"
            }
        }

        var help: String {
            switch self {
            case .setup:
                """
                This password encrypts everything you put in the vault, and it is the \
                only way back in: it is not stored anywhere and cannot be recovered or \
                reset. Keep the whole vault folder together when you back it up or move \
                it to another device.
                """
            case .change:
                """
                The entries themselves are not re-encrypted, so this is quick. \
                Everything in the vault will need the new password from now on.
                """
            }
        }
    }

    let purpose: Purpose
    /// Returns whether the vault accepted the passwords.
    var onSubmit: (_ current: String, _ new: String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var working = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(purpose.help)
                        .font(.footnote)
                }
                if purpose == .change {
                    SecureField("Current master password", text: $current)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    SecureField("New master password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Type it again", text: $confirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(footer)
                        .foregroundStyle(failed ? .red : .secondary)
                }
            }
            .disabled(working)
            .overlay {
                if working {
                    ProgressView("Encrypting")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .navigationTitle(purpose.title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(working)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: submit)
                        .disabled(!isValid || working)
                }
            }
        }
    }

    private var footer: String {
        if failed {
            // Setting up has no current password to get wrong, so a failure
            // there is something the alert behind this sheet explains.
            return purpose == .change
                ? "That is not the current master password."
                : "The vault could not be set up."
        }
        if !password.isEmpty, password.count < VaultSession.minimumPasswordLength {
            return "At least \(VaultSession.minimumPasswordLength) characters."
        }
        if !confirmation.isEmpty, confirmation != password {
            return "The two passwords do not match."
        }
        return "At least \(VaultSession.minimumPasswordLength) characters, typed twice."
    }

    private var isValid: Bool {
        password.count >= VaultSession.minimumPasswordLength
            && password == confirmation
            && (purpose == .setup || !current.isEmpty)
    }

    private func submit() {
        guard isValid, !working else {
            return
        }
        Task {
            working = true
            let accepted = await onSubmit(current, password)
            working = false
            if accepted {
                dismiss()
            } else {
                failed = true
                current = ""
            }
        }
    }
}
