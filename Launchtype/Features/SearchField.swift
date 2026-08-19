import SwiftUI

/// The search field — the whole interface. Focused on launch and after every
/// mode switch; return runs the first result and the keyboard stays up.
struct SearchField: View {
    @Bindable var model: AppModel
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        TextField("Search", text: $model.query)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused(focused)
            .onSubmit {
                onSubmit()
            }
            .accessibilityLabel("Search \(model.mode.title.lowercased())")
            .padding(.horizontal)
    }
}
