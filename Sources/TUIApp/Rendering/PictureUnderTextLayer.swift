//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureUnderTextLayer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The pictures laid under glyphs that stand on a frosted picture, kept in
/// step with the terminal: one Kitty classic placement per block of marked
/// cells the diff writer found (``PictureUnderTextMarker``), cropped to the
/// pixels of the picture's copy those cells cover and scaled to fill them, at
/// `z=-1` — below the glyphs, above the cells' default field (graphics notes
/// §14.5).
///
/// ## Blocks
///
/// A block is a run and the runs below it that continue it: the same cells
/// across, the same image, the next row of its pixels. Under a glass every
/// cell of whose frost backdrop is marked, it is the whole glass, placed once:
/// the terminal scales it as one picture, so no seam shows where one row's
/// crop or one run's would meet the next (§14.6).
///
/// ## What it keeps
///
/// A placement stays on screen until it is deleted, whatever is drawn over
/// it, as a hairline's does (``HairlineLayer``). So this keeps what the
/// terminal holds and each frame sends only the difference: a placement for
/// a block that is new or has changed, a delete for one that has gone.
/// Placing a block again by the same `(i, p)` replaces it in place.
///
/// ## Whose images
///
/// The image store's: the derived copies it made of a picture under a
/// translucent layer, sent and deleted by it. This places and deletes
/// placements only. A copy the store deletes takes its placements with it,
/// and the cells that named it name another copy, whose block is placed anew.
@MainActor
final class PictureUnderTextLayer {

    /// Below the glyphs, above a cell's default field: the spec's `z<0`, and
    /// Ghostty's (measured, §14.5). Never 0.
    static let z: Int32 = -1

    /// How many blocks can start on one row: a placement id carries the row
    /// above eight bits and the block below, as a hairline's does.
    static let maximumBlocksPerRow = 255

    /// A run, and how many rows down it reaches: its pixels run that far.
    struct Block: Hashable {
        /// The screen row of its first run.
        var row: Int
        var rows: Int
        /// Its first run, its pixels' height stretched over every row.
        var run: PictureUnderTextMarker.Run
    }

    /// The blocks the terminal holds, by placement id — what the last frame
    /// placed.
    private var placed: [UInt32: Block] = [:]

    /// Whether the terminal's screen may no longer be what ``placed`` says.
    private var isInvalid = false

    /// What ``prepare(rows:)`` decided the frame owes the screen, for
    /// ``place(on:startRow:)`` to write.
    private var deletes: [(image: KittyGraphics.ImageID, placement: UInt32)] = []
    private var places: [(block: Block, placement: UInt32)] = []

    /// Whether the layer has nothing on screen and nothing owed — the state a
    /// host not drawing pictures under text never leaves.
    var isIdle: Bool { placed.isEmpty && !isInvalid && deletes.isEmpty }

    /// Forgets what is on screen: the next frame deletes every placement and
    /// places every block again.
    func invalidate() {
        guard !placed.isEmpty else { return }
        isInvalid = true
    }

    /// Works out what this frame owes the terminal for `rows`, one entry per
    /// screen row in screen order.
    func prepare(rows: [[PictureUnderTextMarker.Run]]) {
        places.removeAll(keepingCapacity: true)
        if isInvalid {
            deletes += everyPlacement()
            placed.removeAll()
            isInvalid = false
        }
        let wanted = Self.blocks(of: rows)
        for (placement, before) in placed where wanted[placement] == nil {
            deletes.append((before.run.image, placement))
        }
        for (placement, after) in wanted {
            let before = placed[placement]
            guard before != after else { continue }
            // A block that changed on the same image is placed again by the same
            // `(i, p)`, which replaces it; one on another image leaves the old
            // one's placement to delete.
            if let before, before.run.image != after.run.image {
                deletes.append((before.run.image, placement))
            }
            places.append((after, placement))
        }
        // In screen order, so a frame's bytes do not depend on a dictionary's.
        places.sort { ($0.block.row, $0.placement) < ($1.block.row, $1.placement) }
        placed = wanted
    }

    /// `rows`' runs gathered into blocks, by placement id: each run continues
    /// a block that ended on the row above if one has its cells across, its
    /// image and its pixels across, and its pixels end where the run's begin.
    static func blocks(of rows: [[PictureUnderTextMarker.Run]]) -> [UInt32: Block] {
        var blocks: [Block] = []
        // The blocks that reached the row above, by their index in `blocks`.
        var open: [Int] = []
        for (row, runs) in rows.enumerated() {
            var reaching: [Int] = []
            var starting = 0
            for run in runs {
                if let index = open.first(where: { blocks[$0].continues(into: run) }) {
                    blocks[index].rows += 1
                    blocks[index].run.height += run.height
                    reaching.append(index)
                } else if starting < maximumBlocksPerRow {
                    blocks.append(Block(row: row, rows: 1, run: run))
                    reaching.append(blocks.count - 1)
                    starting += 1
                }
            }
            open = reaching
        }
        var byPlacement: [UInt32: Block] = [:]
        var index = 0
        for (offset, block) in blocks.enumerated() {
            index = offset > 0 && blocks[offset - 1].row == block.row ? index + 1 : 0
            byPlacement[placementID(row: block.row, index: index)] = block
        }
        return byPlacement
    }

    /// Writes the deletes and placements ``prepare(rows:)`` decided, inside
    /// the frame's hold, each placement after a move to its block's first
    /// cell. Once: what it writes is forgotten as it is written.
    ///
    /// - Returns: Whether it moved the cursor.
    @discardableResult
    func place(on terminal: any TerminalProtocol, startRow: Int) -> Bool {
        defer {
            deletes.removeAll(keepingCapacity: true)
            places.removeAll(keepingCapacity: true)
        }
        for delete in deletes {
            terminal.write(KittyGraphics.deletePlacement(id: delete.image, placement: delete.placement))
        }
        guard !places.isEmpty else { return false }
        for place in places {
            let run = place.block.run
            terminal.moveCursor(toRow: startRow + place.block.row, column: run.column + 1)
            terminal.write(
                KittyGraphics.classicPlacement(
                    id: run.image, placement: place.placement, crop: (run.x, run.y, run.width, run.height),
                    columns: run.columns, rows: place.block.rows, z: Self.z))
        }
        return true
    }

    /// What the terminal is owed before the app lets go of it — a suspend, a
    /// quit: every placement deleted. Forgets them, so the first frame after a
    /// resume places what it shows.
    func farewell() -> String {
        let out = (deletes + everyPlacement()).map { KittyGraphics.deletePlacement(id: $0.image, placement: $0.placement) }
            .joined()
        deletes.removeAll()
        places.removeAll()
        placed.removeAll()
        isInvalid = false
        return out
    }

    /// Every placement ``placed`` says the terminal holds.
    private func everyPlacement() -> [(image: KittyGraphics.ImageID, placement: UInt32)] {
        placed.sorted { $0.key < $1.key }.map { ($0.value.run.image, $0.key) }
    }

    /// A block's placement id: its first row above eight bits, its place
    /// among the blocks starting on that row below, counting from 1 — `p=0`
    /// is the protocol's "none".
    static func placementID(row: Int, index: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: row) << 8 | UInt32(truncatingIfNeeded: index + 1)
    }
}

extension PictureUnderTextLayer.Block {
    /// Whether `run`, on the row below this block's last, carries it on: the
    /// same cells across, the same image and pixels across, and its pixels
    /// starting where the block's end.
    func continues(into run: PictureUnderTextMarker.Run) -> Bool {
        self.run.column == run.column && self.run.columns == run.columns && self.run.image == run.image
            && self.run.x == run.x && self.run.width == run.width && self.run.y + self.run.height == run.y
    }
}
