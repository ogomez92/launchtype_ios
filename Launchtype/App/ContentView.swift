import SwiftUI
import UniformTypeIdentifiers

/// The single screen: mode tabs, the always-focused search field, and the
/// results list. VoiceOver reading order is tabs → field → results. The
/// header carries the mode-dependent Add button (leading) and the backup
/// menu — export everything as a zip, import a backup zip, import a vault
/// folder from the desktop app (trailing).
struct ContentView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var importingVault = false
    @State private var importFailed = false
    @State private var importErrorMessage = ""

    var body: some View {
        NavigationStack {
            VStack {
                ModeTabs(model: model)
                SearchField(model: model, focused: $searchFocused) {
                    open(model.activateFirst())
                }
                ResultsList(model: model) { item in
                    open(model.activate(item))
                } onEdit: { item in
                    model.edit(item)
                }
            }
            .navigationTitle("Launchtype")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if EditorSheet.newItem(for: model.mode) != nil {
                        Button("Add \(model.mode.itemName)", systemImage: "plus") {
                            model.add()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Backup", systemImage: "square.and.arrow.up") {
                        ShareLink(
                            item: BackupArchive(),
                            preview: SharePreview("Launchtype backup")
                        ) {
                            Label("Export all data", systemImage: "square.and.arrow.up")
                        }
                        Button("Import backup", systemImage: "square.and.arrow.down") {
                            importing = true
                        }
                        Button("Import vault folder", systemImage: "lock.square") {
                            importingVault = true
                        }
                    }
                }
            }
        }
        .sheet(item: $model.editor) {
            // The keyboard must never drop — typing is the whole interface.
            searchFocused = true
        } content: { sheet in
            EditorSheetView(sheet: sheet, model: model)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result,
               let message = model.importBackup(from: url) {
                importErrorMessage = message
                importFailed = true
            }
            searchFocused = true
        }
        // The vault travels as a folder — `vault.meta` plus one file per
        // entry — so this picks the folder itself rather than an archive.
        .fileImporter(isPresented: $importingVault, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.importVault(from: url)
            }
            searchFocused = true
        }
        .alert("Import failed", isPresented: $importFailed) {
            Button("OK") {
                searchFocused = true
            }
        } message: {
            Text(importErrorMessage)
        }
        .vaultPrompts(model: model) {
            searchFocused = true
        }
        .onAppear {
            searchFocused = true
        }
        .onChange(of: scenePhase) { _, phase in
            // Sleeping tasks do not run while the app is suspended, so the
            // vault's idle deadline is applied again the moment it can matter.
            if phase == .active {
                model.sceneBecameActive()
            }
        }
        .onChange(of: model.mode) {
            model.modeChanged()
            searchFocused = true
        }
        .onChange(of: model.query) { oldValue, newValue in
            model.queryChanged(from: oldValue, to: newValue)
        }
    }

    private func open(_ url: URL?) {
        if let url {
            openURL(url)
        }
        // The keyboard must never drop — typing is the whole interface.
        searchFocused = true
    }
}
