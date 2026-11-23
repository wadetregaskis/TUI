//  🖥️ TUI — A Terminal UI framework for Swift
//  ZeroWidthCharacterTests.swift
//
//  A character that takes no cell of its own — a BOM (U+FEFF) a file was read
//  with, a ZWSP (U+200B) pasted from a web page, a soft hyphen, a bidi mark, a
//  combining mark with nothing before it — used to be COUNTED as one cell by
//  the text inputs and WRITTEN as it was, which the terminal gives no cell. So
//  the row came out a cell short (an editor's scroll bar drawn a column to the
//  left, the field's closing cap too) and a caret on one drew nothing
//  visible (H-48, TEXTIN-4). It is drawn now as the one-cell stand-in a
//  control character already had, U+FFFD; a mark or joiner merged into the
//  character before it is part of that character and is not touched.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

/// A mutable string backing a test `Binding`.
private final class TextSink: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
    var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("Zero-width characters in text inputs")
struct ZeroWidthCharacterTests {

    // MARK: - The stand-in

    @Test(
        "A standalone character with no cell of its own is drawn as U+FFFD",
        arguments: [
            "\u{200B}",  // ZWSP
            "\u{FEFF}",  // BOM
            "\u{00AD}",  // soft hyphen
            "\u{200E}",  // LRM
            "\u{202E}",  // RLO
            "\u{2060}",  // word joiner
            "\u{301}",  // a combining acute with no base
        ] as [Character])
    func zeroWidthStandsIn(character: Character) {
        #expect(character.terminalWidth == 0, "the premise: the terminal gives it no cell")
        #expect(TextFieldHandler.displayCharacter(character) == "\u{FFFD}")
        #expect(TextFieldHandler.verticalDisplayCharacter(character) == "\u{FFFD}")
        #expect(TextFieldHandler.singleLineDisplayCharacter(character) == "\u{FFFD}")
    }

    @Test(
        "A mark or joiner merged into a character, and ordinary characters, are drawn as they are",
        arguments: ["e\u{301}", "\u{1F469}\u{200D}\u{1F680}", "a", "中", "\u{2764}\u{FE0F}", "é"] as [Character])
    func mergedCharactersUnchanged(character: Character) {
        #expect(TextFieldHandler.displayCharacter(character) == character)
    }

    @Test("The ASCII characters draw as they always did: a tab a space, a control U+FFFD")
    func asciiUnchanged() {
        #expect(TextFieldHandler.displayCharacter("\t") == " ")
        #expect(TextFieldHandler.displayCharacter("\u{1B}") == "\u{FFFD}")
        #expect(TextFieldHandler.displayCharacter("\r\n") == "\u{FFFD}")
        #expect(TextFieldHandler.displayCharacter("\u{7F}") == "\u{FFFD}")
        #expect(TextFieldHandler.displayCharacter("\u{85}") == "\u{FFFD}", "a C1 control")
        for byte in UInt8(0x20)..<0x7F {
            let character = Character(Unicode.Scalar(byte))
            #expect(TextFieldHandler.displayCharacter(character) == character)
        }
    }

    // MARK: - TextEditor

    private func row(_ line: String, width: Int = 10) -> String {
        let core = _TextEditorCore(
            text: .constant(line), focusID: nil, isDisabled: false, menuTarget: TextEditingMenuTarget())
        let styling = _TextEditorCore.RowStyling(
            palette: EnvironmentValues().palette, isDisabled: false, background: nil)
        return core.styledRow(
            TextCharacters(line)[...], tabWidth: .periodic(4), scrollColumn: 0, width: width,
            caret: nil, selection: nil, styling: styling
        ).line
    }

    @Test("An editor row holding a ZWSP is exactly its width, the ZWSP a visible cell")
    func editorRowWidth() {
        let drawn = row("a\u{200B}b")
        #expect(drawn.strippedLength == 10, "|\(drawn.stripped)|")
        #expect(drawn.stripped.hasPrefix("a\u{FFFD}b"))
    }

    @Test("An editor row starting with a BOM is exactly its width")
    func editorRowBOM() {
        let drawn = row("\u{FEFF}hello")
        #expect(drawn.strippedLength == 10, "|\(drawn.stripped)|")
        #expect(drawn.stripped.hasPrefix("\u{FFFD}hello"))
    }

    @Test(
        "An editor row of merged marks and joiners is drawn as written",
        arguments: ["e\u{301}x", "\u{1F469}\u{200D}\u{1F680}x"])
    func editorRowMergedUnchanged(line: String) {
        let drawn = row(line)
        #expect(drawn.strippedLength == 10, "|\(drawn.stripped)|")
        #expect(drawn.stripped.hasPrefix(line))
        #expect(!drawn.stripped.contains("\u{FFFD}"))
    }

    private struct EditorHost: View {
        let sink: TextSink
        var body: some View { TextEditor(text: sink.binding) }
    }

    @Test("Every row of a scrolling editor over a ZWSP is its full width, the bar's row included")
    func editorWithScrollBar() {
        let sink = TextSink("a\u{200B}b\n2\n3\n4\n5\n6\n7")
        let buffer = renderToBuffer(EditorHost(sink: sink), context: makeRenderContext(width: 10, height: 3))
        for line in buffer.lines {
            #expect(line.strippedLength == 10, "|\(line.stripped)|")
        }
        // The bar's column is the same on the ZWSP's row as on the rows under it.
        let lastCells = buffer.lines.map { $0.stripped.last }
        #expect(Set(lastCells).count <= 2, "bar column: \(lastCells)")
        withExtendedLifetime(sink) {}
    }

    @Test("A caret on a ZWSP sits on its own visible cell, where the row drew it")
    func editorCaretOnZeroWidth() {
        let sink = TextSink("a\u{200B}b")
        let context = makeRenderContext(width: 10, height: 2)
        let view = EditorHost(sink: sink)
        _ = renderToBuffer(view, context: context)
        guard let handler = context.environment.focusManager?.activeSection?.focusables
            .compactMap({ $0 as? TextEditorHandler }).first
        else {
            Issue.record("no editor handler registered")
            return
        }
        handler.cursorLine = 0
        handler.cursorColumn = 1
        let buffer = renderToBuffer(view, context: context)
        let run = buffer.animatedCells.first
        #expect(run?.offsetX == 1)
        #expect(run?.width == 1)
        #expect(run?.frames.allSatisfy { $0.stripped == "\u{FFFD}" } == true, "frames: \(run?.frames ?? [])")
        #expect(buffer.lines[0].strippedLength == 10, "|\(buffer.lines[0].stripped)|")
        expectReplayIsIdentity(buffer)
        withExtendedLifetime(sink) {}
    }

    // MARK: - TextField

    @Test("A field over a ZWSP is exactly its width, focused and not")
    func fieldWidth() {
        func context(_ manager: FocusManager, path: String) -> RenderContext {
            var environment = EnvironmentValues()
            environment.focusManager = manager
            return RenderContext(
                availableWidth: 14, availableHeight: 1, environment: environment, tuiContext: TUIContext(),
                identity: ViewIdentity(path: path)
            ).isolatingRenderCache()
        }
        for focused in [true, false] {
            let manager = FocusManager()
            if !focused {
                // A decoy registers first and takes the auto-focus.
                _ = renderToBuffer(
                    TextField("Decoy", text: .constant("x")).focusID("decoy"),
                    context: context(manager, path: "decoy"))
            }
            let fieldContext = context(manager, path: "field")
            let field = TextField("Fill", text: .constant("a\u{200B}b")).focusID("tf")
            _ = renderToBuffer(field, context: fieldContext)
            let line = renderToBuffer(field, context: fieldContext).lines[0].stripped
            #expect((manager.currentFocusedID == "tf") == focused)
            #expect(line.strippedLength == 14, "focused \(focused): |\(line)|")
            #expect(line.contains("a\u{FFFD}b"), "focused \(focused): |\(line)|")
        }
    }

    @Test("A field's caret on a ZWSP draws the stand-in, and the field keeps its width")
    func fieldCaretOnZeroWidth() {
        let renderer = TextFieldContentRenderer(
            prompt: nil, isDisabled: false, displayCharacter: TextFieldHandler.displayCharacter,
            contentForeground: nil)
        let content = renderer.buildContent(
            text: "a\u{200B}b", cursorPosition: 1, selectionRange: nil, isFocused: true,
            palette: SystemPalette(.green), cursorStyle: TextCursorStyle(), cursorTimer: nil, contentWidth: 10)
        #expect(content.line.strippedLength == 10, "|\(content.line.stripped)|")
        #expect(content.line.stripped.hasPrefix("a\u{FFFD}b"))
    }

    @Test("A vertical field over a ZWSP is exactly its width")
    func verticalFieldWidth() {
        let field = TextField("", text: .constant("a\u{200B}b c"), axis: .vertical)
        let buffer = renderToBuffer(field, context: makeRenderContext(width: 12, height: 3))
        #expect(buffer.lines.first?.stripped.contains("a\u{FFFD}b") == true, "\(buffer.lines.map(\.stripped))")
        for line in buffer.lines {
            #expect(line.strippedLength == 12, "|\(line.stripped)|")
        }
    }
}
