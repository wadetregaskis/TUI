//  🖥️ TUI — A Terminal UI framework for Swift
//  SixelPictureLayer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// Pictures drawn by Sixel, on a host with no Kitty graphics
/// (`Terminal graphics protocols.md` §16).
///
/// The cells of a picture reach here as ``PicturePlacementLayer``'s do, from the
/// writer, but the terminal holds nothing to place again: pixels are pixels until a
/// written cell erases them, cell by cell (measured, `sixel_probe.py`). So the writer
/// does not write those cells (``KittyGraphics/skippingPictureCells(_:)``), and this
/// keeps what each screen cell shows and draws only the cells that show something
/// else: a view opening over a picture costs no Sixel, and closing costs the
/// rectangle it uncovered. A spinner beside one costs none at all.
///
/// ## The bound on bytes
///
/// Every redraw is pixels, so a picture in motion could be megabytes a second, and a
/// terminal shows them more slowly than it takes them (iTerm2 3.7.6 took 887 KB in
/// 17 ms and showed it about a second later). Two limits: ``frameByteLimit`` a frame, as a page of many
/// pictures would otherwise stall on one write, and ``bytesPerSecond`` over time.
/// Past either, a cell already showing pixels keeps them, the last frame of a playing
/// picture say, and any other gets half blocks. A later frame draws what is owed:
/// ``Result/retryNanos``.
@MainActor
final class SixelPictureLayer {
    /// What one screen cell shows.
    private struct Shown: Equatable {
        var image: KittyGraphics.ImageID
        var placement: UInt32?
        var imageRow: Int
        var imageColumn: Int
    }

    /// The bytes of Sixel one frame may write, past its first block.
    static let frameByteLimit = 1 << 20

    /// The bytes of Sixel a second, over time: about what iTerm2 3.7.6 was measured
    /// to turn into a picture (887 KB showed within a second of its write), so that
    /// motion does not fall behind what is on screen (§16).
    static let bytesPerSecond = 1 << 20

    /// What each row's cells show, by screen row. Only rows with a picture.
    private var onScreen: [Int: [Shown?]] = [:]

    /// The cells showing a half block of what they should show in pixels.
    private var glyphs: [Int: [Shown?]] = [:]

    /// Each on-screen image's colours, chosen once from all its pixels so that two
    /// rectangles of it agree. Goes with the image's last cell.
    private var palettes: [KittyGraphics.ImageID: SixelEncoder.Palette] = [:]

    /// The bytes written and not yet paid for at ``bytesPerSecond``, as of ``paidAt``.
    private var debt = 0
    private var paidAt: UInt64 = 0

    /// The pixels of one cell, in Sixel's own: not necessarily what is reported as
    /// points (`CellPointsCalibration`).
    var cell = TerminalCellPixels(width: 10, height: 20) {
        didSet {
            if cell != oldValue { invalidate() }
        }
    }

    /// How many colours a picture may have: what the terminal says it has registers
    /// for (`XTSMGRAPHICS`), or 256.
    var colourLimit = 256

    /// Forgets what is on screen: the next frame draws every picture.
    func invalidate() {
        onScreen.removeAll()
        glyphs.removeAll()
    }

    /// What a frame did.
    struct Result {
        /// Whether it moved the cursor.
        var moved = false
        /// Whether it wrote glyphs, leaving the writer's belief about styling wrong.
        var styled = false
        /// The bytes of Sixel it wrote.
        var bytes = 0
        /// When the pixels it still owes can be afforded, or `nil` if it owes none.
        var retryNanos: UInt64?
    }

    /// Draws what `rows`' cells should show and do not.
    ///
    /// - Parameters:
    ///   - rows: The picture cells of each screen row: every one the writer left
    ///     unwritten.
    ///   - screenRows: The terminal's height, for the block that reaches its last row.
    func draw(
        rows: [[KittyGraphics.PlaceholderRun]], store: TerminalImageStore,
        background: SixelEncoder.Background?, screenRows: Int, nowNanos: UInt64,
        on terminal: any TerminalProtocol, startRow: Int
    ) -> Result {
        var next: [Int: [Shown?]] = [:]
        var missing: [[KittyGraphics.PlaceholderRun]] = []
        for (row, runs) in rows.enumerated() {
            var missingRuns: [KittyGraphics.PlaceholderRun] = []
            for run in runs { keep(run, row: row, next: &next, missing: &missingRuns) }
            missing.append(missingRuns)
        }
        var result = Result()
        pay(until: nowNanos)
        let blocks = PicturePlacementLayer.blocks(of: missing.map { $0.compactMap { store.placementRun(for: $0) } })
            .values.sorted { ($0.row, $0.run.column) < ($1.row, $1.run.column) }
        var owed: [PicturePlacementLayer.Block] = []
        for block in blocks {
            guard debt == 0 || result.bytes > 0, result.bytes < Self.frameByteLimit else {
                owed.append(block)
                continue
            }
            guard let encoded = encoded(block, store: store, background: background) else { continue }
            terminal.moveCursor(toRow: startRow + block.row, column: block.run.column + 1)
            // Without this a host that puts its cursor below a picture, as xterm and
            // foot do, would scroll the screen for a picture on the last row (§16).
            // iTerm2 ignores it and does not scroll (measured).
            let reachesLastRow = block.row + block.rows >= screenRows
            terminal.write(reachesLastRow ? "\u{1B}[?8452h" + encoded + "\u{1B}[?8452l" : encoded)
            result.moved = true
            result.bytes += encoded.utf8.count
            for cell in cells(of: block, in: missing) { set(cell.shown, row: cell.row, column: cell.column, in: &next) }
        }
        debt += result.bytes
        var nextGlyphs: [Int: [Shown?]] = [:]
        for block in owed {
            let wrote = writeHalfBlocks(
                of: block, cells: cells(of: block, in: missing), next: &next, nextGlyphs: &nextGlyphs, store: store,
                background: background, on: terminal, startRow: startRow)
            if wrote {
                result.moved = true
                result.styled = true
            }
        }
        onScreen = next
        glyphs = nextGlyphs
        forgetPalettes()
        if !owed.isEmpty {
            let waiting = UInt64(max(debt, 1)) * 1_000_000_000 / UInt64(Self.bytesPerSecond)
            result.retryNanos = max(waiting, 16_666_667)
        }
        return result
    }

    /// `run`, on `row`: the cells already showing what it draws go into `next`, and
    /// the rest into `missing`, as runs of their own.
    private func keep(
        _ run: KittyGraphics.PlaceholderRun, row: Int, next: inout [Int: [Shown?]],
        missing: inout [KittyGraphics.PlaceholderRun]
    ) {
        let width = run.column + run.columns
        var shownNext = next[row] ?? []
        if shownNext.count < width { shownNext += [Shown?](repeating: nil, count: width - shownNext.count) }
        let before = onScreen[row]
        var pending: KittyGraphics.PlaceholderRun?
        for offset in 0..<run.columns {
            let column = run.column + offset
            let wanted = Shown(
                image: run.image, placement: run.placement, imageRow: run.imageRow,
                imageColumn: run.imageColumn + offset)
            if let before, column < before.count, before[column] == wanted {
                shownNext[column] = wanted
                if let done = pending { missing.append(done) }
                pending = nil
            } else if pending != nil {
                pending?.columns += 1
            } else {
                pending = KittyGraphics.PlaceholderRun(
                    column: column, columns: 1, image: run.image, placement: run.placement, imageRow: run.imageRow,
                    imageColumn: run.imageColumn + offset)
            }
        }
        if let done = pending { missing.append(done) }
        next[row] = shownNext
    }

    /// Pays off ``debt`` for the time since it was last paid.
    private func pay(until now: UInt64) {
        defer { paidAt = now }
        guard debt > 0, now > paidAt else { return }
        let paid = (now - paidAt) / (1_000_000_000 / UInt64(Self.bytesPerSecond))
        debt = paid >= UInt64(debt) ? 0 : debt - Int(paid)
    }

    /// `block` as the escape that draws it at the cursor, at its cells' own pixels.
    private func encoded(
        _ block: PicturePlacementLayer.Block, store: TerminalImageStore, background: SixelEncoder.Background?
    ) -> String? {
        guard let pixels = store.pixels(of: block.run) else { return nil }
        let id = block.run.image
        if palettes[id] == nil, let whole = store.pixels(ofWhole: id) {
            palettes[id] = SixelEncoder.Palette(rgba: whole.bytes, background: background, limit: colourLimit)
        }
        let width = block.run.columns * cell.width
        let height = block.rows * cell.height
        let fitted = SixelEncoder.resampled(
            rgba: pixels.bytes, width: pixels.width, height: pixels.height, toWidth: width, toHeight: height)
        guard !fitted.isEmpty else { return nil }
        // A palette is asked for above; a picture with no whole form to ask gets one
        // of its own here.
        var palette =
            palettes[id] ?? SixelEncoder.Palette(rgba: fitted, background: background, limit: colourLimit)
        // Moved out and back, so a dictionary's copy-on-write does not copy the table.
        palettes[id] = nil
        defer { palettes[id] = palette }
        return SixelEncoder.encode(rgba: fitted, width: width, height: height, palette: &palette, background: background)
    }

    /// `block`'s cells, and what each of them is to show.
    private func cells(
        of block: PicturePlacementLayer.Block, in missing: [[KittyGraphics.PlaceholderRun]]
    ) -> [(row: Int, column: Int, shown: Shown)] {
        var cells: [(row: Int, column: Int, shown: Shown)] = []
        for row in block.row..<(block.row + block.rows) where row < missing.count {
            for run in missing[row] where run.image == block.run.image && run.column == block.run.column {
                for offset in 0..<run.columns {
                    let shown = Shown(
                        image: run.image, placement: run.placement, imageRow: run.imageRow,
                        imageColumn: run.imageColumn + offset)
                    cells.append((row, run.column + offset, shown))
                }
            }
        }
        return cells
    }

    private func set(_ shown: Shown?, row: Int, column: Int, in map: inout [Int: [Shown?]]) {
        var cells = map[row] ?? []
        if cells.count <= column { cells += [Shown?](repeating: nil, count: column + 1 - cells.count) }
        cells[column] = shown
        map[row] = cells
    }

    private func shown(row: Int, column: Int, in map: [Int: [Shown?]]) -> Shown? {
        guard let cells = map[row], column < cells.count else { return nil }
        return cells[column]
    }

    /// What is owed for `block` until its pixels can be: a cell showing pixels, of any
    /// picture, keeps them and goes on saying so, stale and not blank, and any other
    /// gets a half block unless it already has this one.
    ///
    /// - Returns: Whether it wrote any.
    private func writeHalfBlocks(
        of block: PicturePlacementLayer.Block, cells: [(row: Int, column: Int, shown: Shown)],
        next: inout [Int: [Shown?]], nextGlyphs: inout [Int: [Shown?]], store: TerminalImageStore,
        background: SixelEncoder.Background?, on terminal: any TerminalProtocol, startRow: Int
    ) -> Bool {
        var needed: [(row: Int, column: Int)] = []
        for cell in cells {
            if let stale = shown(row: cell.row, column: cell.column, in: onScreen) {
                set(stale, row: cell.row, column: cell.column, in: &next)
                continue
            }
            set(cell.shown, row: cell.row, column: cell.column, in: &nextGlyphs)
            if shown(row: cell.row, column: cell.column, in: glyphs) != cell.shown {
                needed.append((cell.row, cell.column))
            }
        }
        guard !needed.isEmpty, let pixels = store.pixels(of: block.run) else { return false }
        let halves = SixelEncoder.halfBlocks(
            rgba: pixels.bytes, width: pixels.width, height: pixels.height, columns: block.run.columns,
            rows: block.rows, background: background)
        guard halves.count == block.rows else { return false }
        var after: (row: Int, column: Int)?
        for cell in needed {
            let glyph = halves[cell.row - block.row][cell.column - block.run.column]
            if let after, after == (cell.row, cell.column) {
                terminal.write(glyph)
            } else {
                terminal.moveCursor(toRow: startRow + cell.row, column: cell.column + 1)
                terminal.write(glyph)
            }
            after = (cell.row, cell.column + 1)
        }
        terminal.write("\u{1B}[0m")
        return true
    }

    /// Lets go of the colours of images no cell shows.
    private func forgetPalettes() {
        guard !palettes.isEmpty else { return }
        var inUse = Set<KittyGraphics.ImageID>()
        for row in onScreen.values {
            for shown in row {
                if let shown { inUse.insert(shown.image) }
            }
        }
        for id in palettes.keys where !inUse.contains(id) { palettes[id] = nil }
    }

    /// What the terminal is owed before the app lets go of it: nothing, as leaving
    /// the alternate screen takes the pixels. Forgets them, so the first frame after
    /// a resume draws what it shows.
    func farewell() {
        invalidate()
        palettes.removeAll()
        debt = 0
    }
}
