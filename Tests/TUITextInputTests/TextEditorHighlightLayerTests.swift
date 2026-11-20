//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightLayerTests.swift
//
//  Highlighting drawn over a TextEditor's text, never written into it (the
//  highlighting design's B-ATTRED-8 and 10, lane H1 of its §8.6): runs in
//  UTF-8 offsets and interned styles, drawn over an attributed value's own
//  runs and under the selection and the caret, faded when disabled, through
//  alignment, line height and wrapping, and kept for the lines drawn.
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
@Suite("Text editor: highlighting drawn over the text")
struct TextEditorHighlightLayerTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private typealias Sample = SelectionTestText

    /// What the test's highlighter calls a token.
    enum Token: Hashable { case key, word, bold, plate }

    nonisolated static let yellow = Color.rgb(220, 200, 20)

    /// Each token's attributes: one attribute each, so each test sees what a
    /// run that sets only that attribute leaves of the run under it.
    nonisolated static func style(_ token: Token) -> AttributeContainer {
        var container = AttributeContainer()
        switch token {
        case .key: container.foregroundColor = Sample.green
        case .word: container.foregroundColor = Sample.orange
        case .bold: container.font = .body.weight(.semibold)
        case .plate: container.backgroundColor = yellow
        }
        return container
    }

    /// A layer whose lines have `lines`' runs: each a UTF-8 offset and a
    /// token, or `nil` for a gap; its styles interned from `style`.
    static func layer(
        _ lines: [Int: [(Int, Token?)]], style: (Token) -> AttributeContainer = Self.style
    ) -> EditorHighlightLayer {
        var styles = EditorHighlightStyles()
        var table: [Int: [EditorHighlightRun]] = [:]
        for (line, runs) in lines {
            table[line] = runs.map { offset, token in
                EditorHighlightRun(
                    utf8Offset: offset,
                    style: token.map { styles.index(of: $0, style: style) } ?? EditorHighlightStyles.none)
            }
        }
        let runs = table
        return EditorHighlightLayer(runs: { runs[$0] ?? [] }, styles: styles)
    }

    /// Each visible cell of `line` with the SGR state in force on it.
    static func cells(_ line: String) -> [(character: Character, state: SGRState)] {
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

    /// The SGR state of a cell drawn in `ink`, on `field` where one is given.
    static func drawn(ink: Color? = nil, field: Color? = nil, bold: Bool = false) -> SGRState {
        var style = TextStyle()
        if bold { style.isBold = true }
        style.foregroundColor = ink?.opaqueSpelling
        style.backgroundColor = field?.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// An editor of `view`, rendered once so its handler exists, `layer` given
    /// to it, and rendered again: its handler, and a render's rows' cells.
    private func editor(
        _ view: some View, width: Int = 20, height: Int = 3, layer: EditorHighlightLayer?,
        prepare: (TextEditorHandler) -> Void = { _ in }
    ) -> (handler: TextEditorHandler, rows: () -> [[(character: Character, state: SGRState)]], lines: () -> [String]) {
        let context = makeRenderContext(width: width, height: height)
        let framed = view.frame(width: width, height: height)
        _ = renderToBuffer(framed, context: context)
        let handler = context.environment.focusManager!.activeSection!.focusables
            .compactMap { $0 as? TextEditorHandler }.first!
        prepare(handler)
        handler.replaceHighlightLayer(layer)
        let lines = { renderToBuffer(framed, context: context).lines }
        return (handler, { lines().map(Self.cells) }, lines)
    }

    // MARK: - Drawing

    @Test("A highlighter's runs draw their styles; its gaps, and the lines it leaves alone, as without one")
    func runsAreDrawn() throws {
        let text = "xkey = word\nnext"
        let layer = Self.layer([0: [(0, nil), (1, .key), (4, nil), (7, .word)]])
        let row = try #require(editor(TextEditor(text: .constant(text)), layer: layer).rows().first)
        let plain = editor(TextEditor(text: .constant(text)), layer: nil).rows()
        for cell in row[1..<4] { #expect(cell.state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "\(cell.character)") }
        for cell in row[7..<11] { #expect(cell.state.foregroundColour == Self.drawn(ink: Sample.orange).foregroundColour, "\(cell.character)") }
        for column in 4..<7 { #expect(row[column].state == plain[0][column].state, "gap \(column)") }
        let highlighted = editor(TextEditor(text: .constant(text)), layer: layer).rows()
        #expect(highlighted[1].map(\.state) == plain[1].map(\.state), "a line with no runs")
    }

    @Test("No highlighter, and one with no runs, draw byte for byte as an editor without")
    func emptyHighlighterIsUnchanged() {
        var stored = AttributedString("abc")
        stored.foregroundColor = Sample.red
        let value = AttributedString("x") + stored + AttributedString("\tdef\nghi")
        for view in [AnyView(TextEditor(text: .constant("abc\tdef\nghi"))), AnyView(TextEditor(text: .constant(value)))] {
            let without = editor(view, layer: nil).lines()
            #expect(editor(view, layer: Self.layer([:])).lines() == without)
            #expect(editor(view, layer: Self.layer([0: [(0, nil)]])).lines() == without)
        }
    }

    @Test(
        "Over an attributed value's own runs, what a highlight run sets wins and what it leaves unset is the value's")
    func composesOverTheValuesRuns() throws {
        // "abcdefg" red on blue, between plain characters.
        var stored = AttributedString("abcdefg")
        stored.foregroundColor = Sample.red
        stored.backgroundColor = Sample.blue
        let value = Box(AttributedString("x") + stored + AttributedString("hi"))
        let original = value.value
        let layer = Self.layer([0: [(0, nil), (2, .key), (4, .bold), (6, .plate), (7, nil)]])
        let row = try #require(editor(TextEditor(text: value.binding), layer: layer).rows().first)
        let redOnBlue = Self.drawn(ink: Sample.red, field: Sample.blue)
        #expect(row[1].state == redOnBlue, "the value's alone")
        for cell in row[2..<4] {
            #expect(cell.state == Self.drawn(ink: Sample.green, field: Sample.blue), "the highlight's ink, the value's field")
        }
        for cell in row[4..<6] {
            #expect(cell.state == Self.drawn(ink: Sample.red, field: Sample.blue, bold: true), "the highlight's bold, the value's colours: \(cell.character)")
        }
        #expect(row[6].state == Self.drawn(ink: Sample.red, field: Self.yellow), "the highlight's field, the value's ink")
        #expect(row[7].state == redOnBlue, "a gap: the value's")
        let plain = try #require(editor(TextEditor(text: .constant(value.value)), layer: nil).rows().first)
        #expect(row[8].state == plain[8].state, "neither")
        #expect(value.value == original, "the value is never written")
    }

    @Test("A selection's colours win over a highlight's, and its attributes stay")
    func selectionOverHighlight() throws {
        let text = "xabcdef"
        let layer = Self.layer([0: [(1, .bold), (4, .key)]])
        func select(_ handler: TextEditorHandler) {
            handler.moveCursor(toLine: 0, column: 2)
            handler.selectionAnchor = handler.cursor
            handler.startOrExtendSelection()
            handler.moveCursor(toLine: 0, column: 5)
        }
        let row = try #require(editor(TextEditor(text: .constant(text)), layer: layer, prepare: select).rows().first)
        let plain = try #require(editor(TextEditor(text: .constant(text)), layer: nil, prepare: select).rows().first)
        for column in 2..<5 {
            #expect(row[column].state.foregroundColour == plain[column].state.foregroundColour, "selected ink \(column)")
            #expect(row[column].state.backgroundColour == plain[column].state.backgroundColour, "selected field \(column)")
        }
        #expect(row[2].state.isBold && row[3].state.isBold, "the bold stays under the selection")
        #expect(row[1].state.isBold && !row[1].state.isOn(7))
        #expect(row[5].state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "past the selection, the highlight's")
    }

    @Test("The caret on a highlighted run draws as on any cell, and the run on either side of it")
    func caretOnHighlight() throws {
        let text = "xabc"
        let layer = Self.layer([0: [(0, .key)]])
        func caret(_ handler: TextEditorHandler) { handler.moveCursor(toLine: 0, column: 2) }
        let view = TextEditor(text: .constant(text)).textCursor(.block, animation: .none)
        let drawn = editor(view, layer: layer, prepare: caret)
        let row = try #require(drawn.rows().first)
        let plain = try #require(editor(view, layer: nil, prepare: caret).rows().first)
        #expect(drawn.handler.insertionPoint == CellPoint(x: 2, y: 0))
        #expect(row[2].state == plain[2].state, "the caret's own cell")
        for column in [0, 1, 3] { #expect(row[column].state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "\(column)") }
    }

    // MARK: - Disabled (A-DISED-1)

    @Test("A disabled editor fades a highlight's ink and field, as it fades a value's runs")
    func disabledFades() throws {
        try withColorDepth(.truecolor) {
            let disabled = TextEditorForegroundStyleTests.Flag(false)
            let context = makeRenderContext(width: 20, height: 3)
            @MainActor func view() -> some View {
                TextEditor(text: .constant("xabcd")).disabled(disabled.value).frame(width: 20, height: 3)
            }
            _ = renderToBuffer(view(), context: context)
            let handler = try #require(
                context.environment.focusManager?.activeSection?.focusables
                    .compactMap { $0 as? TextEditorHandler }.first)
            handler.replaceHighlightLayer(Self.layer([0: [(1, .key), (2, .plate), (3, nil)]]))
            @MainActor func row() throws -> [(character: Character, state: SGRState)] {
                Self.cells(try #require(renderToBuffer(view(), context: context).lines.first))
            }
            let enabled = try row()
            #expect(enabled[1].state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour)
            disabled.value = true
            let faded = (
                ink: TextEditorForegroundStyleTests.faded(Sample.green, in: context),
                field: TextEditorForegroundStyleTests.faded(Self.yellow, in: context)
            )
            try #require(faded.ink != Sample.green && faded.field != Self.yellow, "the premise: the fade shows")
            let off = try row()
            #expect(off[1].state.foregroundColour == Self.drawn(ink: faded.ink).foregroundColour, "the ink faded")
            #expect(off[2].state.backgroundColour == Self.drawn(field: faded.field).backgroundColour, "the field faded")
            disabled.value = false
            #expect(try row().map(\.state) == enabled.map(\.state), "enabled again")
        }
    }

    @Test(
        "A disabled editor whose highlight's fade the terminal's depth rounds away is drawn faint",
        arguments: [ColorDepth.basic16, .palette256])
    func swallowedFadeDrawsFaint(_ depth: ColorDepth) throws {
        try withColorDepth(depth) {
            let context = makeRenderContext(width: 20, height: 3)
            let palette = context.environment.palette
            let ground = palette.background.resolve(with: palette)
            let ink = try #require(
                TextEditorForegroundStyleTests.swallowedFade(over: ground, at: depth), "the premise: a fade rounds away")
            try #require(
                palette.foregroundTertiary.resolve(with: palette).downsampled(to: depth)
                    != palette.foreground.resolve(with: palette).downsampled(to: depth),
                "the premise: the plain text's grey shows at \(depth)")
            let disabled = TextEditorForegroundStyleTests.Flag(false)
            @MainActor func view() -> some View {
                TextEditor(text: .constant("xabcd")).disabled(disabled.value).frame(width: 20, height: 3)
            }
            _ = renderToBuffer(view(), context: context)
            let handler = try #require(
                context.environment.focusManager?.activeSection?.focusables
                    .compactMap { $0 as? TextEditorHandler }.first)
            handler.replaceHighlightLayer(
                Self.layer([0: [(1, .key), (3, nil)]]) { _ in
                    var container = AttributeContainer()
                    container.foregroundColor = ink
                    return container
                })
            @MainActor func row() throws -> [(character: Character, state: SGRState)] {
                Self.cells(try #require(renderToBuffer(view(), context: context).lines.first))
            }
            let enabled = try row()
            disabled.value = true
            let drawn = try row()
            for (live, off) in zip(enabled[1..<3], drawn[1..<3]) {
                #expect(!live.state.isFaint, "\(live.character) enabled, at \(depth)")
                #expect(off.state.isFaint, "\(off.character) disabled looks live at \(depth)")
            }
        }
    }

    // MARK: - Rows: alignment, line height, wrapping

    @Test(
        "A highlighted line its paragraph centres is drawn highlighted after the blank cells",
        arguments: ParagraphAlignmentSpelling.available)
    func alignedRow(_ spelling: ParagraphAlignmentSpelling) throws {
        var value = AttributedString("alpha\nhi")
        spelling.align(&value, value.range(of: "hi")!, .center)
        let rows = editor(
            TextEditor(text: .constant(value)), width: 12, height: 4, layer: Self.layer([1: [(0, .key)]])
        ).rows()
        // "hi" centred in 11 cells starts at cell 4.
        #expect(String(rows[1][4..<6].map(\.character)) == "hi")
        for cell in rows[1][4..<6] { #expect(cell.state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "\(cell.character)") }
        for cell in rows[1][0..<4] { #expect(cell.state.foregroundColour != Self.drawn(ink: Sample.green).foregroundColour) }
    }

    @Test(
        "A highlighted line after a paragraph of two rows a line is drawn on its own row, the blank row unstyled",
        arguments: LineRowsSpelling.available)
    func lineHeightRows(_ spelling: LineRowsSpelling) throws {
        var value = AttributedString("ab\ncd")
        spelling.set(&value, value.range(of: "ab")!, rows: 2)
        let layer = Self.layer([0: [(0, .plate)], 1: [(0, .key)]])
        let rows = editor(
            TextEditor(text: .constant(value)), width: 12, height: 4, layer: layer,
            prepare: { spelling.prepare($0) }
        ).rows()
        let text = rows.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
        #expect(Array(text.prefix(3)) == ["ab", "", "cd"])
        #expect(rows[0][1].state.backgroundColour == Self.drawn(field: Self.yellow).backgroundColour)
        #expect(rows[1].allSatisfy { $0.state.backgroundColour != Self.drawn(field: Self.yellow).backgroundColour })
        for cell in rows[2][0..<2] { #expect(cell.state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "\(cell.character)") }
    }

    @Test("A highlight run that wraps is drawn on both rows of its line")
    func wrappedRun() throws {
        let rows = editor(
            TextEditor(text: .constant("abcdefghijklmnop")), width: 12, height: 4,
            layer: Self.layer([0: [(0, nil), (8, .key), (14, nil)]])
        ).rows()
        #expect(String(rows[1].prefix(5).map(\.character)) == "lmnop")
        for cell in rows[0][8..<11] { #expect(cell.state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "\(cell.character)") }
        for cell in rows[1][0..<3] { #expect(cell.state.foregroundColour == Self.drawn(ink: Sample.green).foregroundColour, "\(cell.character)") }
        #expect(rows[1][3].state.foregroundColour != Self.drawn(ink: Sample.green).foregroundColour)
    }

    // MARK: - The drawn lines' cache, and the styles

    @Test("A line's runs are read when it is drawn, kept, and read again after an edit or a change to them")
    func cacheKeepsDrawnLines() {
        let reads = Box("")
        let text = Box("one\ntwo\nthree")
        var styles = EditorHighlightStyles()
        let key = styles.index(of: Token.key, style: Self.style)
        let layer = EditorHighlightLayer(
            runs: { line in
                reads.value += "\(line)"
                return [EditorHighlightRun(utf8Offset: 0, style: key)]
            }, styles: styles)
        let drawn = editor(TextEditor(text: text.binding), layer: layer)
        _ = drawn.rows()
        #expect(reads.value == "012")
        _ = drawn.rows()
        #expect(reads.value == "012", "kept between frames")
        drawn.handler.moveCursor(toLine: 1, column: 0)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .character("X")))
        _ = drawn.rows()
        #expect(reads.value == "0121", "the edited line alone")
        drawn.handler.highlightingChanged(inLines: 2..<3)
        _ = drawn.rows()
        #expect(reads.value == "01212", "the line whose highlighting changed alone")
        #expect(drawn.handler.lineStyleCache.drawnCount == 3)
        drawn.handler.hidingGlyph = "•"
        #expect(drawn.handler.styles(ofLine: 0).isEmpty, "hidden text is drawn in no highlight")
    }

    @Test("A token's style is asked for once; a palette change resolves it again without asking")
    func stylesInternedOnce() {
        let asked = Box(0)
        var styles = EditorHighlightStyles()
        let style: (Token) -> AttributeContainer = {
            asked.value += 1
            return Self.style($0)
        }
        let first = styles.index(of: Token.key, style: style)
        #expect(styles.index(of: Token.key, style: style) == first)
        #expect(styles.index(of: Token.word, style: style) != first)
        #expect(asked.value == 2)
        #expect(first != EditorHighlightStyles.none)
        var environment = EnvironmentValues()
        let firstAdopted = styles.adopt(EditorAttributedStyling(in: environment))
        let againAdopted = styles.adopt(EditorAttributedStyling(in: environment))
        #expect(firstAdopted)
        #expect(!againAdopted, "resolved already")
        #expect(styles.style(first)?.foreground == Sample.green)
        #expect(styles.style(EditorHighlightStyles.none) == nil && styles.style(99) == nil)
        let other = SystemPalette.Preset.allCases.map { SystemPalette($0) }.first { $0.id != environment.palette.id }!
        environment.palette = other
        let newPaletteAdopted = styles.adopt(EditorAttributedStyling(in: environment))
        #expect(newPaletteAdopted, "a new palette resolves again")
        #expect(asked.value == 2, "without asking for the style again")
    }

    // MARK: - Offsets and composition, alone

    @Test("UTF-8 offsets map to characters: one inside a character styles all of it; bad offsets are clamped")
    func offsetsToColumns() {
        var styles = EditorHighlightStyles()
        let key = styles.index(of: Token.key, style: Self.style)
        let word = styles.index(of: Token.word, style: Self.style)
        _ = styles.adopt(EditorAttributedStyling(in: EnvironmentValues()))
        // a: byte 0; é: 1–2; 😀: 3–6; b: 7; c: 8.
        let line = Array("aé😀bc")
        func columns(_ runs: [(Int, UInt16)]) -> [Range<Int>] {
            EditorHighlightRun.styledRuns(
                runs.map { EditorHighlightRun(utf8Offset: $0.0, style: $0.1) }, in: line, styles: styles
            ).map(\.columns)
        }
        #expect(columns([(0, 0), (2, key), (5, word), (7, 0)]) == [1..<2, 2..<3], "inside é and inside 😀")
        #expect(columns([(3, key), (1, word), (100, 0)]) == [2..<5], "backwards: the later run wins the character")
        #expect(columns([(-5, key)]) == [0..<5], "a negative offset is the line's start")
        #expect(columns([(9, key)]).isEmpty, "at the line's end: nothing")
        #expect(columns([(0, 999)]).isEmpty, "an unknown style draws nothing")
        #expect(EditorHighlightRun.styledRuns([EditorHighlightRun(utf8Offset: 0, style: key)], in: [], styles: styles).isEmpty)
        #expect(MemoryLayout<EditorHighlightRun>.stride == 8, "B-ATTRED-10: 8 bytes a run")
    }

    @Test("Overlaying matches a cell-by-cell composition, for any runs")
    func overlayMatchesCellByCell() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let colours = [Sample.red, Sample.blue, Sample.green, Sample.orange, nil]
        func runs() -> [EditorStyledRun] {
            var result: [EditorStyledRun] = []
            var column = next(3)
            while column < 24 {
                let length = 1 + next(5)
                var decoration = CellDecoration()
                decoration.isBold = next(2) == 0
                decoration.underline = next(3) == 0 ? .single : nil
                result.append(
                    EditorStyledRun(
                        columns: column..<(column + length), foreground: colours[next(5)],
                        background: colours[next(5)], decoration: decoration))
                column += length + next(3)
            }
            return result
        }
        func at(_ column: Int, _ runs: [EditorStyledRun]) -> EditorStyledRun? {
            runs.first { $0.columns.contains(column) }
        }
        for _ in 0..<200 {
            let (top, bottom) = (runs(), runs())
            let overlaid = EditorStyledRun.overlaying(top, on: bottom)
            #expect(zip(overlaid, overlaid.dropFirst()).allSatisfy { $0.columns.upperBound <= $1.columns.lowerBound })
            for column in 0..<32 {
                let (above, below, got) = (at(column, top), at(column, bottom), at(column, overlaid))
                #expect((got == nil) == (above == nil && below == nil), "covered at \(column)")
                guard let got else { continue }
                #expect(got.foreground == (above?.foreground ?? below?.foreground), "ink at \(column)")
                #expect(got.background == (above?.background ?? below?.background), "field at \(column)")
                let decoration = above.map { $0.decoration.over(below?.decoration ?? CellDecoration()) }
                #expect(got.decoration == decoration ?? below?.decoration, "decoration at \(column)")
            }
            for start in [0, 3, 10] {
                #expect(
                    EditorStyledRun.clipping(overlaid, toColumns: start, start + 7)
                        == overlaid.compactMap { $0.clipped(toColumns: start, start + 7) })
            }
        }
    }
}
