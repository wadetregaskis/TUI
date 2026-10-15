//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FindNavigatorTests.swift
//
//  The find and replace bar a `TextEditor` draws: presented by
//  `findNavigator(isPresented:)` or Ctrl-G, finding and replacing in the text,
//  and kept away by `findDisabled` and `replaceDisabled`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

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

    @Test("Ctrl-G in an editor with no binding presents the bar")
    func controlGPresents() {
        var text = "one two"
        let binding = Binding(get: { text }, set: { text = $0 })
        let harness = InputChainHarness(width: 50, height: 8)
        harness.frame(TextEditor(text: binding))
        let before = harness.frame(TextEditor(text: binding)).lines.map(\.stripped)
        #expect(!before.contains { $0.contains("Done") })
        harness.press(KeyEvent(key: .character("g"), ctrl: true))
        let after = harness.frame(TextEditor(text: binding)).lines.map(\.stripped)
        #expect(after.contains { $0.contains("Done") }, "\(after)")
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
