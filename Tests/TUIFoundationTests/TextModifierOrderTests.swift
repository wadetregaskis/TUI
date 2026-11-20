//  🖥️ TUI — A Terminal UI framework for Swift
//  TextModifierOrderTests.swift
//
//  Of two of a `Text`'s own modifiers of one kind, the first written wins, as
//  in SwiftUI (measured on macOS 15.8.3:
//  `Tools/SwiftUIProbes/Text foregroundStyle levels (TXTFG)/stacked.out`), and
//  where a bold and a weight meet, the earlier applies to the later.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("A Text's own modifiers keep the first of two statements")
struct TextModifierOrderTests {

    private func drawn<V: View>(_ view: V, width: Int = 12, height: Int = 1) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    /// `stacked` draws as `expected` (SwiftUI's answer: mostly the first
    /// modifier alone), and not as `other`, which must differ from it.
    private func keepsFirst(
        _ stacked: Text, _ expected: Text, not other: Text, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (both, one, other) = (drawn(stacked), drawn(expected), drawn(other))
        #expect(one != other, "precondition: the two draw differently", sourceLocation: sourceLocation)
        #expect(both == one, "\(both.lines) against \(one.lines)", sourceLocation: sourceLocation)
    }

    private let text = Text("Sample")

    @Test("Bold, italic, underline and strikethrough keep the first")
    func emphasis() {
        keepsFirst(text.bold(false).bold(true), text, not: text.bold())
        keepsFirst(text.bold(true).bold(false), text.bold(), not: text)
        keepsFirst(text.italic(false).italic(true), text, not: text.italic())
        keepsFirst(text.italic().italic(false), text.italic(), not: text)
        keepsFirst(text.underline(false).underline(), text, not: text.underline())
        keepsFirst(text.underline().underline(false), text.underline(), not: text)
        keepsFirst(text.underline(pattern: .dot).underline(pattern: .solid), text.underline(pattern: .dot),
            not: text.underline(pattern: .solid))
        keepsFirst(text.underline(color: .red).underline(color: .blue), text.underline(color: .red),
            not: text.underline(color: .blue))
        keepsFirst(text.strikethrough(false).strikethrough(), text, not: text.strikethrough())
        keepsFirst(text.strikethrough().strikethrough(false), text.strikethrough(), not: text)
    }

    @Test("A font, font(nil) included, keeps the first")
    func font() {
        keepsFirst(text.font(.title).font(.caption), text.font(.title), not: text.font(.caption))
        keepsFirst(text.font(nil).font(.title), text, not: text.font(.title))
        keepsFirst(text.font(.title).font(nil), text.font(.title), not: text)
    }

    @Test("A weight keeps the first, and a bold before it applies to it, as SwiftUI's does")
    func weight() {
        let light = text.fontWeight(.ultraLight)
        let heavy = text.fontWeight(.heavy)
        keepsFirst(heavy.fontWeight(.ultraLight), heavy, not: light)
        // Measured: `bold()` before a light weight is light, before a regular
        // one bold; `bold(false)` before a heavy weight is regular, before a
        // light one light.
        keepsFirst(text.bold().fontWeight(.ultraLight), light, not: text.bold())
        keepsFirst(text.bold().fontWeight(.regular), text.bold(), not: text.fontWeight(.regular))
        keepsFirst(light.bold(), light, not: text.bold())
        keepsFirst(text.bold(false).fontWeight(.heavy), text, not: heavy)
        keepsFirst(text.bold(false).fontWeight(.ultraLight), light, not: text)
        keepsFirst(heavy.bold(false), heavy, not: text)
    }

    @Test("fontWeight(nil) is the font's own weight, over a weight or bold stated after it or above it")
    func fontsOwnWeight() {
        keepsFirst(text.fontWeight(nil).fontWeight(.heavy), text, not: text.fontWeight(.heavy))
        keepsFirst(text.fontWeight(nil).bold(), text, not: text.bold())
        #expect(drawn(text.bold().fontWeight(nil)) == drawn(text.bold()), "a bold before it still applies")
        // Above it: a view's weight and bold give way; a font's weight is the
        // text's own (measured: `.font(.body.bold())` keeps it bold).
        #expect(drawn(VStack { text.fontWeight(nil) }.fontWeight(.heavy)) == drawn(text))
        #expect(drawn(VStack { text.fontWeight(nil) }.bold()) == drawn(text))
        #expect(drawn(VStack { text }.bold()) != drawn(text), "precondition: a view's bold reaches a text")
        #expect(drawn(text.font(.headline).fontWeight(nil)) == drawn(text.font(.headline)))
        #expect(drawn(VStack { text.fontWeight(nil) }.font(.headline)) == drawn(VStack { text }.font(.headline)))
    }

    @Test("dim keeps the first faint statement, a weight's included")
    func dim() {
        keepsFirst(text.dim(false).dim(), text, not: text.dim())
        let light = text.fontWeight(.ultraLight)
        keepsFirst(light.dim(false), light, not: text)
        // A dim before a weight leaves it the bold to say.
        #expect(drawn(text.dim().fontWeight(.heavy)) == drawn(text.bold().dim()))
    }

    @Test("A text scale keeps the first")
    func textScale() {
        keepsFirst(text.textScale(.secondary).textScale(.default), text.textScale(.secondary), not: text)
        keepsFirst(text.textScale(.default).textScale(.secondary), text, not: text.textScale(.secondary))
    }

    @Test("A line limit and a truncation mode keep the first, as the nearer View modifier does in SwiftUI")
    func layout() {
        let long = Text("one two three four five six")
        #expect(drawn(long.lineLimit(1).lineLimit(3), width: 8, height: 3)
            == drawn(long.lineLimit(1), width: 8, height: 3))
        #expect(drawn(long.lineLimit(1), width: 8, height: 3) != drawn(long.lineLimit(3), width: 8, height: 3))
        let line = long.lineLimit(1)
        keepsFirst(line.truncationMode(.head).truncationMode(.tail), line.truncationMode(.head),
            not: line.truncationMode(.tail))
    }
}
