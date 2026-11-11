//  🖥️ TUI — A Terminal UI framework for Swift
//  HoverFocusSegmentTests.swift
//
//  With the focus following the pointer, a segmented picker's and a radio
//  group's keyboard cursor — the segment or option the keys act on — follows
//  the pointer as it moves over them, as a list's cursor row does; never the
//  choice (owner ruling SEGMENT-CURSOR b, 2026-11-11).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("With the focus following the pointer, a segmented picker's and a radio group's cursor follow it")
struct HoverFocusSegmentTests {
    enum Kind: String, CaseIterable, Sendable {
        case segmented, palette, radio, horizontalRadio
    }

    private struct Page: View {
        let kind: Kind
        @State private var size = 2

        var body: some View {
            VStack(alignment: .leading) {
                Button("Go") {}.focusID("go")
                picker
                // Below the options, so an option's name is found on the control first.
                Text("picked \(["", "Small", "Medium", "Large"][size])")
                Spacer()
            }
        }

        @ViewBuilder private var picker: some View {
            let picker = Picker("Size", selection: $size) {
                Text("Small").tag(1)
                Text("Medium").tag(2)
                Text("Large").tag(3)
            }
            .focusID("size")
            switch kind {
            case .segmented: picker.pickerStyle(.segmented)
            case .palette: picker.pickerStyle(.palette)
            case .radio: picker.pickerStyle(.radioGroup)
            case .horizontalRadio: picker.pickerStyle(.radioGroup).horizontalRadioGroupLayout()
            }
        }
    }

    private struct PageApp: App {
        let kind: Kind
        let follows: Bool
        init() { (kind, follows) = (.segmented, true) }
        init(kind: Kind, follows: Bool) { (self.kind, self.follows) = (kind, follows) }

        var body: some Scene {
            WindowGroup { Page(kind: kind) }
                .focusFollowsPointer(follows)
        }
    }

    private func launched(_ kind: Kind, follows: Bool = true) -> TestApp {
        let app = TestApp(PageApp(kind: kind, follows: follows), width: 50, height: 10)
        app.advance(by: .milliseconds(20))
        return app
    }

    /// The cell `offset` columns into `text`, where it first shows.
    private func cell(_ app: TestApp, _ text: String, offset: Int = 0) throws -> CellPoint {
        let lines = app.screen.lines
        let y = try #require(lines.firstIndex { $0.contains(text) }, "\(text) is on screen")
        let start = try #require(lines[y].range(of: text)).lowerBound
        return CellPoint(x: lines[y][..<start].count + offset, y: y)
    }

    private func picked(_ app: TestApp) -> String? {
        app.screen.lines.lazy.compactMap { line in
            line.range(of: "picked ").map { String(line[$0.upperBound...]) }
        }
        .first?.trimmingCharacters(in: .whitespaces)
    }

    @Test("A move onto an option focuses the control and puts its cursor there, the choice unmoved", arguments: Kind.allCases)
    func cursorFollows(_ kind: Kind) throws {
        let app = launched(kind)
        #expect(app.focusedID == "go")
        app.hover(at: try cell(app, "Large"))
        #expect(app.focusedID == "size", "\(kind): the focus is on \(app.focusedID ?? "nothing")")
        #expect(picked(app) == "Medium", "\(kind): the pointer chose an option")
        app.press(.space)
        #expect(picked(app) == "Large", "\(kind): the keys acted on \(picked(app) ?? "nothing"), not the option under the pointer")
        app.hover(at: try cell(app, "Small"))
        #expect(picked(app) == "Large", "\(kind): the pointer chose an option")
        app.press(.space)
        #expect(picked(app) == "Small", "\(kind): the cursor stayed behind the pointer")
    }

    @Test("Off, the pointer moves neither the focus nor the cursor", arguments: Kind.allCases)
    func offMovesNothing(_ kind: Kind) throws {
        let app = launched(kind, follows: false)
        app.hover(at: try cell(app, "Large"))
        #expect(app.focusedID == "go")
        app.press(.tab)
        #expect(app.focusedID == "size")
        app.hover(at: try cell(app, "Large", offset: 1))
        app.press(.space)
        #expect(picked(app) == "Medium", "\(kind): the pointer moved the cursor")
    }

    @Test("A pointer at rest leaves the cursor where the keys put it; the next move takes it", arguments: Kind.allCases)
    func stillPointerKeepsCursor(_ kind: Kind) throws {
        let app = launched(kind)
        let large = try cell(app, "Large")
        app.hover(at: large)
        #expect(app.focusedID == "size")
        app.press(kind == .radio ? .up : .left)
        app.hover(at: large)
        app.press(.space)
        #expect(picked(app) == "Medium", "\(kind): a report from the same cell took the cursor back")
        // A move within the cursor's own option leaves it there.
        app.hover(at: try cell(app, "Medium", offset: 1))
        app.press(.space)
        #expect(picked(app) == "Medium", "\(kind): a move within the cursor's option moved it")
        app.hover(at: try cell(app, "Large", offset: 1))
        app.press(.space)
        #expect(picked(app) == "Large", "\(kind): the pointer moved, and the cursor did not follow it")
    }

    @Test("A rule between two segments moves nothing", arguments: [Kind.segmented, .palette])
    func ruleMovesNothing(_ kind: Kind) throws {
        let app = launched(kind)
        app.hover(at: try cell(app, "Large"))
        let medium = try cell(app, "Medium")
        // The rule left of "Medium", past its padding.
        let rule = try #require(
            (0..<medium.x).reversed().first { x in
                let line = app.screen.lines[medium.y]
                return line[line.index(line.startIndex, offsetBy: x)] == "│"
            })
        app.hover(at: CellPoint(x: rule, y: medium.y))
        app.press(.space)
        #expect(picked(app) == "Large", "\(kind): the rule moved the cursor")
    }

    private struct DisabledOptionPage: View {
        @State private var size = 2

        var body: some View {
            VStack(alignment: .leading) {
                Button("Go") {}.focusID("go")
                RadioButtonGroup(selection: $size) {
                    RadioButtonItem(1, "Small")
                    RadioButtonItem(2, "Medium")
                    RadioButtonItem(3, "Large").disabled()
                }
                .focusID("size")
                Text("picked \(["", "Small", "Medium", "Large"][size])")
                Spacer()
            }
        }
    }

    private struct DisabledOptionApp: App {
        var body: some Scene {
            WindowGroup { DisabledOptionPage() }
                .focusFollowsPointer()
        }
    }

    @Test("A disabled option takes nothing: the cursor stays where it was")
    func disabledOption() throws {
        let app = TestApp(DisabledOptionApp(), width: 50, height: 10)
        app.advance(by: .milliseconds(20))
        app.hover(at: try cell(app, "Small"))
        #expect(app.focusedID == "size")
        app.hover(at: try cell(app, "Large"))
        app.press(.space)
        #expect(picked(app) == "Small", "the cursor went onto the disabled option")
    }

    private struct SheetApp: App {
        var body: some Scene {
            WindowGroup {
                Page(kind: .segmented)
                    .sheet(isPresented: .constant(true)) {
                        Button("Sheet") {}.focusID("sheet")
                    }
            }
            .focusFollowsPointer()
        }
    }

    @Test("Behind a sheet, the pointer moves nothing in the picker")
    func behindSheet() throws {
        let app = TestApp(SheetApp(), width: 50, height: 10)
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "sheet")
        app.hover(at: try cell(app, "Large"))
        #expect(app.focusedID == "sheet")
    }
}
