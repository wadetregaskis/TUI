//  🖥️ TUI — A Terminal UI framework for Swift
//  SuggestionLabelStateTests.swift
//
//  A text field's suggestion labels keep `@State` of their own, and the
//  field keeps its own slots beside them.
//
//  The field draws its suggestions' labels a step below its own identity,
//  where its handler and focus id live at indices 0…. A label written in the
//  builder is a `Subview`, which draws at the identity it resolved to, so its
//  state is its own wherever the field draws it from; this keeps it so. (A
//  searchable's suggested token is drawn by the app's view itself, which did
//  land on the handler's key: `SearchTokenLabelStateTests`.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
import TUITextInput

/// Where the labels below leave a way for the test to write their state.
@MainActor
private final class LabelNotes {
    var writers: [String: (String) -> Void] = [:]
}

/// A suggestion label whose `@State` the test writes, as a key would, and
/// which counts its appearances into `@State` of a type no slot of the
/// field's holds.
private struct NotedSuggestion: View {
    let name: String
    let notes: LabelNotes
    @State private var count = 0
    @State private var note = ""

    var body: some View {
        notes.writers[name] = { note = $0 }
        return Text(verbatim: "\(name)\(note)\(count)").onAppear { count = 7 }
    }
}

private struct FieldPage: View {
    let notes: LabelNotes
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Value", text: $text)
                .textInputSuggestions {
                    NotedSuggestion(name: "alpha", notes: notes)
                    NotedSuggestion(name: "beta", notes: notes)
                }
                .frame(width: 24)
            Text(verbatim: "typed[\(text)]")
            Spacer()
        }
    }
}

@MainActor
@Suite("A text field's suggestion labels keep their own @State")
struct SuggestionLabelStateTests {
    @Test("Each label keeps its own state, and the menu still opens and fills the field")
    func labelsKeepTheirState() throws {
        let notes = LabelNotes()
        let app = TestApp(width: 60, height: 16) {
            FieldPage(notes: notes)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        _ = app.screen
        notes.writers["beta"]?("+b")
        app.press(.down)
        if app.screen.location(of: "alpha") == nil {
            app.press(.tab)
            app.press(.down)
        }
        try #require(app.screen.location(of: "beta+b7") != nil, "the menu opens, beta keeps its state: \(app.screen)")
        #expect(app.screen.location(of: "alpha7") != nil, "alpha keeps its own state: \(app.screen)")
        app.press(.down)
        app.press(.enter)
        #expect(app.screen.contains("typed[beta+b7]"), "the menu filled the field: \(app.screen)")
        app.press(.down)
        #expect(app.screen.location(of: "beta+b7") != nil, "reopened, beta still holds its state: \(app.screen)")
    }
}
