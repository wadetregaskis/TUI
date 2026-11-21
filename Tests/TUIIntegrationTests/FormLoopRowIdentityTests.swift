//  🖥️ TUI — A Terminal UI framework for Swift
//  FormLoopRowIdentityTests.swift
//
//  A `Form` draws a `ForEach`'s rows at their elements' identities, and what
//  follows the loop at a place the loop's length does not move (CTRLS-1, H-09).
//
//  The form flattened a loop's rows into its list of elements and drew the
//  list by position: removing an element moved each drawn control's state —
//  a `DisclosureGroup`'s expansion, a field's caret, the focus — to the row
//  that took its place, and a button after the loop moved one place on with
//  every element added, so its focus id was new and the focus left it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

private struct Item: Identifiable, Equatable {
    let id: Int
}

/// The form's data, changed from outside between frames.
@MainActor
private final class Items {
    var binding: Binding<[Item]>?
    var adds = 0
}

/// A form of disclosure groups, one per item, then a button that adds one.
private struct LoopForm: View {
    @State private var items = [Item(id: 1), Item(id: 2), Item(id: 3)]
    let model: Items
    let style: Int

    var body: some View {
        model.binding = $items
        let form = Form {
            ForEach(items) { item in
                DisclosureGroup("Row \(item.id)") {
                    Text("inside \(item.id)")
                }
            }
            Button("Add") {
                model.adds += 1
                items.append(Item(id: (items.map(\.id).max() ?? 0) + 1))
            }
        }
        return Group {
            if style == 0 {
                form.formStyle(.columns)
            } else {
                form.formStyle(.grouped)
            }
        }
    }
}

@MainActor
@Suite("A Form's loop rows keep their state by element")
struct FormLoopRowIdentityTests {
    @Test("Removing the first item leaves the expanded row the same element", arguments: [0, 1])
    func expandedRowFollowsItsElement(style: Int) throws {
        let model = Items()
        let app = TestApp(width: 40, height: 20) { LoopForm(model: model, style: style) }
        try app.click("Row 2")
        #expect(app.screen.contains("inside 2"), "precondition: \(app.screen)")
        model.binding?.wrappedValue.removeFirst()
        #expect(app.screen.contains("inside 2"), "row 2 collapsed: \(app.screen)")
        #expect(!app.screen.contains("inside 3"), "row 3 took row 2's expansion: \(app.screen)")
    }

    @Test("The button after the loop keeps the focus as the loop grows", arguments: [0, 1])
    func trailingButtonKeepsTheFocus(style: Int) throws {
        let model = Items()
        let app = TestApp(width: 40, height: 20) { LoopForm(model: model, style: style) }
        try app.click("Add")
        #expect(model.adds == 1, "precondition")
        _ = app.press(.enter)
        _ = app.press(.enter)
        #expect(model.adds == 3, "the focus left the button: \(app.screen)")
    }
}
