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
        context.textSpelling = transliterating ? .ascii(.standard) : .asWritten
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    private func first(_ view: some View, transliterating: Bool = true, width: Int = 30) -> String {
        (lines(view, transliterating: transliterating, width: width).first ?? "")
            .replacingOccurrences(of: " +$", with: "", options: .regularExpression)
    }

    private func size(_ view: some View, transliterating: Bool = true) -> ViewSize {
        var context = makeRenderContext(width: 30, height: 6)
        context.textSpelling = transliterating ? .ascii(.standard) : .asWritten
        return measureChild(view, proposal: ProposedSize(width: 30, height: 6), context: context)
    }

    @Test("Off by default: the words are drawn as written")
    func offByDefault() {
        #expect(EnvironmentValues().textSpelling == .asWritten)
        #expect(makeRenderContext().textSpelling == .asWritten)
        #expect(first(Text(verbatim: "Café 你好"), transliterating: false) == "Café 你好")
    }

    /// The key symbols have no letters for ICU to read, and folded at output
    /// in their one cell they came out blank: `⌃Q 退出` was ` Q tui chu`.
    /// Control is a caret, as terminals write it; the other modifiers, which
    /// have no one-character spelling, and the keys that type nothing, are
    /// their names, as `TUI_KEY_SYMBOLS=0` writes them.
    @Test("Key symbols are spelled: ⌃ as a caret, the other modifiers and keys by name")
    func keySymbols() {
        #expect(TextTransliteration.transliterated("⌃Q quit") == "^Q quit")
        #expect(TextTransliteration.transliterated("⌥F") == "Alt-F")
        #expect(TextTransliteration.transliterated("⇧⇥") == "Shift-Tab")
        #expect(TextTransliteration.transliterated("⌘S") == "Cmd-S")
        #expect(TextTransliteration.transliterated("⌃⇧Z") == "Ctrl-Shift-Z")
        #expect(TextTransliteration.transliterated("⌃+C") == "Ctrl+C")
        #expect(TextTransliteration.transliterated("⎋ back") == "Esc back")
    }

    @Test("ASCII comes back as it was, the same string")
    func asciiIsUntouched() {
        #expect(TextTransliteration.transliterated("plain words") == "plain words")
        #expect(TextTransliteration.spelled("Café", as: .asWritten) == "Café")
    }

    @Test("What the transform has nothing to say about is left for the folding at output")
    func boxDrawingIsLeft() {
        #expect(TextTransliteration.transliterated("ok ✓ ┼") == "ok ✓ ┼")
    }

    @Test("A context made from an environment carries its spelling; a copy keeps it")
    func contextCarriesSpelling() {
        var environment = EnvironmentValues()
        environment.textSpelling = .ascii(.japanese)
        let context = RenderContext(availableWidth: 10, availableHeight: 1, environment: environment)
        #expect(context.textSpelling == .ascii(.japanese))
        #expect(context.withChildIdentity(type: Text.self, index: 0).textSpelling == .ascii(.japanese))
        #expect(context.spelled("plain") == "plain")
    }

    @Test("A reading for each language that reads a script its own way, and the standard one for the rest")
    func readings() {
        #expect(TextReading(languageCode: "ja") == .japanese)
        #expect(TextReading(languageCode: "uk") == .ukrainian)
        #expect(TextReading(languageCode: "sr") == .serbian)
        #expect(TextReading(languageCode: "zh") == .standard)
        #expect(TextReading(languageCode: "en") == .standard)
        #expect(TextReading(languageCode: nil) == .standard)
    }

    @Test("Emoji are spelled as emoticons, short names or their Unicode names, without ICU")
    func emoji() {
        #expect(EmojiSpelling.spelled("ok 🙂") == "ok :)")
        #expect(EmojiSpelling.spelled("👍🏽 ❤️ 🎉") == ":+1: <3 :tada:")
        #expect(EmojiSpelling.spelled("🦋") == ":butterfly:")
        #expect(EmojiSpelling.spelled("🇯🇵 1️⃣") == "[JP] [1]")
        #expect(EmojiSpelling.spelled("👨‍👩‍👧") == ":man_woman_girl:")
        // Text by default: left for `Latin-ASCII`, which knows them.
        #expect(EmojiSpelling.spelled("© ™ ↩︎ 1") == "© ™ ↩︎ 1")
    }

    @Test("The marks Latin-ASCII keeps become an apostrophe, or go")
    func marks() {
        #expect(TextTransliteration.withoutMarks("alʿrbyt obʺyëm") == "al'rbyt obyëm")
    }

    #if canImport(Darwin)
        // Foundation's transliterators are ICU's; on Darwin they are certain to
        // be there. Elsewhere `spelled` may answer the string unchanged.

        @Test("Other scripts are spelled in Latin letters, at the width they then take")
        func spelled() {
            #expect(first(Text(verbatim: "你好")) == "ni hao")
            #expect(first(Text(verbatim: "Привет, Ελλάδα")) == "Privet, Ellada")
            #expect(first(Text(verbatim: "ok 🙂")) == "ok :)")
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
            #expect(first == "Zdravstvuyte")
            #expect(TextTransliteration.transliterated("Здравствуйте") == first)
            #expect(TextTransliteration.spelling("Здравствуйте", reading: .standard) == first)
        }

        @Test("Cyrillic by BGN/PCGN, as the words sound, and by the app's language's own")
        func cyrillic() {
            #expect(TextTransliteration.transliterated("Имя, Щука, Юрий") == "Imya, Shchuka, Yuriy")
            #expect(TextTransliteration.transliterated("Київ", reading: .ukrainian) == "Kyyiv")
            #expect(TextTransliteration.transliterated("България", reading: .bulgarian) == "Bulgariya")
        }

        @Test("Greek by UNGEGN's modern romanization")
        func greek() {
            #expect(TextTransliteration.transliterated("Αθήνα, ευχαριστώ") == "Athina, efcharisto")
        }

        @Test("Japanese read as Japanese where it has kana or the app is Japanese; Han alone as Chinese")
        func japanese() {
            #expect(TextTransliteration.transliterated("日本語", reading: .japanese) == "nippon go")
            #expect(TextTransliteration.transliterated("東京へ行きます") == "toukyou he iki masu")
            #expect(TextTransliteration.transliterated("日本語") == "ri ben yu")
            #expect(TextTransliteration.transliterated("你好", reading: .japanese).isEmpty == false)
        }

        @Test("Korean by ICU's Revised Romanization transliteration; Arabic's ʿayin as an apostrophe")
        func koreanAndArabic() {
            #expect(TextTransliteration.transliterated("안녕하세요, 서울") == "annyeonghaseyo, seoul")
            #expect(TextTransliteration.transliterated("العربية") == "al'rbyt")
        }
    #endif
}
