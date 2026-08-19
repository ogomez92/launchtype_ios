import Foundation
import UserNotifications

/// The root model: current mode, the query, and the per-keystroke pipeline —
/// exact shortcut match beats fuzzy search, sounds and VoiceOver announcements
/// mirror the desktop app.
@MainActor
@Observable
final class AppModel {
    var mode: Mode = .commands
    var query = ""

    let settings: AppSettings
    let sounds: SoundPlayer
    let announcer = Announcer()
    let scheduler: NotificationScheduler
    let commandsStore: CommandsStore
    let snippetsStore: SnippetsStore
    let timerStore: TimerStore
    let alarmStore: AlarmStore
    let vault: VaultSession
    let notificationDelegate = NotificationDelegate()

    /// The presented sheet — an editor, or one of the vault's password
    /// prompts. Owned here rather than by the view because the vault decides
    /// which prompt is due (unlock, or set up the first time).
    var editor: EditorSheet?

    /// A vault entry waiting on the "this cannot be undone" confirmation.
    var pendingVaultDeletion: VaultEntry?

    /// The number of unopenable entry files found when setting up a vault
    /// over the top of them; non-nil while that warning is up.
    var vaultOrphanWarning: Int?

    /// A vault folder that has been read and checked, waiting on confirmation
    /// because writing it would replace the vault already on this device.
    var pendingVaultImport: VaultImport.Candidate?

    /// A vault failure worth interrupting the user for. A mistyped master
    /// password is not one of these — that is answered in the unlock sheet.
    var vaultErrorMessage: String?

    /// Emoji results are capped like the desktop's EMOJI_LIMIT.
    private static let emojiLimit = 200

    /// How often the auto-lock sweep looks at the clock. The deadline is in
    /// minutes, so there is nothing to gain from waking more often.
    private static let lockCheckInterval = Duration.seconds(5)

    @ObservationIgnored private var announceTask: Task<Void, Never>?
    @ObservationIgnored private var lockTask: Task<Void, Never>?
    @ObservationIgnored private var clipboardClearTask: Task<Void, Never>?

    init() {
        DataBootstrap.run()
        let settingsStore = SettingsStore()
        settings = settingsStore.settings
        sounds = SoundPlayer(enabled: settings.enableSounds)
        scheduler = NotificationScheduler()
        commandsStore = CommandsStore(
            fileName: settings.commandsFile,
            sortByUses: settings.commandSortByUses
        )
        snippetsStore = SnippetsStore()
        timerStore = TimerStore(sounds: sounds, announcer: announcer, scheduler: scheduler)
        alarmStore = AlarmStore(scheduler: scheduler)
        // Nothing is read or decrypted here: the vault is a locked door until
        // the user goes to `*` mode and gives it the master password.
        vault = VaultSession(lockAfterMinutes: settings.vaultLockMinutes)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        notificationDelegate.onForegroundDelivery = { [weak self] identifier in
            self?.notificationArrivedInForeground(id: identifier)
        }
        startAutoLock()
        sounds.play(.logo)
    }

    /// The rows for the current mode and query. Computed so timer countdown
    /// ticks and store updates flow into the list through observation.
    var results: [ResultItem] {
        buildResults().items
    }

    // MARK: - Query pipeline

    /// Wire this to `onChange(of: query)`. Handles trigger characters, plays
    /// the type/match cue, and schedules the results announcement.
    func queryChanged(from oldValue: String, to newValue: String) {
        if oldValue.isEmpty, newValue.count == 1, let character = newValue.first,
           let target = Mode.forTrigger(character) {
            if target == mode {
                // Re-announce rather than switch; the char is still consumed.
                query = ""
                announcer.say(mode.announcement, high: true)
            } else {
                mode = target
            }
            return
        }
        guard oldValue != newValue else {
            return
        }
        let built = buildResults()
        if !newValue.isEmpty {
            sounds.play(built.exactShortcutHit ? .match : .type)
        }
        scheduleAnnouncement(for: built, immediate: built.exactShortcutHit)
    }

    /// Wire this to `onChange(of: mode)` — from the tabs or a trigger char.
    func modeChanged() {
        query = ""
        announceTask?.cancel()
        announcer.say(mode.announcement, high: true)
        if mode == .vault {
            enterVaultMode()
        }
    }

    // MARK: - Activation

    /// Run a row. Returns a URL for the caller to open (commands mode);
    /// everything else completes here.
    func activate(_ item: ResultItem) -> URL? {
        switch item.kind {
        case .command(let command, let url):
            sounds.play(.run)
            commandsStore.recordRun(id: command.id)
            return url
        case .snippet(let snippet):
            Pasteboard.copy(snippet.content)
            sounds.play(.copy)
            announcer.say("\(snippet.shortcut) copied", high: true)
        case .emoji(let entry):
            Pasteboard.copy(entry.emoji)
            sounds.play(.copy)
            announcer.say("\(entry.name) copied", high: true)
        case .timer(let timer):
            if let active = timerStore.toggle(timer.id) {
                sounds.play(.match)
                announcer.say(active ? "Timer started" : "Timer stopped", high: true)
            }
        case .alarm(let alarm):
            if let enabled = alarmStore.toggle(alarm.id) {
                sounds.play(.match)
                announcer.say(enabled ? "Alarm on" : "Alarm off", high: true)
            }
        case .vaultEntry(let entry):
            copySecret(for: entry)
        case .vaultAction(let action):
            run(action)
        }
        return nil
    }

    /// Return-key handling: run the first result.
    func activateFirst() -> URL? {
        guard let first = results.first else {
            return nil
        }
        return activate(first)
    }

    // MARK: - Add, edit, delete, export

    /// The header button: add something to the current mode. The vault has to
    /// be open first, so a locked one asks for the master password instead and
    /// the user presses Add again afterwards.
    func add() {
        if mode == .vault, !vault.isUnlocked {
            enterVaultMode()
            return
        }
        editor = EditorSheet.newItem(for: mode)
    }

    /// Edit the thing behind a row. A vault entry is decrypted here, which is
    /// the only reason this is not a pure function of the row.
    func edit(_ item: ResultItem) {
        switch item.kind {
        case .command(let command, _):
            editor = .editCommand(command)
        case .snippet(let snippet):
            editor = .editSnippet(snippet)
        case .timer(let timer):
            editor = .editTimer(timer)
        case .alarm(let alarm):
            editor = .editAlarm(alarm)
        case .vaultEntry(let entry):
            guard vault.isUnlocked else {
                enterVaultMode()
                return
            }
            do {
                editor = .editVaultEntry(try vault.draft(id: entry.id))
            } catch {
                report(error)
            }
        case .emoji, .vaultAction:
            return
        }
    }

    /// Delete the thing behind a row. Emoji rows are the built-in catalog and
    /// cannot be deleted; a vault entry is the only copy of whatever it holds,
    /// so it goes through a confirmation rather than straight to the disk.
    func delete(_ item: ResultItem) {
        switch item.kind {
        case .command(let command, _):
            commandsStore.delete(id: command.id)
        case .snippet(let snippet):
            snippetsStore.delete(snippet)
        case .timer(let timer):
            timerStore.delete(id: timer.id)
        case .alarm(let alarm):
            alarmStore.delete(id: alarm.id)
        case .vaultEntry(let entry):
            guard vault.isUnlocked else {
                enterVaultMode()
                return
            }
            pendingVaultDeletion = entry
            return
        case .emoji, .vaultAction:
            return
        }
        sounds.play(.hide)
        announcer.say("\(item.label) deleted", high: true)
    }

    func saveCommand(_ command: Command) {
        commandsStore.upsert(command)
        confirmSave()
    }

    func saveSnippet(shortcut: String, content: String, replacing original: Snippet?) {
        snippetsStore.save(shortcut: shortcut, content: content, replacing: original)
        confirmSave()
    }

    func saveTimer(_ timer: TimerDef, isNew: Bool) {
        if isNew {
            timerStore.add(timer)
        } else {
            timerStore.update(timer)
        }
        confirmSave()
    }

    func saveAlarm(_ alarm: AlarmDef) {
        alarmStore.upsert(alarm)
        confirmSave()
    }

    private func confirmSave() {
        sounds.play(.match)
        announcer.say("Saved", high: true)
    }

    /// Import a backup zip picked in the Files browser: validate, write into
    /// Documents, and reload every store so the new data is live at once.
    /// Returns an error message for the caller to alert, or nil on success.
    func importBackup(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let summary = try DataArchive.importZip(at: url)
            DataBootstrap.syncNotificationSounds()
            commandsStore.reload()
            snippetsStore.reload()
            timerStore.reload()
            alarmStore.reload()
            // The backup may have brought its own vault with it, in which case
            // the key in memory belongs to a vault that is no longer there.
            vault.lock()
            sounds.play(.match)
            announcer.say(summary.announcement, high: true)
            return nil
        } catch {
            sounds.play(.hide)
            let message = error.localizedDescription
            announcer.say("Import failed. \(message)", high: true)
            return message
        }
    }

    // MARK: - The vault

    /// Arriving in vault mode: open it, or set one up the first time.
    ///
    /// Cancelling the sheet leaves the mode showing its one row, so activating
    /// that row tries again rather than stranding the user.
    func enterVaultMode() {
        guard !vault.isUnlocked else {
            // Arriving counts as using it, so browsing does not run into the
            // idle timeout mid-search.
            vault.touch()
            return
        }
        if vault.isNew {
            // Through `run` rather than straight to the sheet, so setting up
            // over the top of unopenable entry files asks first here too.
            run(.create)
        } else {
            editor = .vaultUnlock
        }
    }

    /// Activate one of the rows that is an instruction rather than an entry.
    func run(_ action: VaultAction) {
        switch action {
        case .create:
            // Encrypted entries with no key file next to them cannot be opened
            // by any password, and a fresh vault would quietly bury them.
            let orphans = vault.orphanCount
            if orphans > 0 {
                vaultOrphanWarning = orphans
            } else {
                editor = .vaultSetup
            }
        case .unlock:
            editor = .vaultUnlock
        case .lock:
            vault.lock()
            sounds.play(.match)
            announcer.say("Vault locked", high: true)
        case .add:
            add()
        case .changePassword:
            editor = .vaultChangePassword
        }
    }

    /// Go ahead with a setup that will leave unopenable entry files behind.
    func confirmVaultSetup() {
        vaultOrphanWarning = nil
        editor = .vaultSetup
    }

    /// Open the vault. Returns whether it opened, so the sheet can stay up
    /// with the field ready when the password was wrong — the desktop leaves
    /// its row in place for the same reason.
    func unlockVault(password: String) async -> Bool {
        do {
            try await vault.unlock(password: password)
            sounds.play(.match)
            let count = vault.entries.count
            announcer.say(count == 1 ? "Vault unlocked, 1 entry" : "Vault unlocked, \(count) entries", high: true)
            return true
        } catch {
            reportQuietly(error)
            return false
        }
    }

    /// Create the vault and leave it unlocked.
    func createVault(password: String) async -> Bool {
        do {
            try await vault.create(password: password)
            sounds.play(.match)
            announcer.say("The vault is ready and unlocked.", high: true)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Re-wrap the vault key under a new master password. Instant: the entries
    /// were never encrypted with the password itself.
    func changeVaultPassword(current: String, new: String) async -> Bool {
        do {
            try await vault.changePassword(current: current, new: new)
            sounds.play(.match)
            announcer.say("Master password changed", high: true)
            return true
        } catch {
            reportQuietly(error)
            return false
        }
    }

    /// Save an added or edited entry.
    func saveVaultEntry(_ draft: VaultEntryDraft) {
        do {
            try vault.save(
                id: draft.id,
                name: draft.name,
                shortcut: draft.shortcut,
                secret: draft.secret
            )
            vault.touch()
            sounds.play(.match)
            announcer.say(draft.id == nil ? "Added to the vault" : "Vault entry saved", high: true)
        } catch {
            report(error)
        }
    }

    /// Delete the confirmed entry. There is no undo and no other copy.
    func confirmVaultDeletion() {
        guard let entry = pendingVaultDeletion else {
            return
        }
        pendingVaultDeletion = nil
        do {
            try vault.delete(id: entry.id)
            vault.touch()
            sounds.play(.hide)
            announcer.say("Deleted from the vault", high: true)
        } catch {
            report(error)
        }
    }

    /// Activating an entry: decrypt it, put it on the clipboard, and get out
    /// of the way so it can be pasted.
    private func copySecret(for entry: VaultEntry) {
        // The vault may have auto-locked with this very list still on screen,
        // so this asks for the password and carries on rather than reporting a
        // failure the user can do nothing useful with.
        guard vault.isUnlocked else {
            enterVaultMode()
            return
        }
        do {
            let secret = try vault.secret(id: entry.id)
            let seconds = settings.vaultClipboardSeconds
            Pasteboard.copySecret(secret, expiringAfter: seconds)
            scheduleClipboardClear(after: seconds)
            vault.touch()
            if vault.locksOnUse {
                vault.lock()
            }
            sounds.play(.copy)
            announcer.say("\(entry.name) copied", high: true)
        } catch {
            report(error)
        }
    }

    /// Take the secret back off the clipboard once it has had long enough to
    /// be pasted, unless something else has been copied in the meantime.
    ///
    /// The pasteboard has already been told to expire the secret by itself, so
    /// this is the belt to that pair of braces — it is what clears the secret
    /// promptly while the app is still in the foreground, and it holds the
    /// same "only if it is still ours" rule by comparing the change count
    /// rather than reading the contents back.
    private func scheduleClipboardClear(after seconds: Int) {
        clipboardClearTask?.cancel()
        guard seconds > 0 else {
            return
        }
        let stamp = Pasteboard.changeCount
        clipboardClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self != nil, Pasteboard.changeCount == stamp else {
                return
            }
            Pasteboard.clear()
        }
    }

    /// Wipe the key once the vault has gone unused for long enough.
    ///
    /// This is what makes the timeout real rather than nominal: without it the
    /// key would sit in this process until someone happened to open the vault
    /// again. It locks silently — auto-locking happens while the user is off
    /// doing something else, and interrupting that to report a background
    /// event nobody asked about is worse than saying nothing.
    private func startAutoLock() {
        lockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.lockCheckInterval)
                guard let self else {
                    return
                }
                // Someone typing a secret into the editor is using the vault,
                // even though nothing has been saved yet: locking under them
                // would throw away what they had typed when they pressed Save.
                if vaultSheetIsOpen {
                    vault.touch()
                } else {
                    vault.expire()
                }
            }
        }
    }

    /// Whether a sheet that needs the vault open is up.
    private var vaultSheetIsOpen: Bool {
        switch editor {
        case .newVaultEntry, .editVaultEntry, .vaultChangePassword: true
        default: false
        }
    }

    /// Called when the app comes back to the foreground. Sleeping tasks do not
    /// run while the app is suspended, so the sweep above may have missed the
    /// deadline by hours; this applies the same rule the moment it can matter
    /// again.
    func sceneBecameActive() {
        vault.expire()
    }

    /// Import a vault folder picked in the Files browser — the `vault` folder
    /// from a desktop install, copied over as it is. Nothing is decrypted:
    /// the same master password opens it here.
    func importVault(from url: URL) {
        do {
            let candidate = try VaultImport.candidate(at: url)
            // Replacing the key file would leave any entries already on this
            // device unopenable, so that case is confirmed rather than done.
            if VaultImport.wouldReplaceExistingVault() {
                pendingVaultImport = candidate
                return
            }
            finishVaultImport(candidate)
        } catch {
            report(error)
        }
    }

    /// Go ahead with an import that replaces the vault on this device.
    func confirmVaultImport() {
        guard let candidate = pendingVaultImport else {
            return
        }
        pendingVaultImport = nil
        finishVaultImport(candidate)
    }

    private func finishVaultImport(_ candidate: VaultImport.Candidate) {
        do {
            let summary = try VaultImport.write(candidate)
            // Whatever was open belonged to the vault that has just been
            // replaced; the imported one needs its own password.
            vault.lock()
            mode = .vault
            sounds.play(.match)
            announcer.say(summary.announcement, high: true)
        } catch {
            report(error)
        }
    }

    /// A vault failure the user has to be told about, with an alert.
    private func report(_ error: Error) {
        sounds.play(.error)
        vaultErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// A vault failure that the sheet the user is looking at will show for
    /// itself — a mistyped master password, above all, which is not worth an
    /// alert when the field to try again in is right there.
    private func reportQuietly(_ error: Error) {
        sounds.play(.error)
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        announcer.say(message, high: true)
    }

    /// A timer or alarm notification arrived while the app was frontmost: the
    /// system banner is suppressed, so replay the cue and speak it ourselves.
    func notificationArrivedInForeground(id: String) {
        if let alarm = alarmStore.alarm(withId: id) {
            sounds.playAlert(named: alarm.sound, fallback: .alarm)
            let message = alarm.description.isEmpty ? alarm.title : "\(alarm.title): \(alarm.description)"
            announcer.say(message, high: true)
        }
        // Foreground timer fires are already handled by TimerStore's tick loop.
    }

    // MARK: - Building results

    private func buildResults() -> (items: [ResultItem], exactShortcutHit: Bool) {
        let search = query.lowercased()
        switch mode {
        case .commands:
            return commandResults(search: search)
        case .snippets:
            return snippetResults(search: search)
        case .emoji:
            let entries = EmojiRanker.search(language: settings.emojiLanguage, query: search)
            // The row shows the name only — never the glyph, which a screen
            // reader would speak twice.
            let items = entries.prefix(Self.emojiLimit).map { entry in
                ResultItem(id: entry.emoji, label: entry.name, kind: .emoji(entry))
            }
            return (Array(items), false)
        case .timers:
            _ = timerStore.tickCount
            let timers = SearchScorer.fuzzySearch(search, timerStore.timers) { $0.title }
            let items = timers.map { timer in
                ResultItem(id: timer.id, label: timerStore.label(for: timer), kind: .timer(timer))
            }
            return (items, false)
        case .alarms:
            let alarms = SearchScorer.fuzzySearch(search, alarmStore.alarms) { $0.title }
            let items = alarms.map { alarm in
                ResultItem(id: alarm.id, label: alarm.label, kind: .alarm(alarm))
            }
            return (items, false)
        case .vault:
            return vaultResults(search: search)
        }
    }

    /// The encrypted vault: a single row while locked, the entry names once
    /// open.
    ///
    /// Entry rows carry names and shortcuts only — never a secret. Searching
    /// behaves like every other mode (exact shortcut wins, then fuzzy), and
    /// the action rows are appended only when nothing is typed, so they never
    /// come between the user and the entry they are looking for.
    private func vaultResults(search: String) -> (items: [ResultItem], exactShortcutHit: Bool) {
        guard vault.isUnlocked else {
            // Nothing to search until the key is in memory, so the typed text
            // is ignored rather than filtering the one row away.
            let action: VaultAction = vault.isNew ? .create : .unlock
            return ([vaultActionItem(action)], false)
        }
        let entries = vault.entries
        if let hit = SearchScorer.exactShortcutMatch(search, entries, shortcut: { $0.shortcut }) {
            return ([vaultItem(hit)], true)
        }
        var items = SearchScorer.fuzzySearch(search, entries) { $0.name }.map(vaultItem)
        if search.isEmpty {
            if entries.isEmpty {
                items.append(vaultActionItem(.add))
            }
            items.append(vaultActionItem(.lock))
            items.append(vaultActionItem(.changePassword))
        }
        return (items, false)
    }

    private func vaultItem(_ entry: VaultEntry) -> ResultItem {
        ResultItem(id: entry.id, label: entry.label, kind: .vaultEntry(entry))
    }

    private func vaultActionItem(_ action: VaultAction) -> ResultItem {
        ResultItem(id: "action-\(action.id)", label: action.label, kind: .vaultAction(action))
    }

    private func commandResults(search: String) -> (items: [ResultItem], exactShortcutHit: Bool) {
        let visible = commandsStore.visible
        if let hit = SearchScorer.exactShortcutMatch(search, visible, shortcut: { $0.command.shortcut }) {
            return ([commandItem(hit)], true)
        }
        let matched = SearchScorer.fuzzySearch(search, visible) { $0.command.name }
        return (matched.map(commandItem), false)
    }

    private func commandItem(_ visible: CommandsStore.VisibleCommand) -> ResultItem {
        let shortcut = visible.command.shortcut ?? ""
        let label = shortcut.isEmpty
            ? visible.command.name
            : "\(visible.command.name) (\(shortcut))"
        return ResultItem(id: visible.command.id, label: label, kind: .command(visible.command, visible.url))
    }

    private func snippetResults(search: String) -> (items: [ResultItem], exactShortcutHit: Bool) {
        let snippets = snippetsStore.snippets
        if let hit = SearchScorer.exactShortcutMatch(search, snippets, shortcut: { $0.shortcut }) {
            return ([snippetItem(hit)], true)
        }
        let matched = SearchScorer.fuzzySearch(search, snippets) { $0.searchKey }
        return (matched.map(snippetItem), false)
    }

    private func snippetItem(_ snippet: Snippet) -> ResultItem {
        let collapsed = snippet.content
            .replacing("\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return ResultItem(
            id: snippet.id,
            label: "\(collapsed) (\(snippet.shortcut))",
            kind: .snippet(snippet)
        )
    }

    // MARK: - Announcements

    /// The desktop narration: the first result plus how many more there are.
    /// Debounced so fast typing does not queue a stack of stale speech; an
    /// exact shortcut hit speaks immediately because it is action-ready.
    private func scheduleAnnouncement(for built: (items: [ResultItem], exactShortcutHit: Bool), immediate: Bool) {
        announceTask?.cancel()
        guard !query.isEmpty else {
            return
        }
        let text: String
        if built.items.isEmpty {
            text = "no results"
        } else if built.items.count == 1 {
            text = built.items[0].label
        } else {
            let first = built.items[0].label
            text = "\(first), \(built.items.count) search results shown, use down arrow to access more results"
        }
        if immediate {
            announcer.say(text)
            return
        }
        announceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            announcer.say(text)
        }
    }
}
