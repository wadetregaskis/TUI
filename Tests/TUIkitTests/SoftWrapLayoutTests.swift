//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SoftWrapLayoutTests.swift
//
//  The rows an editable text soft-wraps into, and the mapping between caret
//  offsets and rows and columns.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The layout of `text` at `width`, one cell per character but for CJK.
private func layout(_ text: String, width: Int) -> SoftWrapLayout {
    SoftWrapLayout(Array(text), width: width) { max(1, $0.terminalWidth) }
}

/// Each row's characters, as strings.
private func rowTexts(_ text: String, width: Int) -> [String] {
    let characters = Array(text)
    return layout(text, width: width).rows.map { String(characters[$0.start..<$0.end]) }
}

@Suite("Soft-wrap layout")
struct SoftWrapLayoutTests {
    @Test("A newline ends a row and is drawn nowhere; a trailing one leaves an empty row")
    func newlines() {
        let rows = layout("ab\ncd\n", width: 10).rows
        #expect(rows == [
            .init(start: 0, end: 2, endsParagraph: true),
            .init(start: 3, end: 5, endsParagraph: true),
            .init(start: 6, end: 6, endsParagraph: true),
        ])
        #expect(layout("", width: 10).rows == [.init(start: 0, end: 0, endsParagraph: true)])
    }

    @Test("A row breaks after a run of spaces, which hangs at the end of the row it breaks")
    func spacesHang() {
        // Six cells: five of text and the margin. The space after "hello" sits in
        // the margin rather than starting the next row.
        #expect(rowTexts("hello world", width: 6) == ["hello ", "world"])
        #expect(rowTexts("aaa bbb ccc ddd", width: 9) == ["aaa bbb ", "ccc ddd"])
        // A longer run hangs whole, past the width.
        #expect(rowTexts("aaaa      bbbb", width: 6) == ["aaaa      ", "bbbb"])
        #expect(layout("hello world", width: 6).rows[0].endsParagraph == false)
    }

    @Test("Text wraps one cell short of the width, leaving the margin for the caret")
    func margin() {
        #expect(rowTexts("abcde", width: 5) == ["abcd", "e"])
        #expect(rowTexts("abcd", width: 5) == ["abcd"])
    }

    @Test("A word longer than a row breaks between characters")
    func longWord() {
        #expect(rowTexts("abcdefgh", width: 4) == ["abc", "def", "gh"])
    }

    @Test("A row may break between wide characters, and before one after narrow text")
    func wideCharacters() {
        #expect(rowTexts("中文字符", width: 5) == ["中文", "字符"])
        #expect(rowTexts("ab中", width: 4) == ["ab", "中"])
        // One wide character on a row too narrow for it still goes on it.
        #expect(rowTexts("中", width: 2) == ["中"])
    }

    @Test("A caret where a row wrapped is drawn on the later row, or on the earlier upstream")
    func affinity() {
        let wrapped = layout("hello world", width: 6)
        #expect(wrapped.row(of: 6, affinity: .automatic) == 1)
        #expect(wrapped.row(of: 6, affinity: .downstream) == 1)
        #expect(wrapped.row(of: 6, affinity: .upstream) == 0)
        // At a newline there is no choice to make: the offset is the earlier row's.
        let hard = layout("ab\ncd", width: 10)
        #expect(hard.row(of: 2, affinity: .automatic) == 0)
        #expect(hard.row(of: 3, affinity: .upstream) == 1)
    }

    @Test("A caret's column is the cells before it, held to the last cell")
    func columns() {
        let wrapped = layout("aaaa      bbbb", width: 6)
        #expect(wrapped.column(of: 2, inRow: 0) == 2)
        #expect(wrapped.column(of: 4, inRow: 0) == 4)
        // Further into the hanging run than the margin: held there.
        #expect(wrapped.column(of: 8, inRow: 0) == 5)
        let wide = layout("中文", width: 6)
        #expect(wide.column(of: 1, inRow: 0) == 2)
    }

    @Test("A column on a row maps to the caret before the character holding it")
    func offsets() {
        let wrapped = layout("hello world", width: 6)
        #expect(wrapped.offset(inRow: 1, atColumn: 2, affinity: .automatic) == 8)
        // Past the text of a row that ends a paragraph: its end.
        #expect(wrapped.offset(inRow: 1, atColumn: 30, affinity: .automatic) == 11)
        // Past the text of a wrapped row: before its last character, since its
        // end is drawn on the next row, unless the caret leans upstream.
        #expect(wrapped.offset(inRow: 0, atColumn: 30, affinity: .automatic) == 5)
        #expect(wrapped.offset(inRow: 0, atColumn: 30, affinity: .upstream) == 6)
        // The start of a wrapped row is drawn at the end of the row before it
        // upstream, so the row's first caret there is after its first character.
        #expect(wrapped.offset(inRow: 1, atColumn: 0, affinity: .automatic) == 6)
        #expect(wrapped.offset(inRow: 1, atColumn: 0, affinity: .upstream) == 7)
        for column in 0..<6 {
            let offset = wrapped.offset(inRow: 1, atColumn: column, affinity: .upstream)
            #expect(wrapped.row(of: offset, affinity: .upstream) == 1)
        }
        // Either cell of a wide character is that character.
        let wide = layout("中文", width: 6)
        #expect(wide.offset(inRow: 0, atColumn: 3, affinity: .automatic) == 1)
    }

    // MARK: - Widths that depend on the column

    /// Tabs to stops every four cells, as the editor lays them out.
    private func tabbed(_ text: String, width: Int) -> SoftWrapLayout {
        SoftWrapLayout(Array(text), width: width) { character, column in
            TabLayout.advance(from: column, over: character, tabWidth: .periodic(4))
        }
    }

    @Test("A tab reaches the next stop from where it starts: at a row's start and in its middle")
    func tabsReachTheirStops() {
        #expect(tabbed("\tab", width: 10).cellWidths == [4, 1, 1])
        #expect(tabbed("ab\tc", width: 10).cellWidths == [1, 1, 2, 1])
        #expect(tabbed("ab\tc", width: 10).column(of: 3, inRow: 0) == 4)
    }

    /// An `NSTextView`'s stops sit on its container's left edge, where every
    /// row starts (measured, macOS 15.8): a tab after a wrap is measured from
    /// its row, not from its paragraph.
    @Test("A tab on a wrapped row reaches its stop from the row's start")
    func tabStopsPerRow() {
        let layout = tabbed("aaaa bbbb cc\td", width: 10)
        #expect(layout.rows.map(\.start) == [0, 10])
        // From the paragraph's start the tab would begin at column 12 and take
        // four cells; from its row's, at column 2, and take two.
        #expect(layout.cellWidths[12] == 2)
        #expect(layout.column(of: 13, inRow: 1) == 4)
    }

    @Test("A tab is a place to break, and hangs past the margin as a space does")
    func tabsHang() {
        let layout = tabbed("aaaaaaaa\tb", width: 10)
        #expect(layout.rows == [
            .init(start: 0, end: 9, endsParagraph: false),
            .init(start: 9, end: 10, endsParagraph: true),
        ])
        #expect(layout.cellWidths[8] == 4)
    }
}
