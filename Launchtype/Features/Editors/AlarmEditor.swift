import SwiftUI

/// Add/edit form for an alarm: title, optional description, a wheel time
/// picker, and the enabled toggle.
struct AlarmEditor: View {
    let original: AlarmDef?
    var onSave: (AlarmDef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var time: Date
    @State private var enabled: Bool

    init(original: AlarmDef?, onSave: @escaping (AlarmDef) -> Void) {
        self.original = original
        self.onSave = onSave
        _title = State(initialValue: original?.title ?? "")
        _description = State(initialValue: original?.description ?? "")
        let components = DateComponents(hour: original?.hour ?? 8, minute: original?.minute ?? 0)
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _enabled = State(initialValue: original?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Description (optional)", text: $description)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Toggle("Enabled", isOn: $enabled)
            }
            .navigationTitle(original == nil ? "New Alarm" : "Edit Alarm")
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
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var built: AlarmDef {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        return AlarmDef(
            id: original?.id ?? UUID().uuidString.lowercased(),
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            sound: original?.sound,
            enabled: enabled
        )
    }
}
