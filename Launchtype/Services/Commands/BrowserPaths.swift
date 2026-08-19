import Foundation

/// Recognizing "this command's path is a web browser" — the ported browser
/// placeholder and executable tables from the desktop `portable.rs`. Only a
/// browser path may treat a bare `gmail.com` argument as a website.
enum BrowserPaths {
    /// Browser placeholder names, `{{browser}}` being the OS default handler.
    static let placeholders: Set<String> = [
        "browser", "chrome", "firefox", "edge", "brave", "vivaldi", "opera", "safari",
    ]

    /// Executable/app names that identify a browser, matched on the path's
    /// file name so an unusual install location still counts.
    private static let executables: Set<String> = [
        "chrome.exe", "google chrome", "google chrome.app",
        "firefox.exe", "firefox", "firefox.app",
        "msedge.exe", "microsoft edge", "microsoft edge.app",
        "brave.exe", "brave browser", "brave browser.app",
        "vivaldi.exe", "vivaldi", "vivaldi.app",
        "opera.exe", "opera", "opera.app",
        "safari", "safari.app",
    ]

    static func isBrowserPath(_ path: String) -> Bool {
        let lowered = path.lowercased()
        for name in placeholders where lowered.contains("{{\(name)}}") {
            return true
        }
        let fileName = lowered
            .split(whereSeparator: { $0 == "\\" || $0 == "/" })
            .last(where: { !$0.isEmpty })
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if executables.contains(fileName) {
            return true
        }
        // Opera's launcher.exe only counts inside an Opera folder; the name is
        // far too generic to claim on its own.
        return fileName == "launcher.exe" && lowered.contains("opera")
    }
}
