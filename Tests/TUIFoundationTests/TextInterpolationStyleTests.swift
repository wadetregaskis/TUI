//  🖥️ TUI — A Terminal UI framework for Swift
//  TextInterpolationStyleTests.swift
//
//  An interpolated `Text` keeps its styling, as SwiftUI's does — the
//  replacement SwiftUI names for the deprecated `Text + Text`. Each
//  expectation here is a case measured on macOS 15 (2026-10-18), where the
//  interpolation rendered exactly as the `+` of its pieces.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Interpolating a styled Text", .rendersEnglishUI)
struct TextInterpolationStyleTests {

    /// A run's words and the attributes the tests read.
    private struct Seen: Equatable {
        let text: String
        var bold: Bool?
        var italic: Bool?
        var colour: Color?
    }

    private func seen(_ text: Text) -> [Seen] {
        (text.runs ?? [Text.Run(text: text.content, style: TextStyle())]).map {
            Seen(text: $0.text, bold: $0.style.isBold, italic: $0.style.isItalic, colour: $0.style.foregroundColor)
        }
    }

    @Test("A bold fragment draws bold where its placeholder stands")
    func boldFragment() {
        let text = Text("Hello \(Text("world").bold())!")
        #expect(text.content == "Hello world!")
        #expect(seen(text) == [Seen(text: "Hello "), Seen(text: "world", bold: true), Seen(text: "!")])
    }

    @Test("The fragment's own colour survives a colour on the whole")
    func fragmentColourWins() {
        let text = Text("Hello \(Text("world").foregroundStyle(.red))!").foregroundStyle(.blue)
        #expect(text.style.foregroundColor == .blue, "the whole's colour is the base beneath every run")
        #expect(seen(text)[1] == Seen(text: "world", colour: .red))
        #expect(seen(text)[0].colour == nil, "a run that says nothing takes the base")
    }

    @Test("Inside a Markdown span the fragment takes what it leaves unset from the span")
    func spanFillsTheRest() {
        let italic = Text("**Hello \(Text("world").italic())**")
        #expect(seen(italic) == [Seen(text: "Hello ", bold: true), Seen(text: "world", bold: true, italic: true)])
        let unbold = Text("**Hello \(Text("world").bold(false))**")
        #expect(seen(unbold) == [Seen(text: "Hello ", bold: true), Seen(text: "world", bold: false)])
    }

    @Test("A fragment's own Markdown is kept")
    func nestedMarkdown() {
        let text = Text("A \(Text("**b** c"))")
        #expect(seen(text) == [Seen(text: "A "), Seen(text: "b", bold: true), Seen(text: " c")])
    }

    @Test("A fragment with no styling of its own leaves the key plain")
    func plainFragment() {
        let key: LocalizedStringKey = "Hello \(Text("world"))!"
        #expect(key.styledArguments.isEmpty)
        let text = Text(key)
        #expect(text.content == "Hello world!")
        #expect(text.runs == nil)
    }

    @Test("Whatever reads the key as a string reads the fragment's words")
    func wordsForStrings() {
        let key: LocalizedStringKey = "Hello \(Text("world").bold())!"
        #expect(key.localized == "Hello world!")
        #expect(key.resolvedTitle.plain == "Hello world!")
        #expect(key.resolvedTitle.styled != nil, "a control whose label is a Text draws the bold")
    }

    @Test("A translation that moves the placeholders moves the fragments with them")
    func reorderedTranslation() {
        LocalizationService.shared.registerWithoutRendering(
            translations: ["en": ["test.styledOrder %@ %@": "%2$@ before %1$@"]])
        let text = Text("test.styledOrder \(Text("first").bold()) \(Text("second").italic())")
        #expect(text.content == "second before first")
        #expect(
            seen(text) == [
                Seen(text: "second", italic: true), Seen(text: " before "), Seen(text: "first", bold: true),
            ])
    }

    @Test("A styled fragment draws its style on screen")
    func rendered() {
        let context = RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: TUIContext())
            .isolatingRenderCache()
        let line = renderToBuffer(Text("a \(Text("b").bold()) c"), context: context).lines[0]
        // SGR 1 is bold, alone or among other parameters, and it is on before
        // the "b" and not before the "a".
        let bold = /\u{1B}\[(?:[0-9;]*;)?1(?:;[0-9;]*)?m/
        #expect(line.stripped.hasPrefix("a b c"))
        let beforeB = line[..<(line.firstIndex(of: "b") ?? line.endIndex)]
        #expect(beforeB.contains(bold), "\(line)")
        let beforeA = line[..<(line.firstIndex(of: "a") ?? line.endIndex)]
        #expect(!beforeA.contains(bold), "\(line)")
    }

    @Test("A fragment's own secondary scale steps its intensity down, as a text's does")
    func secondaryFragment() {
        let context = RenderContext(availableWidth: 30, availableHeight: 1, tuiContext: TUIContext())
            .isolatingRenderCache()
        // Plain to faint, bold to plain — and the text around them as it was.
        let text = Text("a \(Text("b").textScale(.secondary)) \(Text("c").bold().textScale(.secondary)) d")
        let lines = renderToBuffer(text, context: context).lines
        // The on/off attributes on the word's first cell: the parameters
        // before any colour's, whose own numbers (`38;2;…`) are not flags.
        let parameters = { (word: String) in
            Set(
                (sgrState(of: word, in: lines)?.parameters ?? "").split(separator: ";").compactMap { Int($0) }
                    .prefix { ![38, 48, 58].contains($0) })
        }
        #expect(parameters("b").contains(2), "\(lines)")
        #expect(!parameters("c").contains(1) && !parameters("c").contains(2), "\(lines)")
        #expect(!parameters("a").contains(2) && !parameters("d").contains(2), "\(lines)")
    }
}
