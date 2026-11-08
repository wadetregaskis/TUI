//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderOnceToStringTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp

/// `renderOnceToString`: what `renderOnce` writes, returned, at the width and
/// height asked for, as plain text unless styling is asked for.
@MainActor
@Suite("renderOnceToString")
struct RenderOnceToStringTests {
    @Test("Plain text by default: the rows joined by newlines, none after the last")
    func plainByDefault() {
        let text = renderOnceToString(width: 20) {
            VStack(alignment: .leading) {
                Text("one").bold()
                Text("two")
            }
        }
        #expect(text == "one\ntwo")
    }

    @Test("The width is the columns drawn in, and a row keeps no trailing spaces")
    func width() {
        let row = renderOnceToString(width: 10) {
            HStack {
                Text("a")
                Spacer()
                Text("b")
            }
        }
        #expect(row == "a        b")
        let narrow = renderOnceToString(width: 4) {
            HStack {
                Text("a")
                Spacer()
            }
        }
        #expect(narrow == "a")
    }

    @Test("A height is offered to the view, and the result has at most that many rows")
    func height() {
        let filled = renderOnceToString(width: 10, height: 4) {
            VStack(alignment: .leading) {
                Text("top")
                Spacer()
                Text("bottom")
            }
        }
        #expect(filled.split(separator: "\n", omittingEmptySubsequences: false) == ["top", "", "", "bottom"])
        let cropped = renderOnceToString(width: 10, height: 2) {
            VStack {
                ForEach(0..<5, id: \.self) { Text("row \($0)") }
            }
        }
        #expect(cropped.split(separator: "\n", omittingEmptySubsequences: false).count == 2)
    }

    @Test("Without a height, the view gets the height it asks for, as renderOnce gives it")
    func naturalHeight() {
        let text = renderOnceToString(width: 10) {
            VStack(alignment: .leading) {
                Text("top")
                Spacer()
                Text("bottom")
            }
        }
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
        // The Spacer at its least, not the terminal's height.
        #expect(rows.first == "top")
        #expect(rows.last == "bottom")
        #expect(rows.count <= 3)
    }

    @Test("Escape sequences keep the styling, in the colour depth asked for")
    func escapeSequences() {
        func red(_ depth: ColorDepth) -> String {
            renderOnceToString(width: 10, output: .escapeSequences, colorDepth: depth) {
                Text("red").foregroundStyle(Color.rgb(255, 0, 0))
            }
        }
        #expect(red(.truecolor).contains("38;2;255;0;0"))
        #expect(red(.palette256).contains("38;5;196"))
        #expect(!red(.noColor).contains("38;"))
        // Each styled row ends its styling, and the result no newline.
        #expect(red(.truecolor).hasSuffix("\u{1B}[0m"))
    }

    @Test("A width or height below 1 draws at 1 rather than failing")
    func degenerateSizes() {
        let text = renderOnceToString(width: 0, height: -3) { Text("x") }
        #expect(text == "x")
    }
}
