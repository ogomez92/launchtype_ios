import UIKit
import UniformTypeIdentifiers

/// The one deliberate UIKit import in the app: there is no SwiftUI API for
/// writing to the clipboard on iOS, so `UIPasteboard` is wrapped here and
/// nowhere else.
@MainActor
enum Pasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Copy a vault secret, on the terms a password deserves.
    ///
    /// Two things separate this from ``copy(_:)``, and both are asked of the
    /// system rather than of us, so they hold even if the app is killed a
    /// second later:
    ///
    /// - `localOnly` keeps the secret off Universal Clipboard, which would
    ///   otherwise hand it to every other device signed into the account.
    /// - `expirationDate` has the pasteboard drop the secret by itself after
    ///   `seconds`, which is the desktop app's "take it back off the clipboard
    ///   once it has had long enough to be pasted". 0 means never, and is the
    ///   only case where the secret is left there indefinitely.
    static func copySecret(_ secret: String, expiringAfter seconds: Int) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if seconds > 0 {
            options[.expirationDate] = Date.now.addingTimeInterval(TimeInterval(seconds))
        }
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: secret]],
            options: options
        )
    }

    /// Empty the clipboard.
    static func clear() {
        UIPasteboard.general.items = []
    }

    /// Bumped by every write to the pasteboard, by any app. Recorded when a
    /// secret is copied so the delayed clear can tell "still ours" from
    /// "something else has been copied since" — without reading the contents
    /// back, which is a privacy prompt the user should not have to see.
    static var changeCount: Int {
        UIPasteboard.general.changeCount
    }
}
