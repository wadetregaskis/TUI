//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextMarkdownTests.swift
//
//  Markdown in a `Text` made from a key: where SwiftUI applies it (a key, not
//  a `String`), in what order (the template before the values), and what it
//  draws — each rule measured on macOS 15.8 by comparing offscreen renders.
//  The parse itself is `InlineMarkdownTests`'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling

@MainActor
@Suite("Markdown in a Text")
struct TextMarkdownTests {

    private func lines(_ text: Text, width: Int = 60) -> [String] {
        renderToBuffer(text, context: makeRenderContext(width: width, height: 4)).lines
    }

    /// The on/off attributes (1 bold … 9 strikethrough) on `word`'s first cell.
    private func attributes(of word: String, in lines: [String]) -> Set<Int> {
        guard let state = sgrState(of: word, in: lines) else { return [] }
        let parameters = state.parameters.split(separator: ";").compactMap { Int($0) }
        var result: Set<Int> = []
        var index = 0
        while index < parameters.count {
            if parameters[index] == 38 || parameters[index] == 48 {
                index += index + 1 < parameters.count && parameters[index + 1] == 2 ? 5 : 3
                continue
            }
            if (1...9).contains(parameters[index]) { result.insert(parameters[index]) }
            index += 1
        }
        return result
    }

    /// Each run's text and the attributes it states, for comparing structure.
    private func runs(_ text: Text) -> [String] {
        (text.runs ?? []).map { run in
            var flags = ""
            if run.style.isBold == true { flags += "b" }
            if run.style.isItalic == true { flags += "i" }
            if run.style.isStrikethrough == true { flags += "s" }
            if let link = run.link { flags += "→" + link.absoluteString }
            if run.live != nil { flags += "~" }
            return run.text + (flags.isEmpty ? "" : "|" + flags)
        }
    }

    // MARK: - What it draws

    @Test("A literal's Markdown draws, and its markers do not")
    func literal() {
        let text = Text("**strong** *em* ~~struck~~ `code` plain")
        #expect(text.content == "strong em struck code plain")
        let drawn = lines(text)
        #expect(attributes(of: "strong", in: drawn) == [1])
        #expect(attributes(of: "em", in: drawn) == [3])
        #expect(attributes(of: "struck", in: drawn) == [9])
        #expect(attributes(of: "code", in: drawn).isEmpty)
        #expect(attributes(of: "plain", in: drawn).isEmpty)
    }

    @Test("A link in a literal is a link")
    func link() {
        let text = Text("Visit our [website](https://example.com).")
        #expect(text.content == "Visit our website.")
        #expect(runs(text) == ["Visit our ", "website|→https://example.com", "."])
    }

    @Test("A key with nothing to parse is a plain text, as before")
    func plainKeys() {
        for key: LocalizedStringKey in ["Save", "Name:", "100% done", "snake_case_name", "a * b", "[x]"] {
            let text = Text(key)
            #expect(text.runs == nil, "\(key)")
        }
        #expect(Text("snake_case_name").content == "snake_case_name")
        #expect(Text("a * b").content == "a * b")
    }

    @Test("An escape draws its character and leaves a plain text")
    func escapes() {
        let text = Text("\\*not emphasis\\*")
        #expect(text.content == "*not emphasis*")
        #expect(text.runs == nil)
    }

    // MARK: - Where it applies

    @Test("A String, and Text(verbatim:), are never parsed")
    func onlyKeys() {
        let computed = "**not parsed**"
        #expect(Text(computed).content == "**not parsed**")
        #expect(Text(computed).runs == nil)
        #expect(Text(verbatim: "**not parsed**").content == "**not parsed**")
        #expect(Text(LocalizedStringKey(computed)).content == "not parsed")
    }

    @Test("A translation's Markdown draws")
    func translation() {
        // SwiftUI parses the string the key resolves to, so a translation can
        // style differently from the key it translates.
        LocalizationService.shared.register(translations: [
            "en": ["test.markdown.translated": "*localised* text"]
        ])
        let text = Text("test.markdown.translated")
        #expect(text.content == "localised text")
        #expect(runs(text) == ["localised|i", " text"])
    }

    // MARK: - Arguments

    @Test("A value takes the style of where it stands")
    func valueTakesItsPlacesStyle() {
        let count = 3
        #expect(runs(Text("Saved **\(count)** files")) == ["Saved ", "3|b", " files"])
        // Even a value whose spaces would stop `** x **` being strong.
        let spaced = " x "
        #expect(runs(Text("**\(spaced)**")) == [" x |b"])
    }

    @Test("A value is drawn as written, never parsed")
    func valuesAreNotParsed() {
        let starred = "*x*"
        let text = Text("A \(starred)")
        #expect(text.content == "A *x*")
        #expect(text.runs == nil)
        // Delimiters that only pair across values stay text.
        let star = "*"
        #expect(Text("\(star)a\(star)").content == "*a*")
        #expect(Text("\(star)a\(star)").runs == nil)
        // A URL that arrives as a value is not autolinked.
        let url = "https://example.com"
        #expect(Text("see \(url)").runs == nil)
    }

    @Test("A value can complete a link's destination")
    func valueInDestination() {
        let id = 42
        #expect(runs(Text("[ticket](https://example.com/t/\(id))")) == ["ticket|→https://example.com/t/42"])
    }

    @Test("Percent signs read as they do without Markdown")
    func percents() {
        // A key with no values has no placeholders: its `%` is a percent.
        #expect(Text("100% **done**").content == "100% done")
        let done = 5
        #expect(Text("\(done)% **done**").content == "5% done")
    }

    @Test("A live value stays live inside its style")
    func liveValue() {
        let text = Text("Due **\(Date(timeIntervalSinceNow: 7200), style: .relative)**")
        #expect(text.isLive)
        #expect(text.runs?.last?.style.isBold == true)
        #expect(text.runs?.last?.live != nil)
        #expect(text.runs?.first?.live == nil)
    }

    // MARK: - The kept parse

    @Test("A template is parsed once, and its parse is kept")
    func templateIsKept() {
        // A template no other test uses, so the first build is the one that
        // files it — or, at the cap, empties the cache and then files it.
        let before = MarkdownTemplate.keptCount
        let first = 1
        _ = Text("**\(first)** kept, in `TextMarkdownTests`")
        let filed = MarkdownTemplate.keptCount
        #expect(filed == before + 1 || filed == 1)
        let second = 2
        _ = Text("**\(second)** kept, in `TextMarkdownTests`")
        #expect(MarkdownTemplate.keptCount == filed)
    }

    @Test("One template's kept parse takes each build's own values")
    func keptParseTakesEachValue() {
        for (name, status) in [("ann", "ok"), ("bo", "failed"), ("*c*", "`x`")] {
            #expect(runs(Text("**\(name)** in `\(status)`")) == ["\(name)|b", " in \(status)"])
        }
        for id in [42, 7] {
            #expect(runs(Text("[ticket](https://example.com/t/\(id))")) == ["ticket|→https://example.com/t/\(id)"])
        }
    }

    @Test("A kept parse is not live because the build that filed it was")
    func keptParseKeepsNoLiveness() {
        // `\(date, style: .relative)` and `\(name)` both make "Due **%@**".
        let due = Date(timeIntervalSinceNow: 7200)
        #expect(Text("Due **\(due, style: .relative)**").runs?.last?.live != nil)
        let name = "Friday"
        #expect(runs(Text("Due **\(name)**")) == ["Due ", "Friday|b"])
        #expect(Text("Due **\(due, style: .relative)**").runs?.last?.live != nil)
    }

    @Test("A template with values and the same one without are parsed apart")
    func keptParseKnowsWhetherThereAreValues() {
        // Without values a `%` is a percent; with them, a placeholder — so the
        // same template parses two ways, whichever comes first.
        let template = "%@ **x** kept"
        for _ in 0..<2 {
            #expect(Text(LocalizedStringKey(template)).content == "%@ x kept")
            #expect(Text(LocalizedStringKey(key: template, arguments: ["5"])).content == "5 x kept")
        }
    }

    @Test("A translation registered later is parsed as itself")
    func keptParseFollowsTheTranslation() {
        // The parse is kept by the text the key resolves to, so a new
        // translation of the same key is a new template.
        LocalizationService.shared.register(translations: [
            "en": ["test.markdown.kept": "*first* text"]
        ])
        #expect(runs(Text("test.markdown.kept")) == ["first|i", " text"])
        LocalizationService.shared.register(translations: [
            "en": ["test.markdown.kept": "**second** text"]
        ])
        #expect(runs(Text("test.markdown.kept")) == ["second|b", " text"])
    }

    @Test("A key with no live values fills the kept merge exactly as span by span")
    func plannedRunsAgreeWithTheSpans() {
        // `filled(by:)` answers a key with no live values from the merge kept
        // with the parse; the span-by-span fill is the reading it must agree
        // with — the same content and the same runs, merged or not. Every
        // source of the measured inline table, with a placeholder at four
        // places, under values that are empty, wide, or look like Markdown.
        var planned = 0
        var cases = 0
        for source in InlineMarkdownTests.measured.map(\.source) {
            let characters = Array(source)
            let templates = [0, min(1, characters.count), characters.count / 2, characters.count].map { cut in
                String(characters[..<cut]) + "%@" + String(characters[cut...])
            }
            for template in templates {
                for values in [["x"], [""], ["**y** `z`"], ["日本 a"], ["a", "b"]] {
                    let key = LocalizedStringKey(key: template, arguments: values)
                    let parse = MarkdownTemplate(parsing: template, for: key)
                    if parse.fillsFromPlan { planned += 1 }
                    cases += 1
                    let filled = parse.filled(by: key)
                    let bySpans = parse.filledBySpans(by: key)
                    #expect(filled.content == bySpans.content, "\(template.debugDescription) \(values)")
                    #expect(filled.runs == bySpans.runs, "\(template.debugDescription) \(values)")
                }
            }
        }
        // Not vacuous: most cases have a placeholder in their words and
        // none in a destination, which is when the kept merge answers.
        #expect(planned > cases / 2, "only \(planned) of \(cases) cases filled from the kept merge")
    }

    @Test("The kept parses are bounded")
    func keptParsesAreBounded() {
        for index in 0...MarkdownTemplate.cacheLimit {
            _ = Text(LocalizedStringKey("**bounded \(index)**"))
            #expect(MarkdownTemplate.keptCount <= MarkdownTemplate.cacheLimit)
        }
    }
}
