import AVFoundation

/// The desktop app's sound cues, played from `Documents/sounds` (so the user
/// can swap them through the Files app) with the bundled seed copies as a
/// fallback. The audio session is ambient and mixes with others so VoiceOver
/// speech is never ducked or interrupted.
@MainActor
final class SoundPlayer {
    enum Cue: String {
        case logo
        case show
        case hide
        case type
        case match
        case run
        case copy
        case timer
        case alarm
        /// Something was refused: a wrong master password, a vault file that
        /// will not open.
        case error
    }

    var enabled: Bool

    /// AVAudioPlayer is non-Sendable; every instance is created, retained, and
    /// played only inside this main-actor class.
    private var players: [String: AVAudioPlayer] = [:]

    init(enabled: Bool) {
        self.enabled = enabled
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ cue: Cue) {
        // alarm ships as flac; every other cue is a wav.
        let fileName = cue == .alarm ? "alarm.flac" : "\(cue.rawValue).wav"
        playFile(named: fileName)
    }

    /// A timer/alarm alert: the definition's own sound file when set,
    /// otherwise the given cue.
    func playAlert(named name: String?, fallback: Cue) {
        if let name, !name.isEmpty {
            playFile(named: name)
        } else {
            play(fallback)
        }
    }

    private func playFile(named name: String) {
        guard enabled, let url = resolve(name) else {
            return
        }
        if let player = players[url.path()] {
            player.currentTime = 0
            player.play()
            return
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }
        players[url.path()] = player
        player.play()
    }

    /// A missing file is a silent no-op, like the desktop app.
    private func resolve(_ name: String) -> URL? {
        let documents = AppDirectories.sounds.appending(path: name)
        if FileManager.default.fileExists(atPath: documents.path()) {
            return documents
        }
        let bundled = AppDirectories.seedData?.appending(path: "sounds/\(name)")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path()) {
            return bundled
        }
        return nil
    }
}
