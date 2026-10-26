//  🖥️ TUI — A Terminal UI framework for Swift
//  FindNavigatorTests.swift
//
//  The find and replace bar a `TextEditor` draws: presented by
//  `findNavigator(isPresented:)` or Ctrl-F, finding and replacing in the text,
//  and kept away by `findDisabled` and `replaceDisabled`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("The find navigator")
struct FindNavigatorTests {

    /// Mutable state the views bind to, kept outside the view values.
    private final class Model {
        var text = "one two one"
        var presented = true
        var offsets: Range<Int>?
    }

    @Test("Matches are found without regard to case, as character offsets")
    func matching() {
        #expect(FindMatches.ranges(of: "one", in: "One two ONE") == [0..<3, 8..<11])
        #expect(FindMatches.ranges(of: "", in: "anything").isEmpty)
        #expect(FindMatches.replacing(4..<7, in: "one two one", with: "2") == "one 2 one")
    }

    @Test("The options: case, a word's start, a whole word")
    func matchingOptions() {
        let text = "One bone ONE one_two"
        #expect(FindMatches.ranges(of: "one", in: text) == [0..<3, 5..<8, 9..<12, 13..<16])
        var options = FindOptions()
        options.ignoresCase = false
        #expect(FindMatches.ranges(of: "one", in: text, options: options) == [5..<8, 13..<16])
        options = FindOptions()
        options.placement = .startsWith
        // "bone" contains it mid-word; "one_two" starts with it.
        #expect(FindMatches.ranges(of: "one", in: text, options: options) == [0..<3, 9..<12, 13..<16])
        options.placement = .fullWord
        // An underscore is part of a word, as in an identifier.
        #expect(FindMatches.ranges(of: "one", in: text, options: options) == [0..<3, 9..<12])
    }

    @Test("Typing a query selects the first match; Return the next; Escape closes the bar")
    func findAndClose() {
        guard #available(macOS 15, *) else { return }
        let model = Model()
        var selection: TextSelection?
        let text = Binding(get: { model.text }, set: { model.text = $0 })
        let selectionBinding = Binding<TextSelection?>(
            get: { selection },
            set: { selection = $0 })
        let presented = Binding(get: { model.presented }, set: { model.presented = $0 })
        let harness = InputChainHarness(width: 50, height: 8)
        func view() -> some View {
            TextEditor(text: text, selection: selectionBinding)
                .findNavigator(isPresented: presented)
        }
        func offsets() -> Range<Int>? {
            guard case .selection(let range)? = selection?.indices else { return nil }
            return model.text.distance(from: model.text.startIndex, to: range.lowerBound)
                ..< model.text.distance(from: model.text.startIndex, to: range.upperBound)
        }
        harness.frame(view())
        harness.frame(view())
        for character in "one" {
            harness.press(KeyEvent(character: character))
            harness.frame(view())
        }
        #expect(offsets() == 0..<3)
        harness.press(KeyEvent(key: .enter))
        harness.frame(view())
        #expect(offsets() == 8..<11)
        harness.press(KeyEvent(key: .escape))
        harness.frame(view())
        #expect(model.presented == false)
    }

    @Test("The bar draws above the text, with a replace row unless replace is disabled")
    func barRows() {
        func lines(_ view: some View) -> [String] {
            let harness = InputChainHarness(width: 60, height: 8)
            harness.frame(view)
            return harness.frame(view).lines.map(\.stripped)
        }
        let text = Binding.constant("one two")
        let withReplace = lines(TextEditor(text: text).findNavigator(isPresented: .constant(true)))
        #expect(withReplace.contains { $0.contains("Replace All") }, "\(withReplace)")
        let findOnly = lines(TextEditor(text: text).replaceDisabled().findNavigator(isPresented: .constant(true)))
        #expect(!findOnly.contains { $0.contains("Replace All") } && findOnly.contains { $0.contains("Done") })
        // The modifier closer to the editor wins, as SwiftUI documents.
        let disabledInside = lines(TextEditor(text: text).findDisabled().findNavigator(isPresented: .constant(true)))
        #expect(!disabledInside.contains { $0.contains("Done") }, "\(disabledInside)")
        let disabledOutside = lines(TextEditor(text: text).findNavigator(isPresented: .constant(true)).findDisabled())
        #expect(disabledOutside.contains { $0.contains("Done") })
    }

    @Test("Ctrl-F in an editor with no binding presents the bar; the editor does not take it")
    func controlFPresents() {
        var text = "one two"
        let binding = Binding(get: { text }, set: { text = $0 })
        let harness = InputChainHarness(width: 50, height: 8)
        harness.frame(TextEditor(text: binding))
        let before = harness.frame(TextEditor(text: binding)).lines.map(\.stripped)
        #expect(!before.contains { $0.contains("Done") })
        harness.press(KeyEvent(key: .character("f"), ctrl: true))
        let after = harness.frame(TextEditor(text: binding)).lines.map(\.stripped)
        #expect(after.contains { $0.contains("Done") }, "\(after)")
        // Where find is disabled the chord is the editor's own again.
        let disabled = InputChainHarness(width: 50, height: 8)
        disabled.frame(TextEditor(text: binding).findDisabled())
        disabled.press(KeyEvent(key: .character("f"), ctrl: true))
        let still = disabled.frame(TextEditor(text: binding).findDisabled()).lines.map(\.stripped)
        #expect(!still.contains { $0.contains("Done") }, "\(still)")
    }

    @Test("After Ctrl-F the keys type into the search field, not the text")
    func controlFFocusesTheQuery() {
        guard #available(macOS 15, *) else { return }
        let model = Model()
        model.text = "one two"
        var selection: TextSelection?
        let text = Binding(get: { model.text }, set: { model.text = $0 })
        let selectionBinding = Binding<TextSelection?>(get: { selection }, set: { selection = $0 })
        let harness = InputChainHarness(width: 50, height: 8)
        func view() -> some View { TextEditor(text: text, selection: selectionBinding) }
        func offsets() -> Range<Int>? {
            guard case .selection(let range)? = selection?.indices else { return nil }
            return model.text.distance(from: model.text.startIndex, to: range.lowerBound)
                ..< model.text.distance(from: model.text.startIndex, to: range.upperBound)
        }
        harness.frame(view())
        harness.frame(view())
        harness.press(KeyEvent(key: .character("f"), ctrl: true))
        harness.frame(view())
        for character in "two" {
            harness.press(KeyEvent(character: character))
            harness.frame(view())
        }
        #expect(model.text == "one two", "the query was typed into the text")
        #expect(offsets() == 4..<7)
    }

    @Test("The find state compares what it was set with, not what its binding says now")
    func stateComparesItsSnapshot() {
        var presented = false
        let binding = Binding(get: { presented }, set: { presented = $0 })
        var closed = FindNavigatorState()
        closed.isPresented = binding
        presented = true
        var open = FindNavigatorState()
        open.isPresented = binding
        // Read live, both said `true` now, and a state kept from the render
        // with the bar closed compared equal to this one.
        #expect(closed != open)
        var openAgain = FindNavigatorState()
        openAgain.isPresented = binding
        #expect(open == openAgain)
    }

    @Test("Ctrl-G finds the next match with the bar closed, and Shift-Ctrl-G the previous")
    func controlGSteps() {
        guard #available(macOS 15, *) else { return }
        let model = Model()
        model.text = "one two one two one"
        var selection: TextSelection?
        let text = Binding(get: { model.text }, set: { model.text = $0 })
        let selectionBinding = Binding<TextSelection?>(get: { selection }, set: { selection = $0 })
        let presented = Binding(get: { model.presented }, set: { model.presented = $0 })
        let harness = InputChainHarness(width: 50, height: 8)
        func view() -> some View {
            TextEditor(text: text, selection: selectionBinding).findNavigator(isPresented: presented)
        }
        func offsets() -> Range<Int>? {
            guard case .selection(let range)? = selection?.indices else { return nil }
            return model.text.distance(from: model.text.startIndex, to: range.lowerBound)
                ..< model.text.distance(from: model.text.startIndex, to: range.upperBound)
        }
        harness.frame(view())
        harness.frame(view())
        for character in "one" {
            harness.press(KeyEvent(character: character))
            harness.frame(view())
        }
        #expect(offsets() == 0..<3)
        harness.press(KeyEvent(key: .escape))
        harness.frame(view())
        #expect(model.presented == false)
        // The bar closed on a query: Ctrl-G goes on through its matches, wrapping.
        harness.press(KeyEvent(key: .character("g"), ctrl: true))
        harness.frame(view())
        #expect(offsets() == 8..<11)
        harness.press(KeyEvent(key: .character("g"), ctrl: true))
        harness.frame(view())
        #expect(offsets() == 16..<19)
        harness.press(KeyEvent(key: .character("g"), ctrl: true))
        harness.frame(view())
        #expect(offsets() == 0..<3)
        // Shift, where the terminal reports it, steps back.
        harness.press(KeyEvent(key: .character("g"), ctrl: true, shift: true))
        harness.frame(view())
        #expect(offsets() == 16..<19)
        #expect(model.presented == false, "Ctrl-G with a query leaves the bar closed")
    }

    @Test("Every match is tinted while the bar is up, the current one selected over it")
    func everyMatchIsTinted() {
        guard #available(macOS 15, *) else { return }
        let model = Model()
        model.text = "one two one"
        var selection: TextSelection?
        let text = Binding(get: { model.text }, set: { model.text = $0 })
        let selectionBinding = Binding<TextSelection?>(get: { selection }, set: { selection = $0 })
        let harness = InputChainHarness(width: 50, height: 8)
        func view() -> some View {
            TextEditor(text: text, selection: selectionBinding).findNavigator(isPresented: .constant(true))
        }
        harness.frame(view())
        harness.frame(view())
        for character in "one" {
            harness.press(KeyEvent(character: character))
            harness.frame(view())
        }
        let lines = harness.frame(view()).lines
        // The text is the line after the bar's two rows; its fields at the first
        // match (selected), between the matches, and at the second (tinted).
        guard let row = lines.first(where: { $0.stripped.hasPrefix("one two one") }) else {
            Issue.record("no text row: \(lines.map(\.stripped))")
            return
        }
        let selected = row.ansiSGRStateAt(visibleColumn: 0).renderedBackground
        let between = row.ansiSGRStateAt(visibleColumn: 5).renderedBackground
        let tinted = row.ansiSGRStateAt(visibleColumn: 9).renderedBackground
        #expect(tinted != between, "the second match is not tinted: \(row.debugDescription)")
        #expect(tinted != selected, "the second match is drawn as the selection: \(row.debugDescription)")
    }

    @Test("The find context reports the modifiers above")
    func findContext() {
        var environment = EnvironmentValues()
        #expect(environment.findContext?.supportsReplace == true)
        environment.findNavigator.isReplaceDisabled = true
        #expect(environment.findContext?.supportsReplace == false)
        environment.findNavigator.isFindDisabled = true
        #expect(environment.findContext == nil)
    }
}
