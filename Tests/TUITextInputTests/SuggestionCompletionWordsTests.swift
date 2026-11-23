//  🖥️ TUI — A Terminal UI framework for Swift
//  SuggestionCompletionWordsTests.swift
//
//  A suggestion with no `textInputCompletion` fills its field with its
//  label's words, as written (Deliberate deviations T16): not the label's
//  first drawn row, which the screen's width cut and a line limit or a
//  `.textCase` above changed (hunt H-39).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUITesting
import TUITextInput

/// Where the field's binding writes, so a test reads what a pick wrote however
/// long it is.
@MainActor
private final class Typed {
    var text = ""
}

/// A field offering `suggestions`, its binding written to `typed`.
private struct SuggestingPage<Suggestions: View>: View {
    let typed: Typed
    let suggestions: Suggestions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Value", text: Binding(get: { typed.text }, set: { typed.text = $0 }))
                .textInputSuggestions { suggestions }
                .frame(width: 24)
            Spacer()
        }
    }
}

/// A suggestion that is a view of the app's own: drawn for its words.
private struct OwnRow: View {
    let words: String
    var body: some View { Text(verbatim: words) }
}

/// A long run of words: 200 characters, which an 80-column screen wraps.
private let longWords = String(
    repeating: "a long suggestion that runs past the screen's edge ", count: 4
).prefix(200).description

@MainActor
@Suite("A suggestion's completion is its label's words")
struct SuggestionCompletionWordsTests {
    /// What picking the first suggestion of `suggestions` writes to the field,
    /// on an 80-column screen.
    private func picked(_ suggestions: some View, around wrap: @escaping (AnyView) -> AnyView = { $0 }) -> String {
        let typed = Typed()
        let app = TestApp(width: 80, height: 16) {
            wrap(AnyView(SuggestingPage(typed: typed, suggestions: suggestions)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        _ = app.screen
        // Down opens the menu on its first row; Return picks it.
        app.press(.down)
        app.press(.enter)
        if typed.text.isEmpty {
            // The field was not focused yet: Tab to it and pick again.
            app.press(.tab)
            app.press(.down)
            app.press(.enter)
        }
        return typed.text
    }

    @Test("A 200-character Text on an 80-column screen fills the field with all of it")
    func longText() {
        #expect(longWords.count == 200)
        #expect(picked(Text(verbatim: longWords)) == longWords)
    }

    @Test("A line limit on the label leaves its words whole")
    func lineLimitedLabel() {
        #expect(picked(Text(verbatim: longWords).lineLimit(1)) == longWords)
    }

    @Test("A .textCase on the label or above it leaves the words as written")
    func textCase() {
        #expect(picked(Text(verbatim: "Paris").textCase(.uppercase)) == "Paris")
        #expect(picked(Text(verbatim: "Rome"), around: { AnyView($0.textCase(.uppercase)) }) == "Rome")
    }

    @Test("A Label's completion is its title's words, without its icon")
    func labelTitle() {
        let label = Label {
            Text(verbatim: "Inbox")
        } icon: {
            Text(verbatim: "📥")
        }
        #expect(picked(label) == "Inbox")
    }

    @Test("A suggestion in a ForEach of equatable elements fills the field with its words")
    func forEachRow() {
        #expect(picked(ForEach([longWords], id: \.self) { Text(verbatim: $0) }) == longWords)
    }

    @Test("A view of the app's own is drawn at its ideal width for its words")
    func ownView() {
        #expect(picked(OwnRow(words: longWords)) == longWords)
        #expect(picked(OwnRow(words: "Oslo"), around: { AnyView($0.textCase(.uppercase)) }) == "Oslo")
    }
}
