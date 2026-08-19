import SwiftUI

/// One result row: a button whose label is exactly what VoiceOver should say.
struct ResultRow: View {
    let item: ResultItem
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(item.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
    }
}
