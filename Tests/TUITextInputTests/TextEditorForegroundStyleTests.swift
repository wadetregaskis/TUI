//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorForegroundStyleTests.swift
//
//  A `TextEditor`'s text in the `.foregroundStyle` in force, as SwiftUI's is,
//  String-bound or attributed — a run's own colour winning, as in a `Text` of
//  the value — and `.disabled` dimming it and taking its focus stop, as it
//  does any control's (CLAUDE.md's control checks 4 and 5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Text editor: the foreground style and .disabled")
struct TextEditorForegroundStyleTests {
    private typealias Runs = SelectionTestText

    private static let stated = Color.rgb(30, 160, 90)

    /// Each visible cell of `line` with the SGR state in force on it.
    private func cells(_ line: String) -> [(character: Character, state: SGRState)] {
        var state = SGRState()
        var result: [(character: Character, state: SGRState)] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): result.append((character, state))
            }
        }
        return result
    }

    /// The ink a cell drawn in `colour` states.
    private static func ink(_ colour: Color) -> SGRState {
        var style = TextStyle()
        style.foregroundColor = colour.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// The first row of `view`, framed 20 by 3, cell by cell, and the context
    /// it was drawn in.
    private func firstRow(_ view: some View) throws -> (
        row: [(character: Character, state: SGRState)], context: RenderContext
    ) {
        let context = makeRenderContext(width: 20, height: 3)
        let buffer = renderToBuffer(view.frame(width: 20, height: 3), context: context)
        return (cells(try #require(buffer.lines.first)), context)
    }

    @Test("A String editor's text takes the .foregroundStyle in force")
    func stringEditorTakesStyle() throws {
        let styled = try firstRow(TextEditor(text: .constant("hello")).foregroundStyle(Self.stated)).row
        let plain = try firstRow(TextEditor(text: .constant("hello"))).row
        // Cell 0 is the caret's, which draws in its own colours.
        for cell in styled[1..<5] {
            #expect(cell.state.foregroundColour == Self.ink(Self.stated).foregroundColour, "\(cell.character)")
        }
        #expect(plain[1].state.foregroundColour != Self.ink(Self.stated).foregroundColour, "unstyled, the palette's")
    }

    @Test("In an attributed editor a run's own colour wins over the .foregroundStyle; the rest takes it")
    func runColourWins() throws {
        let text = Runs.runs([("ab", Runs.red)]) + AttributedString("cd")
        let row = try firstRow(TextEditor(text: .constant(text)).foregroundStyle(Self.stated)).row
        #expect(row[1].state.foregroundColour == Self.ink(Runs.red).foregroundColour, "the run's own")
        for cell in row[2..<4] {
            #expect(cell.state.foregroundColour == Self.ink(Self.stated).foregroundColour, "\(cell.character)")
        }
    }

    @Test("A selection keeps its own ink under a .foregroundStyle")
    func selectionKeepsItsInk() throws {
        let context = makeRenderContext(width: 20, height: 3)
        let view = TextEditor(text: .constant("hello")).foregroundStyle(Self.stated).frame(width: 20, height: 3)
        _ = renderToBuffer(view, context: context)
        let handler = try #require(
            context.environment.focusManager?.activeSection?.focusables.compactMap { $0 as? TextEditorHandler }.first)
        handler.moveCursor(toLine: 0, column: 1)
        handler.selectionAnchor = handler.cursor
        handler.startOrExtendSelection()
        handler.moveCursor(toLine: 0, column: 3)
        let row = cells(try #require(renderToBuffer(view, context: context).lines.first))
        #expect(row[1].state.foregroundColour != Self.ink(Self.stated).foregroundColour, "the selection's ink")
        #expect(row[4].state.foregroundColour == Self.ink(Self.stated).foregroundColour, "past it, the style's")
    }

    @Test(".disabled takes the editor's focus stop and draws its text in the tertiary tier, styled or not")
    func disabledDimsAndBlocks() throws {
        for styled in [false, true] {
            let editor = TextEditor(text: .constant("hello"))
            let drawn =
                if styled { try firstRow(editor.foregroundStyle(Self.stated).disabled(true)) } else {
                    try firstRow(editor.disabled(true))
                }
            let editors = drawn.context.environment.focusManager?.activeSection?.focusables
                .compactMap { $0 as? TextEditorHandler } ?? []
            #expect(editors.allSatisfy { !$0.canBeFocused }, "no focus stop")
            let palette = drawn.context.environment.palette
            let tertiary = Self.ink(palette.foregroundTertiary.resolve(with: palette)).foregroundColour
            // No caret: cell 0 is text too.
            for cell in drawn.row[0..<5] {
                #expect(cell.state.foregroundColour == tertiary, "\(cell.character), styled: \(styled)")
            }
        }
    }

    // MARK: - A disabled editor's runs (A-DISED-1)

    final class Flag: @unchecked Sendable {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    /// A run's colour drawn disabled: faded toward the page by the disabled
    /// dim, keeping its hue, as a disabled slider's accent track is.
    private static func faded(_ colour: Color, in context: RenderContext) -> Color {
        let palette = context.environment.palette
        return colour.opacity(ViewConstants.disabledForeground, over: palette.background.resolve(with: palette))
    }

    /// The field a cell drawn on `colour` states.
    private static func field(_ colour: Color) -> SGRState {
        var style = TextStyle()
        style.backgroundColor = colour.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// The underline colour a cell underlined in `colour` states.
    private static func line(_ colour: Color) -> SGRState {
        var style = TextStyle()
        style.underline = .some(Text.LineStyle(color: colour.opaqueSpelling))
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// Cells 1 and 2 of `row` — past the caret's cell 0, a run's — drawn in
    /// `ink` on `field`, and underlined in `underline` where one is given.
    private func expectRun(
        _ row: [(character: Character, state: SGRState)], ink: Color, field: Color, underline: Color? = nil,
        _ comment: String
    ) {
        for cell in row[1..<3] {
            #expect(cell.state.foregroundColour == Self.ink(ink).foregroundColour, "\(cell.character) ink, \(comment)")
            #expect(
                cell.state.backgroundColour == Self.field(field).backgroundColour, "\(cell.character) field, \(comment)")
            if let underline {
                #expect(
                    cell.state.underlineColour == Self.line(underline).underlineColour,
                    "\(cell.character) line, \(comment)")
            }
        }
    }

    @Test("A disabled attributed editor fades its runs' ink and field; enabled, and enabled again, they are as stated")
    func disabledFadesAttributedRuns() throws {
        try withColorDepth(.truecolor) {
            var run = AttributedString("ab")
            run.foregroundColor = Runs.red
            run.backgroundColor = Runs.blue
            let text = AttributedString("x") + run + AttributedString("cd")
            let disabled = Flag(false)
            let context = makeRenderContext(width: 20, height: 3)
            @MainActor func row() throws -> [(character: Character, state: SGRState)] {
                let view = TextEditor(text: .constant(text)).disabled(disabled.value).frame(width: 20, height: 3)
                return cells(try #require(renderToBuffer(view, context: context).lines.first))
            }
            expectRun(try row(), ink: Runs.red, field: Runs.blue, "enabled")
            disabled.value = true
            let faded = (ink: Self.faded(Runs.red, in: context), field: Self.faded(Runs.blue, in: context))
            try #require(faded.ink != Runs.red && faded.field != Runs.blue, "the premise: the fade shows")
            expectRun(try row(), ink: faded.ink, field: faded.field, "disabled")
            disabled.value = false
            expectRun(try row(), ink: Runs.red, field: Runs.blue, "enabled again")
        }
    }

    @Test("A disabled editor fades a line styler's runs: ink, field and the underline's colour")
    func disabledFadesStyledRuns() throws {
        try withColorDepth(.truecolor) {
            var decoration = CellDecoration()
            decoration.underline = Text.LineStyle(color: Runs.green)
            let styled = EditorStyledRun(
                columns: 1..<3, foreground: Runs.red, background: Runs.blue, decoration: decoration)
            let disabled = Flag(false)
            let context = makeRenderContext(width: 20, height: 3)
            @MainActor func render() -> FrameBuffer {
                renderToBuffer(
                    TextEditor(text: .constant("xabcd")).disabled(disabled.value).frame(width: 20, height: 3),
                    context: context)
            }
            _ = render()
            let handler = try #require(
                context.environment.focusManager?.activeSection?.focusables
                    .compactMap { $0 as? TextEditorHandler }.first)
            handler.replaceLineStyler { $0 == 0 ? [styled] : [] }
            @MainActor func row() throws -> [(character: Character, state: SGRState)] {
                cells(try #require(render().lines.first))
            }
            expectRun(try row(), ink: Runs.red, field: Runs.blue, underline: Runs.green, "enabled")
            disabled.value = true
            expectRun(
                try row(), ink: Self.faded(Runs.red, in: context), field: Self.faded(Runs.blue, in: context),
                underline: Self.faded(Runs.green, in: context), "disabled")
            disabled.value = false
            expectRun(try row(), ink: Runs.red, field: Runs.blue, underline: Runs.green, "enabled again")
        }
    }
}
