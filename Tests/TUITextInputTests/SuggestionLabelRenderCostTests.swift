//  🖥️ TUI — A Terminal UI framework for Swift
//  SuggestionLabelRenderCostTests.swift
//
//  A text field draws its suggestions' labels only while its menu shows: a
//  closed menu's rows are drawn by nobody, and a `Text` label's words, which a
//  pick fills the field with, are read without drawing it. Every label was
//  drawn on every pass before (hunt H-39).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUITesting
import TUITextInput

/// Counts the draws of the labels below.
@MainActor
private final class Draws {
    var drawn = 0
}

/// A form of a field offering `count` suggestions, each a `Text` that counts
/// its draws, beside a second field to type into.
private struct SuggestingForm: View {
    let count: Int
    let draws: Draws
    @State private var value = ""
    @State private var other = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Other", text: $other)
            TextField("Value", text: $value)
                .textInputSuggestions {
                    ForEach(0..<count, id: \.self) { index in
                        Text(verbatim: "suggestion \(index)").onRenderPass { pass in
                            if pass == .render { draws.drawn += 1 }
                        }
                    }
                }
            Spacer()
        }
        .frame(width: 40)
    }
}

@MainActor
@Suite("A text field draws its suggestions' labels only while its menu shows")
struct SuggestionLabelRenderCostTests {
    private static let suggestions = 8

    @Test("A closed menu draws no label, frame after frame")
    func closedMenuDrawsNoLabel() {
        let draws = Draws()
        let app = TestApp(width: 60, height: 16) {
            SuggestingForm(count: Self.suggestions, draws: draws)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        _ = app.screen
        let frames = app.headless.framesDrawn
        draws.drawn = 0
        // Typed into the other field: a frame each, the menu closed.
        app.type("abcd")
        let drawn = app.headless.framesDrawn - frames
        #expect(drawn >= 4, "each key drew a frame")
        #expect(draws.drawn == 0, "\(draws.drawn) label draws over \(drawn) frames with the menu closed")
    }

    @Test("An open menu draws each label")
    func openMenuDrawsEachLabel() throws {
        let draws = Draws()
        let app = TestApp(width: 60, height: 16) {
            SuggestingForm(count: Self.suggestions, draws: draws)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        _ = app.screen
        app.press(.tab)
        draws.drawn = 0
        app.press(.down)
        try #require(app.screen.contains("suggestion 7"), "the menu opened: \(app.screen)")
        #expect(draws.drawn >= Self.suggestions, "\(draws.drawn) label draws for an open menu")
    }
}
