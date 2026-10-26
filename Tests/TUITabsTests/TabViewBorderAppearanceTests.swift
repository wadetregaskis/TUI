//  🖥️ TUI — A Terminal UI framework for Swift
//  TabViewBorderAppearanceTests.swift
//
//  A bordered TabView's folder tabs and content box are drawn in the border
//  of the appearance in force, as a box's are (owner, 2026-10-24: "TabView
//  borders should reflect the active border style (they're currently always
//  in the 'Line' style)").
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUITabs
@testable import TUITestSupport

@MainActor
@Suite("A bordered TabView is drawn in the appearance's border")
struct TabViewBorderAppearanceTests {
    /// Two folder tabs, the first selected, over a one-line box, stripped.
    private func lines(_ appearance: Appearance) -> [String] {
        let view = TabView(selection: .constant(0)) {
            Tab("One", value: 0) { Text("body") }
            Tab("Two", value: 1) { Text("body") }
        }
        .tabViewStyle(.bordered)
        .tabViewHeaderAlignment(.leading)
        .appearance(appearance)
        return renderToBuffer(view, context: makeRenderContext(width: 16, height: 8)).lines.map(\.stripped)
    }

    /// The rounded border's drawing, the default and what every TabView drew.
    private static let rounded = [
        " ╭─────╮─────╮ ",
        " │ One │ Two │ ",
        "╭╯     ╰─────┴╮",
        "│             │",
        "│    body     │",
        "│             │",
        "╰─────────────╯",
    ]

    @Test(
        "Each border of lines draws the tabs and the box in its own glyphs",
        arguments: [
            (Appearance.rounded, "╭╮╰╯─│┴"),
            (.line, "┌┐└┘─│┴"),
            (.heavy, "┏┓┗┛━┃┻"),
            (.doubleLine, "╔╗╚╝═║╩"),
        ] as [(Appearance, String)])
    func linesFamilies(appearance: Appearance, glyphs: String) {
        // The rounded drawing, glyph for glyph in this border's own.
        let spelled = Dictionary(uniqueKeysWithValues: zip("╭╮╰╯─│┴", glyphs))
        let expected = Self.rounded.map { String($0.map { spelled[$0] ?? $0 }) }
        #expect(lines(appearance) == expected, "\(lines(appearance))")
    }

    @Test("Under the blank appearance the box has no glyphs, under Braille it is dots, under Block blocks")
    func otherFamilies() {
        let lineGlyphs = "─│╭╮╰╯┬┴"
        let blank = lines(.blank)
        #expect(!blank.joined().contains { lineGlyphs.contains($0) || $0 == "█" }, "\(blank)")
        let dots = lines(.braille)
        #expect(!dots.joined().contains { lineGlyphs.contains($0) }, "\(dots)")
        #expect(dots.allSatisfy { $0.contains { ("\u{2800}"..."\u{28FF}").contains($0) } }, "\(dots)")
        let block = lines(.block)
        #expect(block.last == String(repeating: "█", count: 15), "\(block)")
        #expect(block[1] == " █ One █ Two █ ", "\(block)")
    }
}
