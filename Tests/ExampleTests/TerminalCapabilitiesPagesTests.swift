//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilitiesPagesTests.swift
//
//  Where the Example says what this terminal can do (`\.terminalCapabilities`):
//  the Text Styles page's notes after a sample the terminal does not draw as
//  asked, or that nobody has measured, and the Terminal page's list.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
@testable import TUIFoundation
@testable import TUITerminalHost
import TUITesting

@MainActor
@Suite("The Example's notes on what this terminal can do")
struct TerminalCapabilitiesPagesTests {
    /// The line of the Text Styles page that shows `sample`.
    private func line(_ sample: String, in app: TestApp) -> String {
        app.screen.line(containing: sample) ?? ""
    }

    /// What the terminal can do, as a run's launch would have settled it, and
    /// the page drawn again with it.
    private func set(_ capabilities: TerminalCapabilities, on app: TestApp) {
        app.headless.terminalCapabilities = capabilities
        app.advance(by: .zero)
    }

    @Test("A sample the terminal draws carries no note; one it does not, or nobody measured, does")
    func textStylesNotes() {
        // Tall enough for the whole page: at 40 rows its scroll view follows
        // the focus to a control further down, off the line styles.
        let app = TestApp(width: 100, height: 400) { TextStylesPage() }
        // Nothing known, as outside a run: every line style is unmeasured.
        #expect(line("page.textStyles.line.curly", in: app).contains("capability.note.undetermined"))

        // Apple Terminal's row of the table: none of them drawn as asked.
        set(.textDecorations(of: .appleTerminal), on: app)
        #expect(line("page.textStyles.line.curly", in: app).contains("capability.note.unsupported"))
        #expect(line("page.textStyles.strikethrough", in: app).contains("capability.note.unsupported"))

        // Warp's: a double line and a strikethrough, and no curly line.
        set(.textDecorations(of: .warp), on: app)
        #expect(!line("page.textStyles.line.double", in: app).contains("capability.note"))
        #expect(!line("page.textStyles.strikethrough", in: app).contains("capability.note"))
        #expect(line("page.textStyles.line.dotted", in: app).contains("capability.note.unsupported"))

        // iTerm2's: everything, and no note anywhere.
        set(.textDecorations(of: .iTerm2), on: app)
        #expect(!app.screen.contains("capability.note"))
    }

    @Test("The Terminal page lists each feature with its answer, and an Option chord changes one")
    func terminalPageList() {
        let app = TestApp(width: 100, height: 40) { TerminalCapabilitiesDemo() }
        let meta = { app.screen.line(containing: "page.terminal.feature.optionAsMeta") ?? "" }
        #expect(meta().contains("page.terminal.unknown"))
        app.press(.character("x"), modifiers: .option)
        #expect(meta().contains("page.terminal.yes"), "\(app.screen)")

        set(app.headless.terminalCapabilities.settling(.pictures, as: .unsupported), on: app)
        #expect(app.screen.line(containing: "page.terminal.feature.pictures")?.contains("page.terminal.no") == true)
    }
}
