//  🖥️ TUI — A Terminal UI framework for Swift
//  DerivedImageTests.swift
//
//  Copies of a picture the terminal draws, changed for a translucent layer
//  over it: transmitted once, re-pointed at by the cells under the layer
//  (`Terminal graphics protocols.md` §14).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Derived copies of a terminal picture")
struct DerivedImageTests {
    private func signature(_ label: String) -> TerminalImageSignature {
        TerminalImageSignature(
            source: .file(label), rawWidth: 8, rawHeight: 8, pixelWidth: 8, pixelHeight: 8,
            colorMode: .trueColor, toneCurve: nil, edgeContrast: 0, dithering: .none,
            monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0),
            terminalColors: .unknown)
    }

    /// A store holding one 4 × 2 picture, its pending escapes taken.
    private func storeWithPicture() -> (TerminalImageStore, [String]) {
        let store = TerminalImageStore()
        let rows = store.placeholderRows(
            token: "a", signature: signature("one"), columns: 4, rows: 2,
            pixels: { ([UInt8](repeating: 0x80, count: 8 * 8 * 4), .rgba, 8, 8) })
        _ = store.takePending()
        return (store, rows ?? [])
    }

    /// Whether `escapes` name image `id` — exactly, not as the start of a longer id.
    private func names(_ escapes: String, _ id: KittyGraphics.ImageID) -> Bool {
        [",", ";", "\u{1B}"].contains { escapes.contains("i=\(id)\($0)") }
    }

    /// The image cells of `line`, read back.
    private func pictureCells(_ line: String) -> [KittyGraphics.PlaceholderCell?] {
        FrameBuffer.cells(in: line, through: line.strippedLength, defaultForeground: .white, surface: .black).map { cell in
            guard let cell, let ink = cell.foreground?.rgbComponents else { return nil }
            return KittyGraphics.placeholderCell(cell.character, foreground: ink)
        }
    }

    @Test("A placeholder cell reads back as the image, row and column it names")
    func placeholderRoundTrip() {
        let rows = KittyGraphics.placeholderRows(id: 0x0A_0B0C, columns: 3, rows: 2)
        for (row, line) in rows.enumerated() {
            #expect(
                pictureCells(line) == (0..<3).map { KittyGraphics.PlaceholderCell(id: 0x0A_0B0C, row: row, column: $0) })
        }
        let cell = KittyGraphics.PlaceholderCell(id: 7, row: 1, column: 2)
        #expect(pictureCells(cell.spelled) == [cell])
        #expect(KittyGraphics.placeholderCell("a", foreground: (0, 0, 7)) == nil)
    }

    @Test("A copy has an id of its own, at the same cell, and is made once")
    func copyMadeOnce() throws {
        let (store, rows) = storeWithPicture()
        let picture = try #require(pictureCells(rows[1])[2])
        let transform = ImageTransform(blurs: true, toward: (20, 30, 40), fraction: 0.5)
        let copy = try #require(store.derived(picture, by: transform))
        #expect(copy.id != picture.id)
        #expect(copy.row == 1 && copy.column == 2)
        let pending = store.takePending()
        #expect(names(pending, copy.id), "the copy is transmitted")
        #expect(pending.contains("a=p,U=1"), "and placed in the picture's box")
        #expect(store.derived(picture, by: transform) == copy)
        #expect(store.takePending().isEmpty, "asked again, it costs nothing")
        #expect(store.average(of: picture, by: transform) != nil)
    }

    @Test("A picture keeps a few copies, and the oldest goes")
    func copiesAreCapped() throws {
        let (store, rows) = storeWithPicture()
        let picture = try #require(pictureCells(rows[0])[0])
        let first = try #require(store.derived(picture, by: ImageTransform(blurs: false, toward: (0, 0, 0), fraction: 1 / 64)))
        for step in 2...DerivedImages.limit {
            _ = store.derived(picture, by: ImageTransform(blurs: false, toward: (0, 0, 0), fraction: Double(step) / 64))
        }
        _ = store.takePending()
        _ = store.derived(picture, by: ImageTransform(blurs: true, toward: (0, 0, 0), fraction: 0))
        #expect(store.takePending().contains("a=d,d=I,q=2,i=\(first.id)\u{1B}"), "the oldest copy is deleted")
    }

    @Test("Letting a picture go deletes its copies")
    func releaseDeletesCopies() throws {
        let (store, rows) = storeWithPicture()
        let picture = try #require(pictureCells(rows[0])[0])
        let copy = try #require(store.derived(picture, by: ImageTransform(blurs: true, toward: (0, 0, 0), fraction: 0)))
        _ = store.takePending()
        store.release(token: "a")
        let pending = store.takePending()
        #expect(pending.contains("a=d,d=I,q=2,i=\(picture.id)\u{1B}") && pending.contains("a=d,d=I,q=2,i=\(copy.id)\u{1B}"))
    }

    @Test("Translucent paint composited over a picture re-points the cells it covers")
    func compositeRePoints() throws {
        let (store, rows) = storeWithPicture()
        let base = FrameBuffer(lines: rows)
        let context = makeRenderContext(width: 2, height: 1)
        let pane = renderToBuffer(Color.rgb(0, 0, 255).opacity(0.5).frame(width: 2, height: 1), context: context)
        let composite = base.compositedCarryingClaimsOverNothing(
            with: pane, at: (x: 1, y: 0),
            in: CompositeEnvironment(palette: context.environment.palette, linearLight: false, images: store))
        let cells = pictureCells(composite.lines[0])
        let original = try #require(cells[0])
        let covered = try #require(cells[1])
        #expect(covered.id != original.id, "a covered cell draws the copy")
        #expect(covered.row == 0 && covered.column == 1, "at its own cell of it")
        #expect(cells[3]?.id == original.id, "an uncovered cell draws the picture")
        #expect(names(store.takePending(), covered.id), "the copy reaches the terminal")
    }

    /// The screen root's route: a layer lifted off the page — an `.offset` panel, a
    /// popover — is spent over the finished page (`compositingOverlays`), not at a
    /// compositor inside the tree, and found the picture there just the same.
    @Test("A floating layer spent over a picture at the root re-points the cells it covers")
    func rootCompositeRePoints() throws {
        let (store, rows) = storeWithPicture()
        let page = FrameBuffer(lines: rows)
        let context = makeRenderContext(width: 2, height: 1)
        let pane = renderToBuffer(Color.rgb(0, 0, 255).opacity(0.5).frame(width: 2, height: 1), context: context)
        let composite = page.compositedResolvingOpacity(
            with: pane, at: (x: 1, y: 0), palette: context.environment.palette, images: store)
        let cells = pictureCells(composite.lines[0])
        let original = try #require(cells[0])
        #expect(cells[1].map { $0.id != original.id } == true, "a covered cell draws the copy")
        #expect(cells[3]?.id == original.id, "an uncovered cell draws the picture")
    }

    /// A material is a painter: its translucent field is under the content, and its
    /// alpha is the painter's claim, not the cell's own. Read from the cell, a thin
    /// material mixed the copy all the way to its tint — a solid panel over a photo.
    @Test("A painter's field mixes the copy by the painter's alpha")
    func painterMixesByItsAlpha() throws {
        let (store, rows) = storeWithPicture()
        let behind = try #require(
            FrameBuffer.cells(in: rows[0], through: 4, defaultForeground: .white, surface: .black)[1])
        let picture = try #require(pictureCells(rows[0])[1])
        var alpha = FrameBuffer.CellAlpha(layer: 1)
        let tint = Color.rgb(200, 190, 170)
        alpha.painterFields = [FrameBuffer.PainterField(colour: tint, layer: 1, field: 0.5)]
        alpha.frosts = true
        let blank = FrameBuffer.RowCell(character: " ", style: SGRState())
        let drawn = try #require(FrameBuffer.overPicture(behind, under: blank, alpha: alpha, images: store))
        let ink = try #require(drawn.foreground?.rgbComponents)
        let copy = try #require(KittyGraphics.placeholderCell(drawn.character, foreground: ink))
        #expect(copy.id != picture.id && copy.row == picture.row && copy.column == picture.column)
        let halfWay = ImageTransform(blurs: true, toward: (200, 190, 170), fraction: 0.5)
        #expect(store.average(of: picture, by: halfWay) != nil, "the copy made is the one mixed half-way")
        #expect(store.average(of: picture, by: ImageTransform(blurs: true, toward: (200, 190, 170), fraction: 1)) == nil)
    }

    /// A picture inside a fade: its rows were left at full strength, since the
    /// resolution read each cell's id as a colour. Each cell now draws a copy mixed
    /// toward what is behind it by the fade.
    @Test("A faded picture draws a copy mixed toward the ground")
    func fadedPictureDrawsCopy() throws {
        let (store, rows) = storeWithPicture()
        var page = FrameBuffer(lines: rows)
        page.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 4, height: 2, opacity: 0.5)]
        let context = makeRenderContext(width: 4, height: 2)
        let ground = Color.rgb(10, 20, 30)
        let faded = page.resolvingOpacity(surface: ground, palette: context.environment.palette, images: store)
        let original = try #require(pictureCells(rows[1])[3])
        let drawn = try #require(pictureCells(faded.lines[1])[3])
        #expect(drawn.id != original.id && drawn.row == 1 && drawn.column == 3, "the copy, at the same cell")
        let halfWay = ImageTransform(blurs: false, toward: (10, 20, 30), fraction: 0.5)
        #expect(store.average(of: original, by: halfWay) != nil, "mixed half-way toward the ground")
    }

    @Test("Unfaded, or with no store to copy from, a picture is drawn as it is")
    func unfadedPictureUnchanged() throws {
        let (store, rows) = storeWithPicture()
        var page = FrameBuffer(lines: rows)
        page.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 4, height: 2, opacity: 0.5)]
        let palette = makeRenderContext(width: 4, height: 2).environment.palette
        let withoutStore = page.resolvingOpacity(surface: .rgb(10, 20, 30), palette: palette, images: nil)
        #expect(pictureCells(withoutStore.lines[0]) == pictureCells(rows[0]))
        page.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 4, height: 2, opacity: 1)]
        let unfaded = page.resolvingOpacity(surface: .rgb(10, 20, 30), palette: palette, images: store)
        #expect(pictureCells(unfaded.lines[0]) == pictureCells(rows[0]))
    }

    /// A fade keeps the picture's detail: its copy is made from the picture's own
    /// pixels at their own size, where a frost's is the small copy, blurred.
    @Test("An unblurred copy is sent at the picture's size; a frosted one small")
    func copyResolution() throws {
        let store = TerminalImageStore()
        let rows = try #require(
            store.placeholderRows(
                token: "a", signature: signature("big"), columns: 4, rows: 2,
                pixels: { ([UInt8](repeating: 0x80, count: 16 * 16 * 4), .rgba, 16, 16) }))
        _ = store.takePending()
        let picture = try #require(pictureCells(rows[0])[0])
        _ = store.derived(picture, by: ImageTransform(blurs: false, toward: (0, 0, 0), fraction: 0.5))
        #expect(store.takePending().contains("s=16,v=16"), "the picture's own 16 × 16")
        _ = store.derived(picture, by: ImageTransform(blurs: true, toward: (0, 0, 0), fraction: 0.5))
        #expect(store.takePending().contains("s=8,v=8"), "the small copy: 4 cells × 2 across, 2 × 4 down")
    }
}
