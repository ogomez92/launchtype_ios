import SwiftUI

/// Add/edit form for a snippet. The shortcut becomes the file name, so it
/// cannot contain dots or slashes and must not collide with another snippet —
/// that would silently overwrite the other file.
struct SnippetEditor: View {
    let original: Snippet?
    var isShortcutTaken: (String) -> Bool
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shortcut: String
    @State private var content: String

    init(
        original: Snippet?,
        isShortcutTaken: @escaping (String) -> Bool,
        onSave: @escaping (String, String) -> Void
    ) {
        self.original = original
        self.isShortcutTaken = isShortcutTaken
        self.onSave = onSave
        _shortcut = State(initialValue: original?.shortcut ?? "")
        _content = State(initialValue: original?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Shortcut", text: $shortcut)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Section("Content") {
                    TextEditor(text: $content)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Content")
                }
            }
            .navigationTitle(original == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedShortcut, content)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var trimmedShortcut: String {
        shortcut.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var isValid: Bool {
        !trimmedShortcut.isEmpty
            && !trimmedShortcut.contains(".")
            && !trimmedShortcut.contains("/")
            && !content.isEmpty
            && !isShortcutTaken(trimmedShortcut)
    }
}
