//  🖥️ TUI — A Terminal UI framework for Swift
//  ClassicPlacementCropTests.swift
//
//  A picture on a host that ignores a placement's source rectangle: what is left
//  of it after a cover or a clip, as images of just those pixels, each a rectangle
//  of whole cells.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private struct Signature: ImageStoreSignature {
    var name: String
    var storeBucket: String { name }
}

/// A picture of 40 x 20 cells at 5 x 5 pixels a cell, each pixel saying where it
/// is: red its x, green its y.
@MainActor
private func picture(in store: TerminalImageStore, name: String = "a") -> (rows: [String], id: KittyGraphics.ImageID) {
    let rows =
        store.placeholderRows(token: name, signature: Signature(name: name), columns: 40, rows: 20) {
            var bytes = [UInt8]()
            for y in 0..<100 {
                for x in 0..<200 { bytes += [UInt8(x), UInt8(y), 7] }
            }
            return (bytes, .rgb, 200, 100)
        } ?? []
    _ = store.takePending()
    return (rows, KittyGraphics.extractingPlaceholders(rows.first ?? "").runs.first?.image ?? 0)
}

/// One `a=p` a frame wrote: where, and which image.
private struct Placed {
    var column: Int
    var row: Int
    var columns: Int
    var rows: Int
    var image: KittyGraphics.ImageID
    var cells: [[Int]] { (row..<(row + rows)).map { row in (column..<(column + columns)).map { $0 + row * 1000 } } }
}

/// The value of `key` in a graphics command's keys.
private func value(_ key: String, in keys: Substring) -> Int? {
    keys.split(separator: ",").first { $0.hasPrefix("\(key)=") }.flatMap { Int($0.dropFirst(key.count + 1)) }
}

/// The placements in what a frame wrote: each after the cursor move to its first
/// cell, which is 1-based, as the frame's rows and columns are 0-based here.
private func placements(in output: String) -> [Placed] {
    var found: [Placed] = []
    var cursor = (row: 0, column: 0)
    for piece in output.components(separatedBy: "\u{1B}") where !piece.isEmpty {
        if piece.hasPrefix("["), piece.hasSuffix("H") {
            let numbers = piece.dropFirst().dropLast().split(separator: ";").compactMap { Int($0) }
            if numbers.count == 2 { cursor = (numbers[0] - 1, numbers[1] - 1) }
        } else if piece.hasPrefix("_Ga=p") {
            let keys = piece.dropFirst(2)
            found.append(
                Placed(
                    column: cursor.column, row: cursor.row, columns: value("c", in: keys) ?? 0,
                    rows: value("r", in: keys) ?? 0, image: UInt32(value("i", in: keys) ?? 0)))
        }
    }
    return found
}

/// The images in `escapes`, by id: their size, and their pixels as RGBA.
private func transmissions(in escapes: String) -> [KittyGraphics.ImageID: (width: Int, height: Int, bytes: [UInt8])] {
    var images: [KittyGraphics.ImageID: (width: Int, height: Int, bytes: [UInt8])] = [:]
    var base64 = ""
    var head: (id: UInt32, width: Int, height: Int)?
    for piece in escapes.components(separatedBy: "\u{1B}_G") where !piece.isEmpty {
        let parts = piece.prefix { $0 != "\u{1B}" }.split(separator: ";", maxSplits: 1)
        guard let keys = parts.first else { continue }
        if keys.hasPrefix("a=t") {
            head = (UInt32(value("i", in: keys) ?? 0), value("s", in: keys) ?? 0, value("v", in: keys) ?? 0)
            base64 = ""
        }
        if parts.count > 1 { base64 += parts[1] }
        if let head, value("m", in: keys) ?? 0 == 0 {
            images[head.id] = (head.width, head.height, [UInt8](Data(base64Encoded: base64) ?? Data()))
        }
    }
    return images
}

@MainActor
@Suite("Classic placements: a host that ignores the source rectangle")
struct ClassicPlacementCropTests {

    /// What a frame of `lines` draws on a screen `width` columns wide: through the
    /// writer, the store and the layer, as `prepareClassicPictures` runs them.
    private func frame(
        _ lines: [String], width: Int = 60, store: TerminalImageStore, layer: PicturePlacementLayer,
        writer: FrameDiffWriter
    ) -> (placed: [Placed], sent: String) {
        _ = writer.buildReusingOutputLines(
            buffer: FrameBuffer(lines: lines), terminalWidth: width, terminalHeight: lines.count, bgCode: "",
            reset: "\u{1B}[0m")
        let rows = writer.imagePlaceholderRows.map { $0.compactMap { store.placementRun(for: $0) } }
        layer.prepare(rows: rows, drawing: { store.croppedRun($0) })
        store.endCroppedFrame()
        let sent = store.takePending()
        let terminal = MockTerminal()
        layer.place(on: terminal, startRow: 1)
        return (placements(in: terminal.allOutput), sent)
    }

    /// Checks `placed`: every cell of `visible` in exactly one placement and no
    /// other cell in any, each an image of just its own cells' pixels.
    ///
    /// - Parameter cellOf: The picture's cell a screen cell draws.
    private func check(
        _ placed: [Placed], sent: String, visible: Set<Int>, wholeImage: KittyGraphics.ImageID? = nil,
        cellOf: (_ row: Int, _ column: Int) -> (row: Int, column: Int) = { ($0, $1) }
    ) {
        let cells = placed.flatMap { $0.cells.flatMap(\.self) }
        #expect(cells.count == Set(cells).count, "no placement overlaps another")
        #expect(Set(cells) == visible, "they cover exactly the cells that show")
        let images = transmissions(in: sent)
        for placement in placed where placement.image != wholeImage {
            guard let image = images[placement.image] else {
                Issue.record("placement of an image never sent: \(placement.image)")
                continue
            }
            #expect(image.width == placement.columns * 5 && image.height == placement.rows * 5)
            let first = cellOf(placement.row, placement.column)
            #expect(image.bytes.count == image.width * image.height * 4)
            // Its corners: the pixels of those cells, whatever lies between.
            #expect(image.bytes[0] == UInt8(first.column * 5) && image.bytes[1] == UInt8(first.row * 5))
            let last = image.bytes.count - 4
            #expect(image.bytes[last] == UInt8((first.column + placement.columns) * 5 - 1))
            #expect(image.bytes[last + 1] == UInt8((first.row + placement.rows) * 5 - 1))
        }
    }

    private func fixture() -> (TerminalImageStore, PicturePlacementLayer, FrameDiffWriter) {
        (TerminalImageStore(), PicturePlacementLayer(z: PicturePlacementLayer.overCells), FrameDiffWriter(program: .warp))
    }

    /// Every cell in `columns` x `rows` but those of the `holes`, as `Placed.cells`
    /// numbers them.
    private func cells(
        columns: Range<Int> = 0..<40, rows: Range<Int> = 0..<20,
        less holes: [(column: Int, row: Int, columns: Int, rows: Int)] = []
    ) -> Set<Int> {
        var out = Set<Int>()
        for row in rows {
            for column in columns
            where !holes.contains(where: {
                ($0.column..<($0.column + $0.columns)).contains(column) && ($0.row..<($0.row + $0.rows)).contains(row)
            }) {
                out.insert(column + row * 1000)
            }
        }
        return out
    }

    private func cover(columns: Int, rows: Int) -> FrameBuffer {
        FrameBuffer(lines: [String](repeating: String(repeating: "x", count: columns), count: rows))
    }

    @Test("A whole picture is placed as itself, and costs nothing more")
    func whole() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, id) = picture(in: store)
            let frame = frame(rows, store: store, layer: layer, writer: writer)
            #expect(frame.sent.isEmpty)
            #expect(frame.placed.map(\.image) == [id])
            check(frame.placed, sent: frame.sent, visible: cells(), wholeImage: id)
        }
    }

    @Test("A view in the middle leaves four rectangles, of just their pixels")
    func middle() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, _) = picture(in: store)
            let lines = FrameBuffer(lines: rows).composited(with: cover(columns: 10, rows: 6), at: (15, 7)).lines
            let frame = frame(lines, store: store, layer: layer, writer: writer)
            #expect(frame.placed.count == 4)
            check(frame.placed, sent: frame.sent, visible: cells(less: [(15, 7, 10, 6)]))
        }
    }

    @Test("A view over one corner leaves two rectangles", arguments: [(0, 0), (30, 0), (0, 14), (30, 14)])
    func corner(at: (x: Int, y: Int)) {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, _) = picture(in: store)
            let lines = FrameBuffer(lines: rows).composited(with: cover(columns: 10, rows: 6), at: at).lines
            let frame = frame(lines, store: store, layer: layer, writer: writer)
            #expect(frame.placed.count == 2)
            check(frame.placed, sent: frame.sent, visible: cells(less: [(at.x, at.y, 10, 6)]))
        }
    }

    @Test("Two views leave what the two leave, with no overlap")
    func twoViews() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, _) = picture(in: store)
            let lines = FrameBuffer(lines: rows)
                .composited(with: cover(columns: 10, rows: 6), at: (2, 2))
                .composited(with: cover(columns: 8, rows: 6), at: (20, 5)).lines
            let frame = frame(lines, store: store, layer: layer, writer: writer)
            check(frame.placed, sent: frame.sent, visible: cells(less: [(2, 2, 10, 6), (20, 5, 8, 6)]))
        }
    }

    @Test("A scroll clip's rows are one rectangle, and the next scroll position another image")
    func scrollClip() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, _) = picture(in: store)
            var frame = frame(Array(rows[3..<13]), store: store, layer: layer, writer: writer)
            #expect(frame.placed.count == 1)
            check(frame.placed, sent: frame.sent, visible: cells(rows: 0..<10)) { ($0 + 3, $1) }
            let first = frame.placed[0].image

            frame = self.frame(Array(rows[4..<14]), store: store, layer: layer, writer: writer)
            #expect(frame.placed.count == 1)
            #expect(frame.placed[0].image != first)
            check(frame.placed, sent: frame.sent, visible: cells(rows: 0..<10)) { ($0 + 4, $1) }
        }
    }

    @Test("A clip at the screen's right edge is a rectangle of the cells left")
    func rightEdge() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, _) = picture(in: store)
            let frame = frame(Array(rows[0..<5]), width: 25, store: store, layer: layer, writer: writer)
            check(frame.placed, sent: frame.sent, visible: cells(columns: 0..<25, rows: 0..<5))
        }
    }

    @Test("A crop that has not changed is neither sent nor placed again")
    func unchanged() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, _) = picture(in: store)
            let lines = FrameBuffer(lines: rows).composited(with: cover(columns: 10, rows: 6), at: (15, 7)).lines
            _ = frame(lines, store: store, layer: layer, writer: writer)
            let again = frame(lines, store: store, layer: layer, writer: writer)
            #expect(again.sent.isEmpty)
            #expect(again.placed.isEmpty)
        }
    }

    @Test("A view that closes and opens again sends no pixels the second time")
    func reopened() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, id) = picture(in: store)
            let lines = FrameBuffer(lines: rows).composited(with: cover(columns: 10, rows: 6), at: (15, 7)).lines
            let first = frame(lines, store: store, layer: layer, writer: writer)
            let closed = frame(rows, store: store, layer: layer, writer: writer)
            #expect(closed.placed.map(\.image) == [id])
            #expect(closed.sent.isEmpty)
            let open = frame(lines, store: store, layer: layer, writer: writer)
            #expect(open.sent.isEmpty)
            #expect(Set(open.placed.map(\.image)) == Set(first.placed.map(\.image)))
        }
    }

    @Test("A copy's crop is the copy's pixels: a veil over part of it stays on the crop")
    func copy() throws {
        let store = TerminalImageStore()
        let (_, id) = picture(in: store)
        let transform = ImageTransform(blurs: false, toward: (255, 255, 255), fraction: 1)
        let copy = try #require(store.derived(.init(id: id, row: 0, column: 0), by: transform))
        _ = store.takePending()
        let run = try #require(store.croppedRun(.init(column: 0, columns: 4, image: copy.id, x: 10, y: 10, width: 20, height: 20)))
        let sent = try #require(transmissions(in: store.takePending())[run.image])
        #expect((sent.width, sent.height) == (20, 20))
        #expect(sent.bytes[0] == 255 && sent.bytes[1] == 255 && sent.bytes[3] == 255)
    }

    @Test("A blurred copy, sent at its small copy's pixels, is cut from them")
    func blurredCopy() throws {
        let store = TerminalImageStore()
        let (_, id) = picture(in: store)
        let transform = ImageTransform(blurs: true, toward: (0, 0, 0), fraction: 0.5)
        let copy = try #require(store.derived(.init(id: id, row: 0, column: 0), by: transform))
        _ = store.takePending()
        let run = try #require(store.croppedRun(.init(column: 0, columns: 40, image: copy.id, x: 0, y: 8, width: 80, height: 8)))
        let sent = try #require(transmissions(in: store.takePending())[run.image])
        #expect((sent.width, sent.height) == (80, 8))
    }

    @Test("A playing frame, whose own pixels were not kept, is cut from its small copy")
    func softCut() throws {
        let store = TerminalImageStore()
        let rows = try #require(
            store.placeholderRows(
                token: "t", signature: Signature(name: "a"), columns: 40, rows: 20, keepsOwnPixels: false
            ) { ([UInt8](repeating: 9, count: 400 * 200 * 4), .rgba, 400, 200) })
        let id = try #require(KittyGraphics.extractingPlaceholders(rows[0]).runs.first?.image)
        _ = store.takePending()
        let run = try #require(store.croppedRun(.init(column: 0, columns: 20, image: id, x: 0, y: 0, width: 200, height: 200)))
        #expect((run.width, run.height) == (40, 80), "2 x 4 pixels a cell")
    }

    @Test("A picture's own pixels are kept whatever their size where a host cannot crop")
    func keptOverTheLimit() {
        let side = 1100
        let pixels = ([UInt8](repeating: 9, count: side * side * 3), KittyGraphics.PixelFormat.rgb, side, side)
        func cutWidth() -> Int? {
            var images = DerivedImages()
            images.remember(1, columns: 10, rows: 10, pixels: pixels)
            return images.cropped(1, x: 0, y: 0, width: 110, height: 110, sent: (side, side))?.width
        }
        KittyGraphics.withClassicPlacementsCrop(true) { #expect(cutWidth() == 2, "the small copy, 2 pixels a cell") }
        KittyGraphics.withClassicPlacementsCrop(false) { #expect(cutWidth() == 110) }
    }

    @Test("A rectangle that falls outside its image is no crop")
    func outside() {
        let store = TerminalImageStore()
        let (_, id) = picture(in: store)
        #expect(store.croppedRun(.init(column: 0, columns: 1, image: id, x: 195, y: 0, width: 50, height: 5)) == nil)
        #expect(store.croppedRun(.init(column: 0, columns: 1, image: id + 99, x: 0, y: 0, width: 5, height: 5)) == nil)
    }

    // MARK: - Bounded

    private func crop(_ index: Int, of id: KittyGraphics.ImageID, in store: TerminalImageStore) -> KittyGraphics.ImageID? {
        store.croppedRun(.init(column: 0, columns: 1, image: id, x: index, y: 0, width: 1, height: 1))?.image
    }

    @Test("A scroll leaves at most the limit behind, oldest first, and never one in use")
    func bounded() throws {
        let store = TerminalImageStore()
        let (_, id) = picture(in: store)
        let first = try #require(crop(0, of: id, in: store))
        store.endCroppedFrame()
        for index in 1...CroppedImages.keptLimit {
            _ = crop(index, of: id, in: store)
            store.endCroppedFrame()
        }
        #expect(store.takeDeletes().isEmpty, "the limit's worth, and one in use")
        _ = crop(CroppedImages.keptLimit + 1, of: id, in: store)
        store.endCroppedFrame()
        #expect(store.takeDeletes() == KittyGraphics.delete(id: first))
        _ = store.takePending()
        let again = try #require(crop(0, of: id, in: store))
        #expect(again != first)
        #expect(!store.takePending().isEmpty, "gone, so it is sent again")
    }

    @Test("Bytes bound them too: a crop in use stays however large")
    func boundedByBytes() {
        var crops = CroppedImages()
        let side = 2048
        for index in 0..<3 {
            let key = CroppedImages.Key(image: 1, x: index, y: 0, width: side, height: side)
            crops.add(key, id: UInt32(index + 2), width: side, height: side)
        }
        #expect(crops.endFrame().isEmpty, "all in use")
        #expect(crops.endFrame() == [2], "16 MiB each, and the limit is two of them")
    }

    @Test("A crop goes with its picture, and a shutdown takes the rest")
    func owned() throws {
        let store = TerminalImageStore()
        let (_, id) = picture(in: store)
        let made = try #require(crop(0, of: id, in: store))
        #expect(store.farewell().contains(KittyGraphics.delete(id: made)))
        store.release(token: "a")
        let deletes = store.takeDeletes()
        #expect(deletes.contains(KittyGraphics.delete(id: made)))
        #expect(deletes.contains(KittyGraphics.delete(id: id)))
        #expect(!store.farewell().contains(KittyGraphics.delete(id: made)))
    }

    @Test("A host that honours a source rectangle is placed the picture's own pixels, in one image")
    func honoured() {
        KittyGraphics.withClassicPlacements(true) {
            let (store, layer, writer) = fixture()
            let (rows, id) = picture(in: store)
            let lines = FrameBuffer(lines: rows).composited(with: cover(columns: 10, rows: 6), at: (15, 7)).lines
            _ = writer.buildReusingOutputLines(
                buffer: FrameBuffer(lines: lines), terminalWidth: 60, terminalHeight: lines.count, bgCode: "",
                reset: "\u{1B}[0m")
            layer.prepare(rows: writer.imagePlaceholderRows.map { $0.compactMap { store.placementRun(for: $0) } })
            let terminal = MockTerminal()
            layer.place(on: terminal, startRow: 1)
            #expect(placements(in: terminal.allOutput).allSatisfy { $0.image == id })
            #expect(store.takePending().isEmpty)
        }
    }
}
