import SwiftUI

/// The mode selector. A segmented picker gets native VoiceOver semantics for
/// free: "Commands, selected, 1 of 5", with swipe-through between segments.
struct ModeTabs: View {
    @Bindable var model: AppModel

    var body: some View {
        Picker("Mode", selection: $model.mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}
