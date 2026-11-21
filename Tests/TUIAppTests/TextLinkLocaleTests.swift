//  🖥️ TUI — A Terminal UI framework for Swift
//  TextLinkLocaleTests.swift
//
//  A key-made `Text` read again under a subtree's language routes its links
//  by the runs of the words it draws (LEAF-1, H-10).
//
//  The stops were filed under the translation's run indices and looked up in
//  the original's runs: a translation with the link in another run trapped,
//  one with two links swapped opened the other link, and any key-made text so
//  read had a focused link that did not breathe, its recoloured copy read
//  again from the key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUIStrings
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("A Text's links read in a subtree's language", .rendersEnglishUI)
struct TextLinkLocaleTests {
    static let first = URL(string: "https://first.example/")!
    static let second = URL(string: "https://second.example/")!

    init() {
        // Keys of this suite's own, so no other suite reads them.
        LocalizationService.shared.registerWithoutRendering(translations: [
            "en": [
                "test.linkLocale.moved": "[Policy](https://first.example/)",
                "test.linkLocale.swapped": "[A](https://first.example/) and [B](https://second.example/)",
                "test.linkLocale.same": "[Docs](https://first.example/)",
            ],
            "de": [
                "test.linkLocale.moved": "Siehe die [Richtlinie](https://first.example/)",
                "test.linkLocale.swapped": "[B](https://second.example/) und [A](https://first.example/)",
                "test.linkLocale.same": "[Doku](https://first.example/)",
            ],
        ])
    }

    /// The URLs the links opened.
    private final class Opened: @unchecked Sendable {
        var urls: [URL] = []
    }

    /// A button, then the text read in German.
    private func page(_ key: LocalizedStringKey, opened: Opened) -> some View {
        VStack(alignment: .leading) {
            Button("Go") {}
            Text(key)
        }
        .environment(\.locale, Locale(identifier: "de"))
        .environment(\.openURL, OpenURLAction { url in
            opened.urls.append(url)
            return .handled
        })
    }

    @Test("A translation that puts the link in another run opens it")
    func linkInAnotherRun() {
        let opened = Opened()
        let harness = InputChainHarness(width: 40, height: 6)
        harness.frame(page("test.linkLocale.moved", opened: opened))
        harness.frame(page("test.linkLocale.moved", opened: opened))
        harness.press(KeyEvent(key: .tab))
        harness.frame(page("test.linkLocale.moved", opened: opened))
        harness.press(KeyEvent(key: .enter))
        harness.frame(page("test.linkLocale.moved", opened: opened))
        #expect(opened.urls == [Self.first])
    }

    @Test("A translation that swaps two links opens the one drawn")
    func swappedLinks() throws {
        let opened = Opened()
        let harness = InputChainHarness(width: 40, height: 6)
        harness.frame(page("test.linkLocale.swapped", opened: opened))
        let rows = harness.frame(page("test.linkLocale.swapped", opened: opened)).lines.map(\.stripped)
        let row = try #require(rows.firstIndex { $0.contains(" und ") }, "\(rows)")
        let column = try #require(rows[row].range(of: "B")).lowerBound.utf16Offset(in: rows[row])
        harness.click(column, row) { page("test.linkLocale.swapped", opened: opened) }
        #expect(opened.urls == [Self.second], "the drawn B opened \(opened.urls)")
    }

    @Test("A focused link read in another language breathes")
    func focusedLinkBreathes() throws {
        let opened = Opened()
        let harness = InputChainHarness(width: 40, height: 6)
        harness.frame(page("test.linkLocale.same", opened: opened))
        let rows = harness.frame(page("test.linkLocale.same", opened: opened)).lines.map(\.stripped)
        let row = try #require(rows.firstIndex { $0.contains("Doku") }, "\(rows)")
        harness.press(KeyEvent(key: .tab))
        let focused = harness.frame(page("test.linkLocale.same", opened: opened))
        // A breath whose frames are all one colour is none: the recoloured
        // copies were each read again from the key, and lost the colour.
        let breath = focused.animatedCells.filter { $0.offsetY == row }
        #expect(breath.contains { Set($0.frames).count > 1 }, "the link's row does not breathe: \(breath.map(\.frames))")
    }
}
