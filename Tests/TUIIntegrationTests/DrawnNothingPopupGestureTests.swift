//  🖥️ TUI — A Terminal UI framework for Swift
//  DrawnNothingPopupGestureTests.swift
//
//  A press on a control that opens a pop-up which then draws nothing: a menu
//  `Picker` with no options, a text field's suggestions while the field cannot
//  hold the focus they draw under. The dispatcher spends the drags and release
//  of a pop-up-opening press while the pop-up is not on screen — before a
//  frame has drawn it, or once it is no longer open — and asks the opener
//  which. An opener whose "open" outlived its drawing let a frame go by and
//  then had the rest of the gesture hit-tested live, onto rows and header
//  regions that never saw a press: a list's row selected, a table's column
//  resized or sorted.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITables
@testable import TUITestSupport

@Observable
@MainActor
private final class Model {
    enum Shape { case pickerOverList, pickerOverTable, suggestionsOverList }

    var shape = Shape.pickerOverList
    var choice = 0
    /// The picker's options: none, unless a test gives it some.
    var options: [Int] = []
    var text = ""
    var selection: Set<Int> = []
    var customization = TableColumnCustomization<Row>()
    var sortOrder = [KeyPathComparator(\Row.alpha)]
}

private struct Row: Identifiable, Equatable {
    let id: Int
    var alpha: String { "a\(id)" }
    var beta: String { "b\(id)" }
}

private struct PopupApp: App {
    let model: Model?

    init() { model = nil }

    init(_ model: Model) { self.model = model }

    var body: some Scene {
        WindowGroup {
            if let model { PopupPage(model: model) }
        }
    }
}

private struct PopupPage: View {
    let model: Model
    private let rows = (1...3).map(Row.init)

    var body: some View {
        VStack {
            switch model.shape {
            case .pickerOverList:
                picker
                list
            case .pickerOverTable:
                picker
                table
            case .suggestionsOverList:
                // Taken out of the focus ring, so it never holds the focus its
                // suggestions draw under.
                TextField("field", text: Bindable(model).text)
                    .textInputSuggestions {
                        Text("apricot")
                        Text("blackberry")
                    }
                    .frame(width: 24)
                    .focusable(false)
                list
            }
        }
    }

    private var picker: some View {
        Picker("pick", selection: Bindable(model).choice) {
            ForEach(model.options, id: \.self) { Text("opt\($0)").tag($0) }
        }
        .pickerStyle(.menu)
    }

    private var list: some View {
        List(rows, selection: Bindable(model).selection) { row in
            Text(row.alpha)
        }
        .frame(height: 5)
    }

    private var table: some View {
        Table(
            rows, selection: Bindable(model).selection, sortOrder: Bindable(model).sortOrder,
            columnCustomization: Bindable(model).customization
        ) {
            TableColumn("Alpha", value: \.alpha)
                .width(min: 4, ideal: 8, max: 30).customizationID("alpha")
            TableColumn("Beta", value: \.beta)
                .width(min: 4, ideal: 8, max: 30).customizationID("beta")
        }
        .frame(height: 6)
    }
}

@MainActor
private final class Harness {
    let model = Model()
    let app: HeadlessApp<PopupApp>
    private var now: Int64 = 0

    init(_ shape: Model.Shape) {
        model.shape = shape
        app = HeadlessApp(PopupApp(model), width: 40, height: 14)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var lines: [String] { app.screen.map(\.stripped) }

    var screen: String { lines.joined(separator: "\n") }

    func position(of text: String, below top: Int = 0) throws -> (x: Int, y: Int) {
        let y = try #require(
            lines.indices.first { $0 >= top && lines[$0].contains(text) }, "\(text) is not drawn:\n\(screen)")
        let range = try #require(lines[y].range(of: text))
        return (lines[y].distance(from: lines[y].startIndex, to: range.lowerBound), y)
    }

    /// Presses the opener at `at`, lets a frame go by, then drags to `to` and
    /// lets go there.
    func pressFrameDragRelease(at: (x: Int, y: Int), to: (x: Int, y: Int)) {
        app.send(MouseEvent(button: .left, phase: .pressed, x: at.x, y: at.y))
        frame()
        app.send(MouseEvent(button: .left, phase: .dragged, x: to.x, y: to.y))
        frame()
        app.send(MouseEvent(button: .left, phase: .released, x: to.x, y: to.y))
        frame()
    }
}

@MainActor
@Suite("The rest of a pop-up's gesture when the pop-up draws nothing")
struct DrawnNothingPopupGestureTests {
    @Test("A press on a menu Picker with no options, dragged onto a list's row and let go, selects nothing")
    func emptyPickerOverAList() throws {
        let harness = Harness(.pickerOverList)
        let picker = try harness.position(of: DropdownMenu.closedCaret)
        let row = try harness.position(of: "a2", below: picker.y + 1)
        harness.pressFrameDragRelease(at: picker, to: row)
        #expect(harness.model.selection.isEmpty, "the release selected a row:\n\(harness.screen)")
        // And the row still takes a click of its own.
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: row.x, y: row.y))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: row.x, y: row.y))
        harness.frame()
        #expect(harness.model.selection == [2], "\(harness.screen)")
    }

    @Test("A press on a menu Picker with no options, dragged across a table's column gap, resizes nothing")
    func emptyPickerOverATableGap() throws {
        let harness = Harness(.pickerOverTable)
        let picker = try harness.position(of: DropdownMenu.closedCaret)
        let beta = try harness.position(of: "Beta", below: picker.y + 1)
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: picker.x, y: picker.y))
        harness.frame()
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta.x - 1, y: beta.y))
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: beta.x + 3, y: beta.y))
        harness.frame()
        harness.app.send(MouseEvent(button: .left, phase: .released, x: beta.x + 3, y: beta.y))
        harness.frame()
        #expect(harness.model.customization[width: "alpha"] == nil, "the drag resized Alpha:\n\(harness.screen)")
    }

    @Test("A press on a menu Picker with no options, let go on a sortable title, sorts nothing")
    func emptyPickerOverATableTitle() throws {
        let harness = Harness(.pickerOverTable)
        let picker = try harness.position(of: DropdownMenu.closedCaret)
        let beta = try harness.position(of: "Beta", below: picker.y + 1)
        harness.pressFrameDragRelease(at: picker, to: (beta.x + 1, beta.y))
        #expect(harness.model.sortOrder == [KeyPathComparator(\Row.alpha)], "the release sorted:\n\(harness.screen)")
    }

    @Test("A press on the suggestions of a field that cannot hold the focus, let go on a list's row, selects nothing")
    func unfocusableSuggestionsOverAList() throws {
        let harness = Harness(.suggestionsOverList)
        let disclosure = try harness.position(of: DropdownMenu.closedCaret)
        let row = try harness.position(of: "a2", below: disclosure.y + 1)
        harness.pressFrameDragRelease(at: disclosure, to: row)
        #expect(!harness.screen.contains("blackberry"), "\(harness.screen)")
        #expect(harness.model.selection.isEmpty, "the release selected a row:\n\(harness.screen)")
    }

    @Test("A menu Picker whose options all go while it is open closes, and does not come back open with them")
    func pickerWhoseOptionsGoCloses() throws {
        let harness = Harness(.pickerOverList)
        harness.model.options = [1, 2]
        harness.model.choice = 1
        harness.frame()
        let picker = try harness.position(of: DropdownMenu.closedCaret)
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: picker.x, y: picker.y))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: picker.x, y: picker.y))
        harness.frame()
        #expect(harness.screen.contains("opt2"), "the click opened nothing:\n\(harness.screen)")
        harness.model.options = []
        harness.frame()
        harness.model.options = [1, 2]
        harness.frame()
        #expect(!harness.screen.contains("opt2"), "the drop-down came back open:\n\(harness.screen)")
    }
}
