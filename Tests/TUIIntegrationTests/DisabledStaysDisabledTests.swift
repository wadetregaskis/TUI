//  🖥️ TUI — A Terminal UI framework for Swift
//  DisabledStaysDisabledTests.swift
//
//  SwiftUI's `disabled(_:)` only ever adds a disabled ancestor: `.disabled(true)
//  .disabled(false)` is disabled, as the environment's `isEnabled` is an AND.
//  Most controls shadow the `View` modifier with a `disabled(_:)` of their own,
//  and all but the text controls ASSIGNED the flag, so the second call turned
//  the control back on — and with it a helper's disabled control the caller
//  wrapped in `.disabled(condition)`. Each shadow now adds, as the text
//  controls' did.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIFoundation
@testable import TUILists
@testable import TUINumericControls
@testable import TUIPickers
@testable import TUITables
import TUITesting

@MainActor
@Suite("disabled(false) does not re-enable")
struct DisabledStaysDisabledTests {

    private struct Row: Identifiable {
        let id: Int
        let name: String
    }

    @Test("Every control's own disabled(_:) adds to the flag rather than replacing it")
    func everyShadowAdds() {
        #expect(Button("b") {}.disabled(true).disabled(false).isDisabled)
        #expect(ScrollView { Text("s") }.disabled(true).disabled(false).isDisabled)
        #expect(Toggle("t", isOn: .constant(false)).disabled(true).disabled(false).isDisabled)
        #expect(List { Text("l") }.disabled(true).disabled(false).isDisabled)
        #expect(Slider(value: .constant(0.5)).disabled(true).disabled(false).isDisabled)
        #expect(Stepper("s", value: .constant(1)).disabled(true).disabled(false).isDisabled)
        #expect(
            DatePicker(selection: .constant(Date()), displayedComponents: .date) { EmptyView() }
                .disabled(true).disabled(false).isDisabled)
        #expect(
            Picker("p", selection: .constant(1)) { Text("a").tag(1) }.disabled(true).disabled(false).isDisabled)
        #expect(RadioButtonItem(1, "one").disabled(true).disabled(false).isDisabled)
        #expect(
            RadioButtonGroup(selection: .constant(1)) { RadioButtonItem(1, "one") }
                .disabled(true).disabled(false).isDisabled)
        let table = Table([Row(id: 1, name: "a")], selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Row.name)
        }
        #expect(table.disabled(true).disabled(false).isDisabled)
    }

    @Test("A slider disabled and then 'enabled' takes no focus")
    func sliderTakesNoFocus() {
        let enabled = TestApp(width: 30, height: 4) { Slider(value: .constant(0.5)).disabled(false) }
        #expect(enabled.focusedID != nil, "the control: an enabled slider takes the focus")
        let app = TestApp(width: 30, height: 4) { Slider(value: .constant(0.5)).disabled(true).disabled(false) }
        app.press(KeyEvent(key: .tab))
        #expect(app.focusedID == nil, "focused \(app.focusedID ?? "")")
    }
}
