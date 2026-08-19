import SwiftUI

/// The vault's alerts: the three questions that must be asked before
/// something irreversible, and the failures worth interrupting for.
///
/// They live in one modifier rather than in `ContentView` because they are all
/// driven by the same model state and none of them belongs to the launcher's
/// own screen.
struct VaultPrompts: ViewModifier {
    @Bindable var model: AppModel
    /// Called after any of these closes, so the search field gets the keyboard
    /// back — typing is the whole interface.
    var onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete vault entry",
                isPresented: presenting($model.pendingVaultDeletion),
                presenting: model.pendingVaultDeletion
            ) { entry in
                Button("Delete", role: .destructive) {
                    model.confirmVaultDeletion()
                    onDismiss()
                }
                Button("Cancel", role: .cancel) {
                    model.pendingVaultDeletion = nil
                    onDismiss()
                }
            } message: { entry in
                Text("Delete \(entry.name) from the vault? The secret in it cannot be recovered afterwards.")
            }
            .alert(
                "Vault key file missing",
                isPresented: presenting($model.vaultOrphanWarning),
                presenting: model.vaultOrphanWarning
            ) { _ in
                Button("Set up a new vault", role: .destructive) {
                    model.confirmVaultSetup()
                }
                Button("Cancel", role: .cancel) {
                    model.vaultOrphanWarning = nil
                    onDismiss()
                }
            } message: { count in
                Text("""
                The vault folder holds \(count) encrypted files, but the key file that \
                goes with them is missing, so nothing can open them any more. Set up a \
                new, empty vault anyway?
                """)
            }
            .alert(
                "Replace this device's vault?",
                isPresented: presenting($model.pendingVaultImport),
                presenting: model.pendingVaultImport
            ) { candidate in
                Button("Replace", role: .destructive) {
                    model.confirmVaultImport()
                    onDismiss()
                }
                Button("Cancel", role: .cancel) {
                    model.pendingVaultImport = nil
                    onDismiss()
                }
            } message: { candidate in
                Text("""
                There is already a vault on this device. Importing \(candidate.entryCount) \
                entries over it replaces its key file, and any entries already here will \
                stop opening.
                """)
            }
            .alert(
                "Vault",
                isPresented: presenting($model.vaultErrorMessage),
                presenting: model.vaultErrorMessage
            ) { _ in
                Button("OK") {
                    model.vaultErrorMessage = nil
                    onDismiss()
                }
            } message: { message in
                Text(message)
            }
    }

    /// An optional read as "is something presented", which is the shape
    /// SwiftUI's alerts want. Setting it false clears the value, so dismissing
    /// by any route — including the system's own — leaves no stale state.
    private func presenting<Value>(_ binding: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue != nil },
            set: { presented in
                if !presented {
                    binding.wrappedValue = nil
                }
            }
        )
    }
}

extension View {
    func vaultPrompts(model: AppModel, onDismiss: @escaping () -> Void) -> some View {
        modifier(VaultPrompts(model: model, onDismiss: onDismiss))
    }
}
