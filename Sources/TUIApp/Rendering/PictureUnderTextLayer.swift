//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureUnderTextLayer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The pictures laid under glyphs that stand on a frosted picture, kept in
/// step with the terminal: one Kitty classic placement per run of marked
/// cells the diff writer found (``PictureUnderTextMarker``), cropped to the
/// pixels of the picture's copy those cells cover and scaled to fill them, at
/// `z=-1` — below the glyphs, above the cells' default field (graphics notes
/// §14.5).
///
/// ## What it keeps
///
/// A placement stays on screen until it is deleted, whatever is drawn over
/// it, as a hairline's does (``HairlineLayer``). So this keeps what the
/// terminal holds, row by row, and each frame sends only the difference: a
/// placement for a run that is new or has moved, a delete for one that has
/// gone. Placing a run again by the same `(i, p)` replaces it in place.
///
/// ## Whose images
///
/// The image store's: the derived copies it made of a picture under a
/// translucent layer, sent and deleted by it. This places and deletes
/// placements only. A copy the store deletes takes its placements with it,
/// and the cells that named it name another copy, whose run is placed anew.
@MainActor
final class PictureUnderTextLayer {

    /// Below the glyphs, above a cell's default field: the spec's `z<0`, and
    /// Ghostty's (measured, §14.5). Never 0.
    static let z: Int32 = -1

    /// How many runs one row can hold: a placement id carries the row above
    /// eight bits and the run below, as a hairline's does.
    static let maximumRunsPerRow = 255

    /// The runs the terminal holds, row by row — what the last frame placed.
    private var placed: [[PictureUnderTextMarker.Run]] = []

    /// Whether the terminal's screen may no longer be what ``placed`` says.
    private var isInvalid = false

    /// What ``prepare(rows:)`` decided the frame owes the screen, for
    /// ``place(on:startRow:)`` to write.
    private var deletes: [(image: KittyGraphics.ImageID, placement: UInt32)] = []
    private var places: [(row: Int, run: PictureUnderTextMarker.Run, placement: UInt32)] = []

    /// Whether the layer has nothing on screen and nothing owed — the state a
    /// host not drawing pictures under text never leaves.
    var isIdle: Bool { placed.isEmpty && !isInvalid && deletes.isEmpty }

    /// Forgets what is on screen: the next frame deletes every placement and
    /// places every run again.
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
        var held = placed
        let rowCount = max(rows.count, held.count)
        if held.count < rowCount { held += Array(repeating: [], count: rowCount - held.count) }
        for row in 0..<rowCount {
            let new = row < rows.count ? Array(rows[row].prefix(Self.maximumRunsPerRow)) : []
            let old = held[row]
            guard new != old else { continue }
            for index in 0..<max(old.count, new.count) {
                let placement = Self.placementID(row: row, index: index)
                let before = index < old.count ? old[index] : nil
                let after = index < new.count ? new[index] : nil
                guard before != after else { continue }
                // A run that moved on the same image is placed again by the same
                // `(i, p)`, which replaces it; one on another image leaves the old
                // one's placement to delete.
                if let before, before.image != after?.image {
                    deletes.append((before.image, placement))
                }
                if let after { places.append((row, after, placement)) }
            }
            held[row] = new
        }
        while let last = held.last, last.isEmpty { held.removeLast() }
        placed = held
    }

    /// Writes the deletes and placements ``prepare(rows:)`` decided, inside
    /// the frame's hold, each placement after a move to its run's first cell.
    /// Once: what it writes is forgotten as it is written.
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
            terminal.moveCursor(toRow: startRow + place.row, column: place.run.column + 1)
            terminal.write(
                KittyGraphics.classicPlacement(
                    id: place.run.image, placement: place.placement,
                    crop: (place.run.x, place.run.y, place.run.width, place.run.height),
                    columns: place.run.columns, rows: 1, z: Self.z))
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
        placed.enumerated().flatMap { row, runs in
            runs.enumerated().map { index, run in (run.image, Self.placementID(row: row, index: index)) }
        }
    }

    /// A run's placement id: its row above eight bits, its place in the row
    /// below, counting from 1 — `p=0` is the protocol's "none".
    static func placementID(row: Int, index: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: row) << 8 | UInt32(truncatingIfNeeded: index + 1)
    }
}
