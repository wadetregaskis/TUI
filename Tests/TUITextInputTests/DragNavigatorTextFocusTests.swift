//  🖥️ TUI — A Terminal UI framework for Swift
//  DragNavigatorTextFocusTests.swift
//
//  The mid-drag navigator keys with a text input holding the focus: a pointer
//  drag does not move the focus, so a field focused before it still holds it,
//  and the keys must still scroll the view under the pointer.
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
@Suite("Mid-drag navigators with a text input focused")
struct DragNavigatorTextFocusTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// A draggable chip, a field, and three drop zones in a two-line scroll
    /// view.
    struct Page: View {
        let field = Box("abcd")
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("seed")
                TextField("Field", text: field.binding).focusID("field").frame(width: 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<3, id: \.self) { zone in
                            Text("ZONE\(zone)").dropDestination(for: String.self) { _, _ in true }
                        }
                    }
                }
                .frame(height: 2)
            }
        }
    }

    /// Hunt DND-9: the text input's layer runs ahead of the navigators', so the
    /// field took the keys it moves its caret with — End, Home — and the view
    /// under the pointer never moved.
    @Test("With a field focused, End mid-drag scrolls the view under the pointer, and the field keeps its text")
    func endReachesTheNavigator() {
        let page = Page()
        let harness = InputChainHarness(width: 24, height: 6)
        harness.frame(page)
        harness.focusManager.focus(id: "field")
        harness.frame(page)
        #expect(harness.focusManager.hasTextInputFocus)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
        let over = harness.frame(page)
        #expect(over.lines[2].stripped.hasPrefix("ZONE0"), "\(over.lines.map(\.stripped))")
        #expect(harness.press(KeyEvent(key: .end)))
        let scrolled = harness.frame(page)
        #expect(scrolled.lines[2].stripped.hasPrefix("ZONE1"), "\(scrolled.lines.map(\.stripped))")
        #expect(harness.focusManager.hasTextInputFocus, "the focus stays in the field")
        #expect(page.field.value == "abcd")
    }
}
