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
}
