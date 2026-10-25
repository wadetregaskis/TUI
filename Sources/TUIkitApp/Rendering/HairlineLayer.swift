//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HairlineLayer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

// MARK: - The lines between rows, as the terminal holds them

/// The lines a `.hairline` list separator draws, kept in step with the
/// terminal: one Kitty classic placement per run of marked cells the diff
/// writer found in the frame (``HairlineMarker``), placed along the top edge of
/// those cells, a pixel or two thick, outside the cell grid.
///
/// ## What it keeps
///
/// A placement stays on screen until it is deleted — nothing the writer draws
/// over it, and nothing a resize does, takes it away (Ghostty 1.3.1 and iTerm2
/// 3.7.3, `Tools/TerminalProbes/hairline_probe.py`). So this keeps a model of
/// what the terminal holds, row by row, and each frame sends only the
/// difference: a placement for a run that is new or has moved, a delete for
/// one that has gone. A frame whose runs did not change sends nothing, and a
/// frame on a host not drawing lines never reaches here.
///
/// ## The strips
///
/// One picture per colour, the width of the screen and the line's thickness,
/// sent once and cropped per run (`w`) — so a run of any width is one ~60-byte
/// placement, and a page of separators in the border's colour is one
/// transmission. Ids from a range of their own at the top of the id space,
/// below the startup handshake's two, which ``TerminalImageStore`` (counting up
/// from 1) does not reach.
///
/// A strip is sent again:
///
/// - after ``invalidate()`` — a resize, a resumed suspend, anything after which
///   the terminal's screen is not what this model says. Every strip is deleted
///   with its placements (`d=I`), and the frame after places every run afresh.
///   Ghostty frees a strip on `ESC[2J` and on leaving the alternate screen,
///   so it has to be sent again there anyway.
/// - when it was left with no placement. A frame that takes a colour's last
///   line away deletes its strip too (`d=I`), rather than keep pixels nobody
///   shows: a terminal running out of room deletes the images that have no
///   placement first (the spec's quota rule), and a placement of an evicted
///   strip under `q=2` is a line that silently never appears. It also frees
///   the colour's slot.
@MainActor
final class HairlineLayer {

    /// What the strips and the crops are measured against: the cell's size in
    /// the terminal's pixels, and the screen's width in cells.
    struct Geometry: Equatable {
        var cellWidth: Int
        var cellHeight: Int
        var columns: Int

        /// The line's thickness: about a point — 2 px on a Retina Ghostty's
        /// 34-pixel cell, 1 on a 16-pixel one. The probe's rule, kept.
        var thickness: Int { max(1, cellHeight / 17) }
    }

    /// The z-index every line is placed at: above the glyphs on Ghostty, where
    /// `z=-1` does not show over every fill; below them elsewhere, where the
    /// spec puts `z=-1` (iTerm2 3.7.3 showed it on every fill). Never 0.
    let z: Int32

    init(z: Int32) {
        self.z = z == 0 ? -1 : z
    }

    /// The z for `program` — see ``z``.
    static func z(for program: TerminalClient.Program) -> Int32 {
        program == .ghostty ? 1 : -1
    }

    /// One colour's strip.
    private struct Strip {
        let id: KittyGraphics.ImageID
        /// Whether it has been sent: a strip is made the frame it is first
        /// placed, and sent before that frame's hold.
        var isSent = false
        /// How many placements of it are on screen.
        var placements = 0
    }

    /// The strips, by colour (``HairlineMarker/Run/ink``).
    private var strips: [UInt32: Strip] = [:]

    /// The first id the strips take, counting down: below the handshake's
    /// placement and compression probes.
    static let firstStripID: KittyGraphics.ImageID = KittyGraphics.maximumImageID - 2

    /// How many colours can have a strip at once. A run in a colour past them
    /// draws no line — a list's separators are the border's colour and a
    /// handful of tints, not a gradient.
    static let maximumStrips = 16

    /// How many runs one row can hold: a placement id carries the row above
    /// eight bits and the run below.
    static let maximumRunsPerRow = 255

    /// The runs the terminal holds, row by row — what the last frame placed.
    private var placed: [[HairlineMarker.Run]] = []

    /// The geometry the strips and placements were made for.
    private var geometry: Geometry?

    /// Whether the terminal's screen may no longer be what ``placed`` says.
    private var isInvalid = false

    /// What ``prepare(rows:geometry:compressed:)`` decided the frame owes the
    /// screen, for ``place(on:startRow:)`` to write.
    private var deletes: [(id: KittyGraphics.ImageID, placement: UInt32)] = []
    private var freed: [KittyGraphics.ImageID] = []
    private var places: [(row: Int, run: HairlineMarker.Run, id: KittyGraphics.ImageID, placement: UInt32)] = []

    /// Whether the layer has nothing on screen and nothing owed — the state a
    /// host not drawing lines never leaves.
    var isIdle: Bool { placed.isEmpty && strips.isEmpty && !isInvalid }

    /// Forgets what is on screen: the next frame deletes every strip, with its
    /// placements, and places every run again.
    func invalidate() {
        guard !strips.isEmpty || !placed.isEmpty else { return }
        isInvalid = true
    }

    /// Works out what this frame owes the terminal for `rows`, one entry per
    /// screen row in screen order, and returns what must go BEFORE the frame's
    /// synchronized hold: the deletes an invalidation owes and the strips to
    /// send. Both draw nothing, and a strip can be large enough to outlast a
    /// hold, as the run loop's own image transmissions are.
    ///
    /// - Parameters:
    ///   - rows: The runs the writer found on each row of the frame.
    ///   - geometry: The cell's pixel size and the screen's width, this frame.
    ///   - compressed: Whether the terminal takes a strip deflated (`o=z`).
    func prepare(rows: [[HairlineMarker.Run]], geometry: Geometry, compressed: Bool) -> String {
        deletes.removeAll(keepingCapacity: true)
        freed.removeAll(keepingCapacity: true)
        places.removeAll(keepingCapacity: true)
        var out = ""
        if let previous = self.geometry, previous != geometry { isInvalid = !strips.isEmpty || !placed.isEmpty }
        self.geometry = geometry
        if isInvalid {
            out += forgetEverything()
            isInvalid = false
        }

        var held = placed
        let rowCount = max(rows.count, held.count)
        if held.count < rowCount { held += Array(repeating: [], count: rowCount - held.count) }
        for row in 0..<rowCount {
            let new = row < rows.count ? Array(rows[row].prefix(Self.maximumRunsPerRow)) : []
            let old = held[row]
            guard new != old else { continue }
            var kept: [HairlineMarker.Run] = []
            for index in 0..<max(old.count, new.count) {
                let placement = Self.placementID(row: row, index: index)
                let before = index < old.count ? old[index] : nil
                let after = index < new.count ? new[index] : nil
                if let before, before == after {
                    kept.append(before)
                    continue
                }
                // A run that moved in the same colour is placed again by the
                // same `(i, p)`, which replaces it; one whose colour changed is
                // another strip's, so the old one goes first.
                if let before, before.ink != after?.ink, let strip = strips[before.ink] {
                    deletes.append((strip.id, placement))
                    strips[before.ink]?.placements -= 1
                }
                guard let after else { continue }
                guard let id = stripID(for: after.ink) else { continue }
                if before?.ink != after.ink { strips[after.ink]?.placements += 1 }
                places.append((row, after, id, placement))
                kept.append(after)
            }
            held[row] = kept
        }
        while let last = held.last, last.isEmpty { held.removeLast() }
        placed = held

        // The strips first placed this frame, sent before it. Sorted, so the
        // bytes a frame writes do not depend on a dictionary's order.
        for (ink, strip) in strips.sorted(by: { $0.key < $1.key }) where !strip.isSent && strip.placements > 0 {
            out += Self.transmit(strip: strip.id, ink: ink, geometry: geometry, compressed: compressed)
            strips[ink]?.isSent = true
        }
        // A strip left with no placement goes, pixels and slot (see the type's
        // documentation): deleted in the hold, after its last placement.
        for (ink, strip) in strips.sorted(by: { $0.key < $1.key }) where strip.placements <= 0 {
            if strip.isSent { freed.append(strip.id) }
            strips[ink] = nil
        }
        return out
    }

    /// Writes the deletes and placements ``prepare(rows:geometry:compressed:)``
    /// decided, inside the frame's hold, each placement after a move to its
    /// run's first cell. Once: what it writes is forgotten as it is written,
    /// so a frame that prepared nothing writes nothing.
    ///
    /// - Returns: Whether it moved the cursor.
    @discardableResult
    func place(on terminal: any TerminalProtocol, startRow: Int) -> Bool {
        defer {
            deletes.removeAll(keepingCapacity: true)
            freed.removeAll(keepingCapacity: true)
            places.removeAll(keepingCapacity: true)
        }
        for delete in deletes {
            terminal.write(KittyGraphics.deletePlacement(id: delete.id, placement: delete.placement))
        }
        for id in freed { terminal.write(KittyGraphics.delete(id: id)) }
        guard let geometry, !places.isEmpty else { return false }
        for place in places {
            terminal.moveCursor(toRow: startRow + place.row, column: place.run.column + 1)
            terminal.write(
                KittyGraphics.classicPlacement(
                    id: place.id, placement: place.placement,
                    sourceWidth: place.run.width * geometry.cellWidth, sourceHeight: geometry.thickness, z: z))
        }
        return true
    }

    /// What the terminal is owed before the app lets go of it — a suspend, a
    /// quit: every strip deleted with its placements, which on iTerm2 would
    /// otherwise stay on the shell's screen (Q8). Forgets them, so the first
    /// frame after a resume sends what it places.
    func farewell() -> String {
        let out = forgetEverything()
        isInvalid = false
        return out
    }

    /// Deletes every strip and its placements, and forgets them all.
    private func forgetEverything() -> String {
        var out = ""
        for strip in strips.values.sorted(by: { $0.id > $1.id }) {
            out += KittyGraphics.delete(id: strip.id)
        }
        strips.removeAll()
        placed.removeAll()
        return out
    }

    /// The strip `ink` is drawn with, given one if it has none and a slot is
    /// free; `nil` when every slot is taken.
    private func stripID(for ink: UInt32) -> KittyGraphics.ImageID? {
        if let strip = strips[ink] { return strip.id }
        let taken = Set(strips.values.map(\.id))
        for slot in 0..<Self.maximumStrips {
            let id = Self.firstStripID - KittyGraphics.ImageID(slot)
            guard !taken.contains(id) else { continue }
            strips[ink] = Strip(id: id)
            return id
        }
        return nil
    }

    /// A run's placement id: its row above eight bits, its place in the row
    /// below, counting from 1 — `p=0` is the protocol's "none".
    static func placementID(row: Int, index: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: row) << 8 | UInt32(truncatingIfNeeded: index + 1)
    }

    /// The strip for `ink`: the screen's width in pixels by the line's
    /// thickness, in that one colour, opaque.
    static func transmit(
        strip id: KittyGraphics.ImageID, ink: UInt32, geometry: Geometry, compressed: Bool
    ) -> String {
        let width = max(1, geometry.columns * geometry.cellWidth)
        let height = geometry.thickness
        let pixel: [UInt8] = [
            UInt8(truncatingIfNeeded: ink >> 16), UInt8(truncatingIfNeeded: ink >> 8), UInt8(truncatingIfNeeded: ink),
        ]
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 3)
        for _ in 0..<(width * height) { pixels += pixel }
        return KittyGraphics.transmit(
            pixels: pixels, format: .rgb, width: width, height: height, id: id, compressed: compressed)
    }
}
