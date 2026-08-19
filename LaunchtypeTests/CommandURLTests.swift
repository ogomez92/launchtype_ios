import Foundation
import Testing
@testable import Launchtype

struct CommandURLTests {
    private func command(path: String, args: String?) -> Command {
        Command(path: path, name: "test", args: args, shortcut: nil, id: "id")
    }

    @Test func browserPlaceholderWithFullURLIsShown() {
        let url = CommandURL.launchURL(for: command(
            path: "{{firefox}}",
            args: "https://meet.gomsen.com/radio#config.startWithVideoMuted=true"
        ))
        #expect(url?.absoluteString == "https://meet.gomsen.com/radio#config.startWithVideoMuted=true")
    }

    @Test func browserWithBareDomainGetsHTTPS() {
        let url = CommandURL.launchURL(for: command(path: "{{chrome}}", args: "gmail.com"))
        #expect(url?.absoluteString == "https://gmail.com")
    }

    @Test func literalChromeExePathCountsAsBrowser() {
        let url = CommandURL.launchURL(for: command(
            path: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
            args: "gmail.com"
        ))
        #expect(url?.absoluteString == "https://gmail.com")
    }

    @Test func exeCommandWithPathArgsIsHidden() {
        let url = CommandURL.launchURL(for: command(
            path: "D:\\bin\\xp.exe",
            args: "{{home}}\\games\\Mush-z\\worlds\\alteraeon\\aasets"
        ))
        #expect(url == nil)
    }

    @Test func editorWithFlagsIsHidden() {
        let url = CommandURL.launchURL(for: command(
            path: "{{programfiles}}\\Microsoft VS Code\\Code.exe",
            args: "-n, temp"
        ))
        #expect(url == nil)
    }

    @Test func driveLetterIsNotAScheme() {
        #expect(!CommandURL.looksLikeURL("D:\\bin\\xp.exe"))
        #expect(!CommandURL.looksLikeURL("C:/things"))
        #expect(CommandURL.looksLikeURL("https://x.com"))
        #expect(CommandURL.looksLikeURL("steam://rungameid/12"))
        #expect(CommandURL.looksLikeURL("mailto:a@b.c"))
    }

    @Test func urlContainingACommaSurvivesWhole() {
        let url = CommandURL.launchURL(for: command(
            path: "{{firefox}}",
            args: "https://example.com/path?a=1,b=2"
        ))
        #expect(url?.absoluteString == "https://example.com/path?a=1,b=2")
    }

    @Test func nonBrowserBareDomainIsNotRewritten() {
        // Only a browser may assume a bare domain is a website.
        let url = CommandURL.launchURL(for: command(path: "D:\\bin\\thing.exe", args: "notes.txt"))
        #expect(url == nil)
    }

    @Test func argSegmentsSplitTrimAndUnquote() {
        #expect(CommandURL.argSegments("-n, temp") == ["-n", "temp"])
        #expect(CommandURL.argSegments(" \"a b\" , c ") == ["a b", "c"])
        #expect(CommandURL.argSegments("   ") == [])
    }
}
