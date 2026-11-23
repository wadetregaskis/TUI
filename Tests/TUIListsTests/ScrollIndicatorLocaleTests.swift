//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorLocaleTests.swift
//
//  Numbers rendered into scroll chrome ("N more above/below") must be
//  locale-formatted — grouped with the app language's thousands separator
//  ("12,000" en, "12.000" de, "12 000" fr) — not a bare "12000".
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("scroll indicator number localisation", .rendersEnglishUI)
struct ScrollIndicatorLocaleTests {

    @Test("localizedInteger groups by locale")
    func groupsByLocale() {
        #expect(localizedInteger(12000, locale: Locale(identifier: "en")) == "12,000")
        #expect(localizedInteger(12000, locale: Locale(identifier: "de")) == "12.000")
        // fr uses a narrow no-break space (U+202F/U+00A0) — assert it's neither
        // a comma nor a dot, and that the digits survive.
        let fr = localizedInteger(12000, locale: Locale(identifier: "fr"))
        #expect(fr.filter(\.isNumber) == "12000")
        #expect(!fr.contains(","), "fr does not group with a comma: \(fr)")
        #expect(!fr.contains("."), "fr does not group with a dot: \(fr)")
        // Small numbers are ungrouped everywhere.
        #expect(localizedInteger(42, locale: Locale(identifier: "en")) == "42")
    }

    @Test("The indicator label carries the grouped count")
    func indicatorLabelGrouped() {
        let palette = EnvironmentValues().palette
        let en = renderScrollIndicator(
            direction: .down, count: 12000, unit: .lines, width: 40,
            palette: palette, cycle: nil, over: palette.background,
            locale: Locale(identifier: "en")
        ).text
        #expect(en.stripped.contains("12,000"), "en grouping in the label: \(en.stripped)")

        let de = renderScrollIndicator(
            direction: .down, count: 12000, unit: .lines, width: 40,
            palette: palette, cycle: nil, over: palette.background,
            locale: Locale(identifier: "de")
        ).text
        #expect(de.stripped.contains("12.000"), "de grouping in the label: \(de.stripped)")
    }

    /// The line as drawn, for `locale`, with its centring trimmed.
    private func line(
        _ direction: ScrollIndicatorDirection, _ count: Int, _ unit: ScrollIndicatorUnit, width: Int = 40,
        _ identifier: String, approximate: Bool = false
    ) -> String {
        let palette = EnvironmentValues().palette
        return renderScrollIndicator(
            direction: direction, count: count, unit: unit, width: width, palette: palette, approximate: approximate,
            cycle: nil, over: palette.background, locale: Locale(identifier: identifier)
        ).text.stripped.trimmingCharacters(in: .whitespaces)
    }

    @Test("The label's words are the locale's language, with its plural")
    func wordsFollowTheLocale() {
        let german = line(.down, 12000, .rows, "de")
        #expect(!german.contains("more") && !german.contains("rows") && !german.contains("below"), "\(german)")
        #expect(german == "▼ 12.000 weitere Zeilen unten")
        #expect(line(.up, 1, .rows, "de") == "▲ 1 weitere Zeile oben", "German's one")
        #expect(line(.down, 3, .lines, "es") == "▼ 3 líneas más abajo")
        // French counts zero as one.
        #expect(line(.up, 0, .rows, "fr") == "▲ 0 ligne de plus au-dessus")
        #expect(line(.up, 2, .rows, "fr") == "▲ 2 lignes de plus au-dessus")
        #expect(line(.down, 1, .rows, "it") == "▼ 1 altra riga sotto")
        #expect(line(.down, 5, .lines, "zh") == "▼ 下方还有5行")
        // The approximate count's suffix is unchanged; only the words move.
        #expect(line(.down, 5400, .lines, "de", approximate: true) == "▼ ~5,4K weitere Zeilen unten")
        // English as it was.
        #expect(line(.down, 1, .rows, "en") == "▼ 1 more row below")
    }

    @Test("The label degrades by cells, so a wide-glyph language fits its width")
    func ladderFitsByCells() {
        #expect(line(.down, 14, .rows, "ja") == "▼ 下にあと14行")
        // Each rung of the ladder in Japanese: 下にあと14行 is 12 cells, 下に14行
        // 8, 14行 4; the line takes the arrow and a blank either side as well.
        #expect(line(.down, 14, .rows, width: 15, "ja") == "▼ 下にあと14行")
        #expect(line(.down, 14, .rows, width: 14, "ja") == "▼ 下に14行")
        #expect(line(.down, 14, .rows, width: 10, "ja") == "▼ 14行")
        #expect(line(.down, 14, .rows, width: 6, "ja") == "▼ 14")
        let palette = EnvironmentValues().palette
        for language in ["ja", "zh", "de", "fr"] {
            for width in 1...30 {
                let drawn = renderScrollIndicator(
                    direction: .down, count: 14, unit: .rows, width: width, palette: palette,
                    cycle: nil, over: palette.background, locale: Locale(identifier: language)
                ).text
                #expect(drawn.strippedLength <= max(width, 2), "\(language) at \(width): \(drawn.stripped)")
            }
        }
    }

    @Test("The approximate label localises its decimal separator")
    func approximateDecimalLocalised() {
        // 5400 → "~5.4K" (en) / "~5,4K" (de).
        #expect(approximateCountLabel(5400, locale: Locale(identifier: "en")) == "~5.4K")
        #expect(approximateCountLabel(5400, locale: Locale(identifier: "de")) == "~5,4K")
    }

    @Test("A List renders its 'N more' count grouped, in the environment's locale")
    func listIndicatorGrouped() {
        // 3000 items in a short frame → a "N more below" indicator whose count
        // is in the thousands, so grouping is observable. Which separator is
        // asked for below, not assumed: `applyRuntimeServices` republishes
        // `\.locale` from the app language, so "the default is English" was
        // only true for a developer whose LANG said so — a German one got
        // "2.999" and this case failed for reasons that had nothing to do
        // with the List.
        struct Item: Identifiable { let id: Int }
        let tuiContext = TUIContext()
        let view = List(
            (0..<3000).map(Item.init), selection: Binding<Int?>.constant(nil)
        ) { item in Text("row \(item.id)") }
        .frame(height: 6)

        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.locale = Locale(identifier: "en")
        // Predates the visibility/style split (#555): these assertions are written
        // against the "N more above / below" lines, which are now a style. The
        // shipped default is a scrollbar; cases about THAT ask for it by name.
        environment.scrollIndicatorStyle = .text
        // Beside the content: this reads the "N more" line drawn at rest, which
        // the default (.overContent) draws only for the pointer or the focus.
        environment.scrollIndicatorPlacement = .besideContent
        let context = RenderContext(
            availableWidth: 40, availableHeight: 6,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        let text = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        // English default → the thousands count is grouped with a comma and
        // never appears as a bare four-plus-digit run.
        #expect(text.contains(","), "the count is grouped: \(text)")
        #expect(!text.contains("2999"), "no un-grouped 4-digit count leaks: \(text)")
    }

    @Test("A List under a German locale says its 'N more' in German")
    func listIndicatorInGerman() {
        struct Item: Identifiable { let id: Int }
        let tuiContext = TUIContext()
        let view = List((0..<30).map(Item.init), selection: Binding<Int?>.constant(nil)) { item in
            Text("row \(item.id)")
        }
        .frame(height: 6)
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.locale = Locale(identifier: "de")
        environment.scrollIndicatorStyle = .text
        environment.scrollIndicatorPlacement = .besideContent
        let context = RenderContext(
            availableWidth: 40, availableHeight: 6, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        let text = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("weitere Zeilen unten"), "\(text)")
        #expect(!text.contains("more") && !text.contains("rows"), "\(text)")
    }
}
