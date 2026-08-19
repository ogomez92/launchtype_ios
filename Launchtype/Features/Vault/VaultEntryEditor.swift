import SwiftUI

/// Add or edit a vault entry.
///
/// The secret is shown in the clear rather than masked. A masked field is read
/// out by VoiceOver as nothing at all, which would leave no way to check what
/// was typed or what is stored — and the vault is already open by the time
/// this sheet is up, so masking here would buy shoulder-surfing cover and
/// nothing else. It is multi-line so recovery codes and keys fit.
struct VaultEntryEditor: View {
    let original: VaultEntryDraft?
    var onSave: (VaultEntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var shortcut: String
    @State private var secret: String

    init(original: VaultEntryDraft?, onSave: @escaping (VaultEntryDraft) -> Void) {
        self.original = original
        self.onSave = onSave
        _name = State(initialValue: original?.name ?? "")
        _shortcut = State(initialValue: original?.shortcut ?? "")
        _secret = State(initialValue: original?.secret ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Shortcut (optional)", text: $shortcut)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Section {
                    TextEditor(text: $secret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Secret")
                } header: {
                    Text("Secret")
                } footer: {
                    Text("Encrypted before it reaches the disk. It is never written anywhere in the clear.")
                }
            }
            .navigationTitle(original == nil ? "Add to the Vault" : "Edit Vault Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(VaultEntryDraft(
                            id: original?.id,
                            name: name.trimmingCharacters(in: .whitespaces),
                            shortcut: shortcut.trimmingCharacters(in: .whitespaces).lowercased(),
                            secret: secret
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !secret.isEmpty
    }
}
