//  🖥️ TUI — A Terminal UI framework for Swift
//  TextTransliterationTests.swift
//
//  `TUI_PLAIN_TEXT=transliterate`: text spelled in ASCII before it is laid out,
//  so the layout makes room for "ni hao" where the folding at output can only
//  cut it to "niha". The point is that the measure and the render agree on the
//  spelled string, as they do on a cased or a redacted one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Text spelled in ASCII before layout")
struct TextTransliterationTests {

    private func lines(_ view: some View, transliterating: Bool = true, width: Int = 30) -> [String] {
        var context = makeRenderContext(width: width, height: 6)
        context.environment.transliteratesText = transliterating
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    private func first(_ view: some View, transliterating: Bool = true, width: Int = 30) -> String {
        (lines(view, transliterating: transliterating, width: width).first ?? "")
            .replacingOccurrences(of: " +$", with: "", options: .regularExpression)
    }

    private func size(_ view: some View, transliterating: Bool = true) -> ViewSize {
        var context = makeRenderContext(width: 30, height: 6)
        context.environment.transliteratesText = transliterating
        return measureChild(view, proposal: ProposedSize(width: 30, height: 6), context: context)
    }

    @Test("Off by default: the words are drawn as written")
    func offByDefault() {
        #expect(EnvironmentValues().transliteratesText == false)
        #expect(first(Text(verbatim: "Café 你好"), transliterating: false) == "Café 你好")
    }

    @Test("ASCII comes back as it was, the same string")
    func asciiIsUntouched() {
        #expect(TextTransliteration.transliterated("plain words") == "plain words")
        #expect(TextTransliteration.transliterated("Café", if: false) == "Café")
    }

    @Test("What the transform has nothing to say about is left for the folding at output")
    func emojiIsLeft() {
        #expect(TextTransliteration.transliterated("ok 🙂").hasSuffix("🙂"))
    }

    #if canImport(Darwin)
        // Foundation's transliterators are ICU's; on Darwin they are certain to
        // be there. Elsewhere `spelled` may answer the string unchanged.

        @Test("Other scripts are spelled in Latin letters, at the width they then take")
        func spelled() {
            #expect(first(Text(verbatim: "你好")) == "ni hao")
            #expect(first(Text(verbatim: "Привет, Ελλάδα")) == "Privet, Ellada")
            #expect(first(Text(verbatim: "Café")) == "Cafe")
            #expect(size(Text(verbatim: "你好")).width == 6)
            #expect(size(Text(verbatim: "你好"), transliterating: false).width == 4)
        }

        @Test("Spelled before it is cased, so the case has letters to change")
        func spelledThenCased() {
            #expect(first(Text(verbatim: "你好").textCase(.uppercase)) == "NI HAO")
        }

        @Test("A redaction covers the spelled words, cell for cell")
        func redactionCoversSpelling() {
            #expect(first(Text(verbatim: "你好").redacted(reason: .placeholder)) == "░░ ░░░")
        }

        @Test("Text interpolated into Text spells each of its runs")
        func runs() {
            let greeting = Text(verbatim: "Привет")
            let world = Text(verbatim: "мир").bold()
            #expect(first(Text("\(greeting) \(world)")) == "Privet mir")
        }

        @Test("A button's title, drawn by its style rather than by a Text, is spelled too")
        func buttonTitle() {
            let drawn = first(Button("Готово") {})
            #expect(drawn.contains("Gotovo"), "\(drawn.debugDescription)")
        }

        @Test("A container's title, drawn into its border, is spelled and measured spelled")
        func containerTitle() {
            let drawn = lines(ContainerView(title: "你好") { Text(verbatim: "x") }).first ?? ""
            #expect(drawn.contains(" ni hao "), "\(drawn.debugDescription)")
        }

        @Test("A string spelled twice comes back the same: the second from the memo")
        func memoAgrees() {
            let first = TextTransliteration.transliterated("Здравствуйте")
            #expect(first == "Zdravstvujte")
            #expect(TextTransliteration.transliterated("Здравствуйте") == first)
            #expect(TextTransliteration.spelled("Здравствуйте") == first)
        }
    #endif
}
