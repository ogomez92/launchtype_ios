import Testing
@testable import Launchtype

struct SnippetTests {
    @Test func shortcutIsFileNameUpToFirstDotLowercased() {
        #expect(Snippet(fileName: "CC.txt", content: "x").shortcut == "cc")
        #expect(Snippet(fileName: "steam_code.txt", content: "x").shortcut == "steam_code")
        #expect(Snippet(fileName: "cl6.txt", content: "x").shortcut == "cl6")
        #expect(Snippet(fileName: "linea diosa holga honduras.txt", content: "x").shortcut
            == "linea diosa holga honduras")
        #expect(Snippet(fileName: "a.b.txt", content: "x").shortcut == "a")
        #expect(Snippet(fileName: "noext", content: "x").shortcut == "noext")
    }

    @Test func searchKeyIsShortcutThenContents() {
        let snippet = Snippet(fileName: "ip.txt", content: "192.168.1.1")
        #expect(snippet.searchKey == "ip 192.168.1.1")
    }
}
