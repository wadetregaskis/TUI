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
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITerminalHost

extension TextStylesPage: ExamplePageContent {}
extension TerminalCapabilitiesDemo: ExamplePageContent {}

@MainActor
@Suite("The Example's notes on what this terminal can do")
struct TerminalCapabilitiesPagesTests {
    /// The line of the Text Styles page that shows `sample`.
    private func line(_ sample: String, in driver: ExamplePageDriver<ExamplePageApp<TextStylesPage>>) -> String {
        driver.lines.first { $0.contains(sample) } ?? ""
    }

    @Test("A sample the terminal draws carries no note; one it does not, or nobody measured, does")
    func textStylesNotes() {
        // Tall enough for the whole page: at 40 rows its scroll view follows
        // the focus to a control further down, off the line styles.
        let driver = ExamplePageDriver(ExamplePageApp<TextStylesPage>(), width: 100, height: 400)
        // Nothing known, as outside a run: every line style is unmeasured.
        #expect(line("page.textStyles.line.curly", in: driver).contains("capability.note.undetermined"))

        // Apple Terminal's row of the table: none of them drawn as asked.
        driver.terminalCapabilities = .textDecorations(of: .appleTerminal)
        #expect(line("page.textStyles.line.curly", in: driver).contains("capability.note.unsupported"))
        #expect(line("page.textStyles.strikethrough", in: driver).contains("capability.note.unsupported"))

        // Warp's: a double line and a strikethrough, and no curly line.
        driver.terminalCapabilities = .textDecorations(of: .warp)
        #expect(!line("page.textStyles.line.double", in: driver).contains("capability.note"))
        #expect(!line("page.textStyles.strikethrough", in: driver).contains("capability.note"))
        #expect(line("page.textStyles.line.dotted", in: driver).contains("capability.note.unsupported"))

        // iTerm2's: everything, and no note anywhere.
        driver.terminalCapabilities = .textDecorations(of: .iTerm2)
        #expect(!driver.lines.joined().contains("capability.note"))
    }

    @Test("The Terminal page lists each feature with its answer, and an Option chord changes one")
    func terminalPageList() {
        let driver = ExamplePageDriver(ExamplePageApp<TerminalCapabilitiesDemo>(), width: 100, height: 40)
        let meta = { driver.lines.first { $0.contains("page.terminal.feature.optionAsMeta") } ?? "" }
        #expect(meta().contains("page.terminal.unknown"))
        driver.send(KeyEvent(key: .character("x"), alt: true))
        #expect(meta().contains("page.terminal.yes"), "\(driver.lines)")

        driver.terminalCapabilities = driver.terminalCapabilities.settling(.pictures, as: .unsupported)
        #expect(driver.lines.first { $0.contains("page.terminal.feature.pictures") }?.contains("page.terminal.no") == true)
    }
}
