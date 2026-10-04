//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectionTests.swift
//
//  A text editor's and a text field's caret and selection exchanged with the
//  app's `TextSelection` binding: the app's writes move them, and their moves
//  are written back, with the environment's affinity.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@available(macOS 15, *)
private final class Model: @unchecked Sendable {
    var text: String
    var selection: TextSelection?
    init(_ text: String) { self.text = text }

    var textBinding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
    var selectionBinding: Binding<TextSelection?> { Binding(get: { self.selection }, set: { self.selection = $0 }) }

    /// The selection as character offsets.
    var offsets: Range<Int>? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
            ..< text.distance(from: text.startIndex, to: range.upperBound)
    }

    func select(_ offsets: Range<Int>) {
        let lower = text.index(text.startIndex, offsetBy: offsets.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: offsets.upperBound)
        selection = TextSelection(range: lower..<upper)
    }
}

@MainActor
@Suite("TextSelection with fields and editors")
struct TextSelectionTests {

    // `TextSelection` is macOS 15's, as SwiftUI's is; the bodies run where it
    // exists, which is every CI lane.

    @Test("A text editor writes its caret, and an app's selection moves it")
    func editorRoundTrip() {
        if #available(macOS 15, *) { editorRoundTripBody() }
    }

    @Test("Text edited by typing reports the caret after the new text")
    func editorTyping() {
        if #available(macOS 15, *) { editorTypingBody() }
    }

    @Test("A text field writes its caret and selection, and an app's selection moves them")
    func fieldRoundTrip() {
        if #available(macOS 15, *) { fieldRoundTripBody() }
    }

    @Test("A vertical text field exchanges its selection the same way, across its rows")
    func verticalFieldRoundTrip() {
        if #available(macOS 15, *) { verticalFieldRoundTripBody() }
    }

    @available(macOS 15, *)
    private func fieldRoundTripBody() {
        let model = Model("hello world")
        let harness = InputChainHarness { $0.textSelectionAffinity = .downstream }
        let field = { TextField("Message", text: model.textBinding, selection: model.selectionBinding) }
        harness.play([KeyEvent(key: .home)], field)
        #expect(model.offsets == 0..<0, "the caret is written as it moves: \(String(describing: model.offsets))")
        #expect(model.selection?.affinity == .downstream)
        harness.play([KeyEvent(key: .right, shift: true), KeyEvent(key: .right, shift: true)], field)
        #expect(model.offsets == 0..<2, "and the selection as it grows")

        // The app selects "world"; the field adopts it, so typing replaces it.
        model.select(6..<11)
        harness.play([KeyEvent(key: .character("X"))], field)
        #expect(model.text == "hello X")
        #expect(model.offsets == 7..<7, "\(String(describing: model.offsets))")
    }

    @available(macOS 15, *)
    private func verticalFieldRoundTripBody() {
        let model = Model("one\ntwo")
        let harness = InputChainHarness()
        let field = {
            TextField(text: model.textBinding, selection: model.selectionBinding, axis: .vertical) {
                Text("Notes")
            }
        }
        harness.play([KeyEvent(key: .up, shift: true)], field)
        #expect(model.offsets == 3..<7, "Shift-Up from the end selects back a row: \(String(describing: model.offsets))")
        model.select(0..<3)
        harness.play([KeyEvent(key: .character("X"))], field)
        #expect(model.text == "X\ntwo")
    }

    @available(macOS 15, *)
    private func editorRoundTripBody() {
        let model = Model("one\ntwo")
        let harness = InputChainHarness { $0.textSelectionAffinity = .upstream }
        let editor = { TextEditor(text: model.textBinding, selection: model.selectionBinding) }
        harness.frame(editor())
        harness.press(KeyEvent(key: .end))
        #expect(model.offsets == 7..<7 || model.offsets == 3..<3, "the caret is written as it moves: \(String(describing: model.offsets))")
        #expect(model.selection?.affinity == .upstream)

        // The app selects "two"; the editor adopts it, so typing replaces it.
        model.select(4..<7)
        harness.frame(editor())
        harness.press(KeyEvent(key: .character("X")))
        #expect(model.text == "one\nX")
        #expect(model.offsets == 5..<5, "\(String(describing: model.offsets))")
    }

    @available(macOS 15, *)
    private func editorTypingBody() {
        let model = Model("ab")
        let harness = InputChainHarness()
        let editor = { TextEditor(text: model.textBinding, selection: model.selectionBinding) }
        model.select(1..<1)
        harness.frame(editor())
        harness.press(KeyEvent(key: .character("x")))
        #expect(model.text == "axb")
        #expect(model.offsets == 2..<2 && model.selection?.isInsertion == true)
    }
}
