//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapesModifiersTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUIkit
@testable import TUIkitApp

extension ShapesPage: ExamplePageContent {}

@MainActor
@Suite("The Shapes page's behind, over and clipping section")
struct ShapesModifiersTests {
    @Test("'Tag' is a label on a capsule and 'A card' a padded label on a rounded rectangle, as the text says")
    func tagAndCard() {
        let driver = ExamplePageDriver(ExamplePageApp<ShapesPage>(), width: 100, height: 40)
        driver.scroll(row: 5, column: 5, down: 200)
        #expect(driver.shows("page.shapes.modifiersExplain"), "\(driver.lines)")
        guard let tag = driver.position(of: "page.shapes.sample.tag"),
            let card = driver.position(of: "page.shapes.sample.card")
        else {
            Issue.record("no samples: \(driver.lines)")
            return
        }
        let lines = driver.lines
        // A capsule's one row has its round ends either side of the label, in
        // the label's own row; a card is padded a cell and a row all round, so
        // its label has rows of the shape above and below it.
        #expect(lines[tag.row].contains("page.shapes.sample.tag"))
        #expect(card.row - tag.row >= 3, "the card sits below the tag with room between: \(lines)")
        #expect(!lines[card.row - 1].allSatisfy { $0 == " " }, "a row of the card's shape above its label")
        #expect(!lines[card.row + 1].allSatisfy { $0 == " " }, "and below it")
    }
}
