import SwiftUI

/// Routes the presented `EditorSheet` case to its concrete editor form.
struct EditorSheetView: View {
    let sheet: EditorSheet
    var model: AppModel

    var body: some View {
        switch sheet {
        case .newCommand:
            CommandEditor(original: nil) { model.saveCommand($0) }
        case .editCommand(let command):
            CommandEditor(original: command) { model.saveCommand($0) }
        case .newSnippet:
            snippetEditor(original: nil)
        case .editSnippet(let snippet):
            snippetEditor(original: snippet)
        case .newTimer:
            TimerEditor(original: nil) { model.saveTimer($0, isNew: true) }
        case .editTimer(let timer):
            TimerEditor(original: timer) { model.saveTimer($0, isNew: false) }
        case .newAlarm:
            AlarmEditor(original: nil) { model.saveAlarm($0) }
        case .editAlarm(let alarm):
            AlarmEditor(original: alarm) { model.saveAlarm($0) }
        case .newVaultEntry:
            VaultEntryEditor(original: nil) { model.saveVaultEntry($0) }
        case .editVaultEntry(let draft):
            VaultEntryEditor(original: draft) { model.saveVaultEntry($0) }
        case .vaultUnlock:
            VaultUnlockSheet { await model.unlockVault(password: $0) }
        case .vaultSetup:
            VaultPasswordSheet(purpose: .setup) { _, new in
                await model.createVault(password: new)
            }
        case .vaultChangePassword:
            VaultPasswordSheet(purpose: .change) { current, new in
                await model.changeVaultPassword(current: current, new: new)
            }
        }
    }

    private func snippetEditor(original: Snippet?) -> some View {
        SnippetEditor(
            original: original,
            isShortcutTaken: { model.snippetsStore.isShortcutTaken($0, excluding: original) },
            onSave: { model.saveSnippet(shortcut: $0, content: $1, replacing: original) }
        )
    }
}
