//  🖥️ TUI — A Terminal UI framework for Swift
//  AppTextEditBindingTests.swift
//
//  The app's edit of a field's or an editor's text, drawn through a real frame
//  (owner ruling O-28 (a), 2026-11-22): the selection carried through it, and
//  a selection the app writes in the same update winning over the carried
//  one, as `TextEditor(text:selection:)` shows the app's in SwiftUI
//  (`Documentation/SwiftUI parity/SELECTION-REPLACE/`, Part 4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
import TUITextInput

private final class Model: @unchecked Sendable {
    var text: String
    var selection: TextSelection?
    init(_ text: String) { self.text = text }

    var textBinding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
    var selectionBinding: Binding<TextSelection?> { Binding(get: { self.selection }, set: { self.selection = $0 }) }

    func select(_ offsets: Range<Int>) {
        let lower = text.index(text.startIndex, offsetBy: offsets.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: offsets.upperBound)
        selection = TextSelection(range: lower..<upper)
    }
}

/// The two controls, each over the model's text and selection.
enum BoundControl: String, CaseIterable, Sendable {
    case field, editor

    @MainActor
    fileprivate func view(_ model: Model) -> AnyView {
        switch self {
        case .field: AnyView(TextField("Text", text: model.textBinding, selection: model.selectionBinding))
        case .editor: AnyView(TextEditor(text: model.textBinding, selection: model.selectionBinding))
        }
    }
}

@MainActor
@Suite("The app's edit of a bound text, through a frame")
struct AppTextEditBindingTests {

    /// The model with "abcdefghij" and "cdefg" selected, drawn in `control`.
    private func selected(in control: BoundControl, harness: InputChainHarness) -> Model {
        let model = Model("abcdefghij")
        harness.frame(control.view(model))
        model.select(2..<7)
        harness.frame(control.view(model))
        return model
    }

    @Test("The app writes the text only: the selection is carried through the edit", arguments: BoundControl.allCases)
    func textOnly(_ control: BoundControl) {
        let harness = InputChainHarness()
        let model = selected(in: control, harness: harness)
        model.text = "XY" + model.text
        harness.frame(control.view(model))
        harness.press(KeyEvent(key: .character("Z")))
        // SwiftUI would have kept 2..<7 of the new text and typed "XYZhij".
        #expect(model.text == "XYabZhij", "the shifted selection, \"cdefg\", was typed over")
    }

    @Test("The app writes the text and a selection together: the app's selection wins", arguments: BoundControl.allCases)
    func textAndSelection(_ control: BoundControl) {
        let harness = InputChainHarness()
        let model = selected(in: control, harness: harness)
        model.text = "XY" + model.text
        model.select(0..<2)
        harness.frame(control.view(model))
        harness.press(KeyEvent(key: .character("Z")))
        #expect(model.text == "Zabcdefghij", "the app's \"XY\" was typed over, not the carried \"cdefg\"")
    }

    @Test("A shorter text under a selection that ran past its end leaves a caret at its end", arguments: BoundControl.allCases)
    func shorterText(_ control: BoundControl) {
        // SwiftUI traps here ("String index is out of bounds"); TUI never does.
        let harness = InputChainHarness()
        let model = selected(in: control, harness: harness)
        model.text = "012"
        harness.frame(control.view(model))
        harness.press(KeyEvent(key: .character("Z")))
        #expect(model.text == "012Z")
    }

    @Test("A document loaded in place of the one selected in leaves a caret at its end, so typing deletes nothing")
    func documentReplaced() {
        // TEXTIN-11's case: the selection was kept while it fitted, and the
        // next key replaced text nobody had selected.
        var text = "abcdefghij"
        let binding = Binding(get: { text }, set: { text = $0 })
        let harness = InputChainHarness()
        harness.frame(TextEditor(text: binding))
        harness.frame(TextEditor(text: binding))
        harness.press(KeyEvent(key: .end))
        for _ in 0..<3 { harness.press(KeyEvent(key: .left, shift: true)) }
        text = "0123456789"
        harness.frame(TextEditor(text: binding))
        harness.press(KeyEvent(key: .character("x")))
        #expect(text == "0123456789x")
    }
}
