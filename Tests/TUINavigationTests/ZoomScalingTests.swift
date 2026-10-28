//  🖥️ TUI — A Terminal UI framework for Swift
//  ZoomScalingTests.swift
//
//  A navigation zoom scales and moves the pictures of the screen it reveals or
//  folds away from the source's frame to their own, rather than cutting them
//  with its rectangle: each drawn again by a second placement of its image at
//  the scale it is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUINavigation
@testable import TUITestSupport
@testable import TUIView

/// A picture's signature, for the store: anything that compares.
private struct Signature: ImageStoreSignature {
    let label: String
    var storeBucket: String { label }
}

/// A picture the terminal draws, `columns` × `rows` cells of the image
/// `token` names — what an `Image` draws with terminal graphics.
private struct Picture: View, Renderable {
    let token: String
    let columns: Int
    let rows: Int

    var body: Never { fatalError("Picture renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let cells = context.environment.terminalImageStore?.placeholderRows(
            token: token, signature: Signature(label: token), columns: columns, rows: rows,
            pixels: { ([UInt8](repeating: 0x80, count: 16 * 16 * 4), .rgba, 16, 16) })
        return FrameBuffer(lines: cells ?? [])
    }
}

/// A stack 40×12 whose root has a thumbnail 4×2 at (10, 3) among dots — the
/// zoom's source — and whose pushed screen holds a photo 20×8 in its
/// bottom-trailing corner, at (20, 4) under the screen's two-row bar.
private struct PhotoZoom: View {
    let path: Binding<NavigationPath>
    @Namespace private var space

    var body: some View {
        NavigationStack(path: path) {
            VStack(alignment: .leading, spacing: 0) {
                GlyphFill(".").frame(width: 40, height: 3)
                HStack(spacing: 0) {
                    GlyphFill(".").frame(width: 10, height: 2)
                    Picture(token: "thumbnail", columns: 4, rows: 2).frame(width: 4, height: 2)
                        .matchedTransitionSource(id: 1, in: space)
                    GlyphFill(".").frame(width: 26, height: 2)
                }
                GlyphFill(".").frame(width: 40, height: 7)
            }
            .navigationDestination(for: Int.self) { _ in
                Picture(token: "photo", columns: 20, rows: 8).frame(width: 20, height: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .navigationTransition(.zoom(sourceID: 1, in: space))
            }
        }
    }
}

/// The smallest rectangle holding every picture cell on `screen`, and
/// whether every cell inside it is one.
private func pictureRect(in screen: FrameBuffer) -> (rect: CellRect, solid: Bool)? {
    let rows = screen.lines.map { line in
        Array(line.stripped).map { $0.unicodeScalars.first == .terminalImagePlaceholder }
    }
    let cells = rows.enumerated().flatMap { y, row in row.indices.filter { row[$0] }.map { (x: $0, y: y) } }
    guard let minX = cells.map(\.x).min(), let maxX = cells.map(\.x).max(),
        let minY = cells.map(\.y).min(), let maxY = cells.map(\.y).max()
    else { return nil }
    let solid = (minY...maxY).allSatisfy { y in (minX...maxX).allSatisfy { x in rows[y].indices.contains(x) && rows[y][x] } }
    return (CellRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1), solid)
}

@MainActor
@Suite("Navigation zoom scales pictures")
struct ZoomScalingTests {
    /// A store holding one picture of `columns` × `rows` cells for each of
    /// `tokens`, and each one's rows.
    private func pictures(_ tokens: [String] = ["photo"], columns: Int, rows: Int) -> (TerminalImageStore, [[String]]) {
        let store = TerminalImageStore()
        let cells = tokens.map { token in
            store.placeholderRows(
                token: token, signature: Signature(label: token), columns: columns, rows: rows,
                pixels: { ([UInt8](repeating: 0x80, count: 16 * 16 * 4), .rgba, 16, 16) }) ?? []
        }
        _ = store.takePending()
        return (store, cells)
    }

    @Test("A picture is lifted out of the screen, found once with its whole box, its cells blanked")
    func lifts() throws {
        let (store, cells) = pictures(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: ["Title", ""] + cells[0].map { "    " + $0 })
        let scaling = ZoomScaling(source: CellRect(x: 0, y: 0, width: 4, height: 2), remaining: 1, images: store)
        let found = scaling.liftingPictures(out: &screen)
        let picture = try #require(found.first)
        #expect(found.count == 1)
        #expect((picture.x, picture.y, picture.columns, picture.rows) == (4, 2, 8, 4))
        #expect(screen.lines.allSatisfy { !$0.unicodeScalars.contains(.terminalImagePlaceholder) })
        #expect(screen.lines[0].stripped == "Title")
    }

    @Test("A picture is drawn on the source's frame at the far end, and in its own place at the near one")
    func endsOnTheSourceAndInPlace() throws {
        let (store, cells) = pictures(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: ["", ""] + cells[0].map { "    " + $0 })
        let source = CellRect(x: 20, y: 8, width: 4, height: 2)
        let visible = CellRect(x: 0, y: 0, width: 40, height: 12)
        let picture = try #require(
            ZoomScaling(source: source, remaining: 1, images: store).liftingPictures(out: &screen).first)
        let far = try #require(ZoomScaling(source: source, remaining: 1, images: store)
            .drawings(of: [picture], within: visible).first)
        #expect((far.x, far.y, far.cells.width, far.cells.height) == (20, 8, 4, 2), "exactly the source's frame")
        let near = try #require(ZoomScaling(source: source, remaining: 0, images: store)
            .drawings(of: [picture], within: visible).first)
        #expect((near.x, near.y, near.cells.width, near.cells.height) == (4, 2, 8, 4), "its own box")
    }

    @Test("Halfway, a picture is moved and scaled halfway from the source's frame to its own")
    func scalesAndMoves() throws {
        let (store, cells) = pictures(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: ["", ""] + cells[0].map { "    " + $0 })
        let scaling = ZoomScaling(source: CellRect(x: 0, y: 0, width: 4, height: 2), remaining: 0.5, images: store)
        let picture = try #require(scaling.liftingPictures(out: &screen).first)
        let visible = CellRect(x: 0, y: 0, width: 20, height: 10)
        // Each edge halfway: 0 → 4, 0 → 2, 4 → 12, 2 → 6.
        let drawn = try #require(scaling.drawings(of: [picture], within: visible).first)
        #expect((drawn.x, drawn.y) == (2, 1), "its corner halfway")
        #expect(drawn.cells.width == 6 && drawn.cells.height == 3, "its size halfway")
        #expect(drawn.cells.lines[0].contains("58;5;2"), "drawn by the image's second placement")
        #expect(store.takePending().contains("p=2,c=6,r=3"), "placed at the scaled size")
        _ = scaling.drawings(of: [picture], within: visible)
        #expect(store.takePending().isEmpty, "the same size is not placed again")
    }

    @Test("Pictures side by side share the source's frame as they share the screen")
    func picturesMoveAsOne() throws {
        let (store, cells) = pictures(["left", "right"], columns: 4, rows: 2)
        var screen = FrameBuffer(lines: zip(cells[0], cells[1]).map { $0 + $1 })
        let scaling = ZoomScaling(source: CellRect(x: 10, y: 5, width: 4, height: 2), remaining: 1, images: store)
        let found = scaling.liftingPictures(out: &screen)
        #expect(found.count == 2)
        let drawn = scaling.drawings(of: found, within: CellRect(x: 0, y: 0, width: 40, height: 12))
        #expect(drawn.map { [$0.x, $0.y, $0.cells.width, $0.cells.height] } == [[10, 5, 2, 2], [12, 5, 2, 2]])
    }

    @Test("What falls outside the visible part is cut")
    func cutToVisible() throws {
        let (store, cells) = pictures(columns: 8, rows: 4)
        var screen = FrameBuffer(lines: cells[0])
        let scaling = ZoomScaling(source: CellRect(x: 0, y: 0, width: 8, height: 4), remaining: 0, images: store)
        let picture = try #require(scaling.liftingPictures(out: &screen).first)
        let drawn = try #require(
            scaling.drawings(of: [picture], within: CellRect(x: 2, y: 1, width: 3, height: 2)).first)
        #expect((drawn.x, drawn.y, drawn.cells.width, drawn.cells.height) == (2, 1, 3, 2))
    }

    @Test("A photo zoomed up from its thumbnail starts exactly on it, and folds back exactly onto it")
    func photoLandsOnItsThumbnail() throws {
        let harness = InputChainHarness(width: 40, height: 12) { $0.canAnimate = true }
        var path = NavigationPath()
        let view = { PhotoZoom(path: Binding(get: { path }, set: { path = $0 })) }
        let thumbnail = CellRect(x: 10, y: 3, width: 4, height: 2)
        harness.frame(view())
        path.append(1)
        harness.transaction = Transaction(animation: .linear(duration: 1))
        let start = try #require(pictureRect(in: harness.frame(view())))
        #expect(start.rect == thumbnail, "the photo starts on the thumbnail, at its size")
        #expect(start.solid, "and covers it: nothing of the screen is drawn across it")
        harness.transaction = Transaction()
        // Halfway, each of the photo's edges is halfway from the thumbnail's
        // to its own — 10 → 20, 3 → 4, 14 → 40, 5 → 12 — inside the
        // rectangle, (5, 2) 22×6.
        harness.now = 500_000_000
        #expect(pictureRect(in: harness.frame(view()))?.rect == CellRect(x: 15, y: 3, width: 12, height: 5))
        harness.now = 1_000_000_000
        #expect(pictureRect(in: harness.frame(view()))?.rect == CellRect(x: 20, y: 4, width: 20, height: 8))
        path.removeLast()
        harness.transaction = Transaction(animation: .linear(duration: 1))
        harness.frame(view())
        harness.transaction = Transaction()
        harness.now = 1_999_000_000
        let end = try #require(pictureRect(in: harness.frame(view())))
        #expect(end.rect == thumbnail, "the photo lands on the thumbnail, at its size")
        #expect(end.solid, "and covers it: the screen's bar is not drawn across it")
        harness.now = 2_000_000_000
        #expect(pictureRect(in: harness.frame(view()))?.rect == thumbnail, "where the thumbnail takes over")
    }
}
