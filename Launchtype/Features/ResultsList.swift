import SwiftUI

/// The results list. Deliberately unlabeled, like the desktop list — a
/// container label would make the screen reader prefix every row with it.
/// Editable rows (everything except emoji) carry Edit/Delete as swipe
/// actions and as VoiceOver custom actions, so they show up in the rotor.
struct ResultsList: View {
    @Bindable var model: AppModel
    var onActivate: (ResultItem) -> Void
    var onEdit: (ResultItem) -> Void

    var body: some View {
        List(model.results) { item in
            let row = ResultRow(item: item) {
                onActivate(item)
            }
            if item.isEditable {
                row
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.delete(item)
                        }
                        Button("Edit", systemImage: "pencil") {
                            onEdit(item)
                        }
                    }
                    .accessibilityAction(named: "Edit") {
                        onEdit(item)
                    }
                    .accessibilityAction(named: "Delete") {
                        model.delete(item)
                    }
            } else {
                row
            }
        }
        .listStyle(.plain)
    }
}
