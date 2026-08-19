import SwiftUI

/// Add/edit form for a countdown timer. Minutes is a plain number field —
/// faster than a stepper under VoiceOver for large values.
struct TimerEditor: View {
    let original: TimerDef?
    var onSave: (TimerDef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var minutes: Int
    @State private var repeating: Bool

    init(original: TimerDef?, onSave: @escaping (TimerDef) -> Void) {
        self.original = original
        self.onSave = onSave
        _title = State(initialValue: original?.title ?? "")
        _description = State(initialValue: original?.description ?? "")
        _minutes = State(initialValue: Int(original?.minutes ?? 5))
        _repeating = State(initialValue: original?.repeating ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Description (optional)", text: $description)
                TextField("Minutes", value: $minutes, format: .number)
                    .keyboardType(.numberPad)
                Toggle("Repeating", isOn: $repeating)
            }
            .navigationTitle(original == nil ? "New Timer" : "Edit Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(built)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && minutes >= 1
    }

    private var built: TimerDef {
        TimerDef(
            id: original?.id ?? UUID().uuidString.lowercased(),
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            minutes: UInt64(minutes),
            repeating: repeating,
            sound: original?.sound
        )
    }
}
