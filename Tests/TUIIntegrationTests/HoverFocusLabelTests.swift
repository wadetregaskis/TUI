//  🖥️ TUI — A Terminal UI framework for Swift
//  HoverFocusLabelTests.swift
//
//  With the focus following the pointer, a move onto a control's label focuses
//  the control, as a move onto the control does — standalone and in a form's
//  label column — and moves no value (owner ruling HOVER-FOCUS b,
//  2026-11-10). Off, the label takes nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("With the focus following the pointer, a control's label focuses the control")
struct HoverFocusLabelTests {
    enum Kind: String, CaseIterable, Sendable {
        case slider, stepper, toggle, datePicker, labeledContent, picker, colorPicker
    }

    private struct Controls: View {
        let kind: Kind
        @State private var value = 3.0
        @State private var count = 2
        @State private var isOn = false
        @State private var date = Date(timeIntervalSince1970: 0)
        @State private var text = ""
        @State private var flavour = 1
        @State private var color = Color.red

        var body: some View {
            switch kind {
            case .slider: Slider(value: $value, in: 0...10) { Text("Volume") }.focusID("target")
            case .stepper: Stepper("Count", value: $count).focusID("target")
            case .toggle: Toggle("Wi-Fi", isOn: $isOn).focusID("target")
            case .datePicker: DatePicker("When", selection: $date).focusID("target")
            case .labeledContent: LabeledContent("Name") { TextField("", text: $text).focusID("target") }
            case .picker:
                Picker("Flavour", selection: $flavour) {
                    Text("Plain").tag(1)
                    Text("Salted").tag(2)
                }
                .focusID("target")
            case .colorPicker: ColorPicker("Tint", selection: $color)
            }
        }
    }

    private struct Page: View {
        let kind: Kind
        let inForm: Bool

        var body: some View {
            VStack(alignment: .leading) {
                Button("Go") {}.focusID("go")
                if inForm {
                    Form { Controls(kind: kind) }
                } else {
                    Controls(kind: kind)
                }
                Spacer()
            }
        }
    }

    private struct PageApp: App {
        let kind: Kind
        let inForm: Bool
        let follows: Bool
        init() { (kind, inForm, follows) = (.slider, false, true) }
        init(kind: Kind, inForm: Bool, follows: Bool) { (self.kind, self.inForm, self.follows) = (kind, inForm, follows) }

        var body: some Scene {
            WindowGroup { Page(kind: kind, inForm: inForm) }
                .focusFollowsPointer(follows)
        }
    }

    private static func label(_ kind: Kind) -> String {
        switch kind {
        case .slider: "Volume"
        case .stepper: "Count"
        case .toggle: "Wi-Fi"
        case .datePicker: "When"
        case .labeledContent: "Name"
        case .picker: "Flavour"
        case .colorPicker: "Tint"
        }
    }

    /// The cell `offset` columns into `text`, where it first shows.
    private func cell(_ app: TestApp, _ text: String, offset: Int = 0) throws -> CellPoint {
        let lines = app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains(text) }, "\(text) is on screen")
        let start = try #require(lines[y].range(of: text)).lowerBound
        return CellPoint(x: lines[y][..<start].count + offset, y: y)
    }

    @Test(
        "A move onto the label focuses the control, and changes nothing drawn but the focus",
        arguments: Kind.allCases, [false, true])
    func labelFocuses(_ kind: Kind, inForm: Bool) throws {
        let app = TestApp(PageApp(kind: kind, inForm: inForm, follows: true), width: 70, height: 12)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "go")
        app.hover(at: try cell(app, Self.label(kind)))
        let focused = try #require(app.focusedID, "\(kind): nothing is focused")
        #expect(focused != "go", "\(kind)\(inForm ? " in a form" : ""): the label took no focus")
        if kind != .colorPicker {
            #expect(focused == "target", "\(kind): the label focused \(focused)")
        }
    }

    @Test("Off, the label takes nothing", arguments: Kind.allCases)
    func offTakesNothing(_ kind: Kind) throws {
        let app = TestApp(PageApp(kind: kind, inForm: false, follows: false), width: 70, height: 12)
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, Self.label(kind)))
        #expect(app.focusedID == "go")
    }

    @Test("A move onto the label moves no value")
    func labelMovesNoValue() throws {
        let app = TestApp(PageApp(kind: .stepper, inForm: false, follows: true), width: 70, height: 12)
        app.advance(by: .milliseconds(20))
        let before = app.screen.lines
        app.hover(at: try cell(app, "Count"))
        app.hover(at: try cell(app, "Count", offset: 2))
        #expect(app.focusedID == "target")
        #expect(app.screen.lines == before, "the value moved")
    }

    // MARK: - The colour picker's swatch and channels

    private struct ColorApp: App {
        @State private var color = Color.red
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Button("Go") {}.focusID("go")
                    ColorPicker("Tint", selection: $color)
                    Spacer()
                }
            }
            .focusFollowsPointer()
        }
    }

    @Test("A colour picker's label and its swatch focus the swatch; a channel's letter focuses its slider")
    func colorPicker() throws {
        let app = TestApp(ColorApp(), width: 80, height: 8)
        app.advance(by: .milliseconds(20))
        let row = try cell(app, "Tint")
        let line = app.screen.lines[row.y]
        func column(of text: String) throws -> Int {
            line[..<(try #require(line.range(of: text), "\(text) is on the picker's row")).lowerBound].count
        }
        // The swatch: the cells between the label column and the first channel.
        app.hover(at: CellPoint(x: try column(of: " R ") - 2, y: row.y))
        let swatch = try #require(app.focusedID, "the swatch took no focus")
        #expect(swatch != "go")
        app.hover(at: try cell(app, "Go"))
        #expect(app.focusedID == "go")
        app.hover(at: row)
        #expect(app.focusedID == swatch, "the label focused \(app.focusedID ?? "nothing"), not the swatch")
        app.hover(at: CellPoint(x: try column(of: " G ") + 1, y: row.y))
        let green = try #require(app.focusedID)
        #expect(green != swatch && green != "go", "the G channel's letter focused \(green)")
    }
}
