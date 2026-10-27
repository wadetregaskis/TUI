//  🖥️ TUI — A Terminal UI framework for Swift
//  ZoomScalingTests.swift
//
//  A navigation zoom scales and moves the pictures of the screen it reveals or
//  folds away with its rectangle, rather than cutting them with it: each drawn
//  again by a second placement of its image at the rectangle's scale.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUINavigation

@MainActor
@Suite("Navigation zoom scales pictures")
struct ZoomScalingTests {
    /// A picture's signature, for the store: anything that compares.
    private struct Signature: ImageStoreSignature {
        let label: String
        var storeBucket: String { label }
    }

    /// A store holding one picture of `columns` × `rows` cells, and its rows.
    private func picture(columns: Int, rows: Int) -> (TerminalImageStore, [String]) {
        let store = TerminalImageStore()
        let cells = store.placeholderRows(
            token: "photo", signature: Signature(label: "photo"), columns: columns, rows: rows,
            pixels: { ([UInt8](repeating: 0x80, count: 16 * 16 * 4), .rgba, 16, 16) }) ?? []
        _ = store.takePending()
        return (store, cells)
    }

    @Test("A picture is lifted out of the screen, found once with its whole box, its cells blanked")
    func lifts() throws {
        let (store, cells) = picture(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: ["Title", ""] + cells.map { "    " + $0 })
        let scaling = ZoomScaling(whole: CellRect(x: 0, y: 0, width: 20, height: 10), images: store)
        let found = scaling.liftingPictures(out: &screen)
        let picture = try #require(found.first)
        #expect(found.count == 1)
        #expect((picture.x, picture.y, picture.columns, picture.rows) == (4, 2, 8, 4))
        #expect(screen.lines.allSatisfy { !$0.unicodeScalars.contains(.terminalImagePlaceholder) })
        #expect(screen.lines[0].stripped == "Title")
    }

    @Test("Drawn into a rectangle half the stack's size, a picture is half its size and moved with it")
    func scalesAndMoves() throws {
        let (store, cells) = picture(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: ["", ""] + cells.map { "    " + $0 })
        let scaling = ZoomScaling(whole: CellRect(x: 0, y: 0, width: 20, height: 10), images: store)
        let picture = try #require(scaling.liftingPictures(out: &screen).first)
        let rect = CellRect(x: 5, y: 2, width: 10, height: 5)
        let drawn = try #require(scaling.drawing(picture, into: rect, within: rect))
        #expect((drawn.x, drawn.y) == (7, 3), "its corner where the map takes it")
        #expect(drawn.cells.width == 4 && drawn.cells.height == 2, "half its box")
        #expect(drawn.cells.lines[0].contains("58;5;2"), "drawn by the image's second placement")
        #expect(store.takePending().contains("p=2,c=4,r=2"), "placed at the scaled size")
        _ = scaling.drawing(picture, into: rect, within: rect)
        #expect(store.takePending().isEmpty, "the same size is not placed again")
    }

    @Test("What falls outside the visible part is cut")
    func cutToVisible() throws {
        let (store, cells) = picture(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: cells)
        let scaling = ZoomScaling(whole: CellRect(x: 0, y: 0, width: 8, height: 4), images: store)
        let picture = try #require(scaling.liftingPictures(out: &screen).first)
        let whole = CellRect(x: 0, y: 0, width: 8, height: 4)
        let drawn = try #require(scaling.drawing(picture, into: whole, within: CellRect(x: 2, y: 1, width: 3, height: 2)))
        #expect((drawn.x, drawn.y, drawn.cells.width, drawn.cells.height) == (2, 1, 3, 2))
    }
}
