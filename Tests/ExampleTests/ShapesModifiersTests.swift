//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapesModifiersTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Shapes page's behind, over and clipping section")
struct ShapesModifiersTests {
    @Test("'Tag' is a label on a capsule and 'A card' a padded label on a rounded rectangle, as the text says")
    func tagAndCard() throws {
        let app = TestApp(width: 100, height: 40) { ShapesPage() }
        app.scroll(.down, by: 200, at: CellPoint(x: 5, y: 5))
        #expect(app.screen.contains("page.shapes.modifiersExplain"), "\(app.screen)")
        let tag = try #require(app.screen.location(of: "page.shapes.sample.tag"), "no samples: \(app.screen)")
        let card = try #require(app.screen.location(of: "page.shapes.sample.card"), "no samples: \(app.screen)")
        let lines = app.screen.lines
        // A capsule's one row has its round ends either side of the label, in
        // the label's own row; a card is padded a cell and a row all round, so
        // its label has rows of the shape above and below it.
        #expect(lines[tag.y].contains("page.shapes.sample.tag"))
        #expect(card.y - tag.y >= 3, "the card sits below the tag with room between: \(app.screen)")
        #expect(!lines[card.y - 1].isEmpty, "a row of the card's shape above its label")
        #expect(!lines[card.y + 1].isEmpty, "and below it")
    }
}
