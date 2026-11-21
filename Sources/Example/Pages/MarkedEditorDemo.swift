//  🖥️ TUI — A Terminal UI framework for Swift
//  MarkedEditorDemo.swift
//
//  The Text Input page's marked, highlighted editor (lane H4′ of the
//  highlighting design's §8.6): JSON coloured by a highlighter through the
//  `@_spi(TextEditorHighlighting)` seam, and its brackets that do not match
//  marked with the public `.textEditorMarks(_:in:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI
import TUIJSONStyler
@_spi(TextEditorHighlighting) import TUITextInput

/// A ``TextEditor`` of JSON. Its colours come from TUI's own JSON styler
/// through the highlighting seam, which is SPI for now. Its marks come from
/// the app: a check of the text for brackets that do not match, run on every
/// evaluation of the body and stated with the text it read, so the editor
/// draws them over the colours and carries them through each key.
struct MarkedEditorDemo: View {
    @State private var json: String = Self.sample

    /// JSON with one bracket too many, after the languages.
    static let sample = """
        {
          "name": "TUI",
          "languages": ["en", "de", "fr", "it", "es", "zh", "ja"]],
          "editor": { "wraps": true, "tabWidth": 4 }
        }
        """

    /// What a bracket that does not match is drawn in: the palette's error
    /// colour, with a curly underline where the terminal has one.
    private static var problem: AttributeContainer {
        var container = AttributeContainer()
        container.foregroundColor = Color.palette.error
        container.underlineStyle = Text.LineStyle(pattern: .curly, color: Color.palette.error)
        return container
    }

    var body: some View {
        DemoSection("page.textInput.marksSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.textInput.marksExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                let problems = Self.unmatchedBrackets(in: json)
                TextEditor(text: $json)
                    .textEditorHighlighter(JSONHighlighter(), style: JSONLineStyler.style)
                    .textEditorMarks(problems.map { TextEditorMark($0, attributes: Self.problem) }, in: json)
                    .frame(height: 5)
                    .border()
                if problems.isEmpty {
                    Text("page.textInput.marksNone").foregroundStyle(.palette.success)
                } else {
                    Text("page.textInput.marksCount \(problems.count)").foregroundStyle(.palette.error)
                }
            }
        }
    }

    /// The brackets of `text` that do not match, in order: each closing one
    /// that closes nothing or the other kind, and each opening one left open.
    /// Brackets inside strings are not counted, and a string ends at its
    /// line's end if not before, as the JSON styler's do.
    static func unmatchedBrackets(in text: String) -> [Range<String.Index>] {
        var open: [(bracket: UInt8, at: String.Index)] = []
        var problems: [Range<String.Index>] = []
        var inString = false
        var escaped = false
        let utf8 = text.utf8
        var index = utf8.startIndex
        while index != utf8.endIndex {
            let byte = utf8[index]
            let next = utf8.index(after: index)
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "\n") {
                    inString = false
                }
            } else {
                switch byte {
                case UInt8(ascii: "\""): inString = true
                case UInt8(ascii: "{"), UInt8(ascii: "["): open.append((byte, index))
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    let opener = byte == UInt8(ascii: "}") ? UInt8(ascii: "{") : UInt8(ascii: "[")
                    if open.last?.bracket == opener {
                        open.removeLast()
                    } else {
                        problems.append(index..<next)
                    }
                default: break
                }
            }
            index = next
        }
        problems += open.map { $0.at..<utf8.index(after: $0.at) }
        return problems.sorted { $0.lowerBound < $1.lowerBound }
    }
}
