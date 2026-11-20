//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusableHelpKeyTests.swift
//
//  The help key shows a focused `.focusable()` view's help wherever its
//  `.help` is written among its modifiers, as SwiftUI's view has one help
//  however its modifiers are ordered. Until 2026-11-20 only a `.help` written
//  outside the focus stop counted: the stop published the help it found in
//  its own environment, and one inside it writes its text into its content's
//  (tuidisk's TUI-FEEDBACK.md, milestone 2 item 7).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("The help key finds a help inside a focusable view")
struct FocusableHelpKeyTests {
    /// A card a memo can serve: `Equatable`, its body a help over a fill.
    private struct Card: View, Equatable {
        let tip: String
        var body: some View {
            Rectangle().fill(.blue).help(tip)
        }
    }

    @Test("A help inside .focusable(interactions: .activate) shows for the help key", arguments: [false, true])
    func helpInsideActivate(automatic: Bool) {
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                if automatic {
                    Rectangle().fill(.blue).help("TIP").focusable()
                } else {
                    Rectangle().fill(.blue).help("TIP").focusable(interactions: .activate)
                }
            }
        }
        app.press(.tab)
        #expect(app.focusedID?.hasPrefix("focusable") == true)
        #expect(!app.screen.contains("TIP"), "nothing shows until the key is pressed")
        app.type("?")
        #expect(app.screen.contains("TIP"))
    }

    @Test("Of a help inside the stop and one outside it, the inner one shows, as under the pointer")
    func innerHelpWins() {
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                Rectangle().fill(.blue).help("INNER").focusable().help("OUTER")
            }
        }
        app.press(.tab)
        app.type("?")
        #expect(app.screen.contains("INNER"))
        #expect(!app.screen.contains("OUTER"))
    }

    @Test("A control's help inside a focusable container stays the control's")
    func controlKeepsItsHelp() {
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                VStack {
                    Text(verbatim: "container")
                    Button("inner") {}.help("BUTTON TIP")
                }
                .focusable()
            }
        }
        app.press(.tab)
        #expect(app.focusedID?.hasPrefix("focusable") == true, "the container has the focus")
        app.type("?")
        #expect(!app.screen.contains("BUTTON TIP"), "the help is the button's, which hasn't the focus")
    }

    @Test("A help in a memoized card inside the stop still shows frames after the focus came")
    func memoizedCard() {
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                Card(tip: "CARD TIP").equatable().focusable()
            }
        }
        app.press(.tab)
        app.advance(by: .seconds(1))
        app.type("?")
        #expect(app.screen.contains("CARD TIP"))
        app.advance(by: .seconds(1))
        #expect(app.screen.contains("CARD TIP"), "still shown on later frames")
    }
}
