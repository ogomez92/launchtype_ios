import SwiftUI

/// Add/edit form for a command. On iOS a command is a URL, so Save stays
/// disabled until the URL field resolves to something the app can open. New
/// commands get a `{{browser}}` path so the desktop app runs them the same
/// way; edits keep the original path and unknown keys untouched.
struct CommandEditor: View {
    let original: Command?
    var onSave: (Command) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var shortcut: String
    @State private var urlString: String

    init(original: Command?, onSave: @escaping (Command) -> Void) {
        self.original = original
        self.onSave = onSave
        _name = State(initialValue: original?.name ?? "")
        _shortcut = State(initialValue: original?.shortcut ?? "")
        _urlString = State(initialValue: original?.args ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Shortcut (optional)", text: $shortcut)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("URL", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .navigationTitle(original == nil ? "New Command" : "Edit Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(built(id: original?.id ?? UUID().uuidString.lowercased()))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return CommandURL.launchURL(for: built(id: "preview")) != nil
    }

    private func built(id: String) -> Command {
        var command = original ?? Command(
            path: "{{browser}}",
            name: "",
            args: nil,
            shortcut: nil,
            id: id,
            runAsAdmin: nil,
            runCount: nil
        )
        command.name = name.trimmingCharacters(in: .whitespaces)
        let trimmedShortcut = shortcut.trimmingCharacters(in: .whitespaces).lowercased()
        command.shortcut = trimmedShortcut.isEmpty ? nil : trimmedShortcut
        command.args = urlString.trimmingCharacters(in: .whitespaces)
        return command
    }
}
