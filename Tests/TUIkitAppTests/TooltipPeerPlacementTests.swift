//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TooltipPeerPlacementTests.swift
//
//  The panels of `.tooltips(.always)` placed as a set at the screen root
//  (`OverlayLayer.arrangingPeers`): none over another, none over its own view,
//  as little as possible over the other views with help, in reading order,
//  and dropped rather than overlapped when there is no room.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation

@Suite("Tooltip panels placed as a set")
struct TooltipPeerPlacementTests {

    /// A panel `width` × `height`, every row of it `label`'s first letter, for
    /// a view `anchorWidth` × `anchorHeight` at (`x`, `y`) — attached as
    /// `TooltipPopover.attach` attaches one, below the view.
    private func panel(
        _ label: String, view x: Int, _ y: Int, anchorWidth: Int, anchorHeight: Int = 1,
        width: Int, height: Int = 3, rank: Int = 2
    ) -> OverlayLayer {
        let row = String(repeating: String(label.prefix(1)), count: width)
        var layer = OverlayLayer(
            offsetX: x, offsetY: y + anchorHeight,
            content: FrameBuffer(lines: Array(repeating: row, count: height)),
            level: .popover, anchorHeight: anchorHeight)
        layer.peerPlacement = OverlayLayer.PeerPlacement(anchorWidth: anchorWidth, rank: rank)
        return layer
    }

    /// Where a placed layer is, and how big.
    private func rect(_ layer: OverlayLayer) -> CellRect {
        CellRect(x: layer.offsetX, y: layer.offsetY, width: layer.content.width, height: layer.content.height)
    }

    private func overlap(_ lhs: CellRect, _ rhs: CellRect) -> Bool {
        lhs.x < rhs.maxX && rhs.x < lhs.maxX && lhs.y < rhs.maxY && rhs.y < lhs.maxY
    }

    /// The placed panel whose rows are `letter`s.
    private func placed(_ letter: Character, in layers: [OverlayLayer]) -> CellRect? {
        layers.first { $0.content.lines.first?.first == letter }.map(rect)
    }

    /// The measured case (session notes MISC12 §3.2 F): a `Button` above a
    /// `Text`, each with help. Placed alone, the Button's panel went directly
    /// below it — over the Text and the Text's own panel.
    @Test("Two stacked views each keep a whole panel, over neither view")
    func stackedViewsBothFit() throws {
        let views = [CellRect(x: 0, y: 0, width: 8, height: 1), CellRect(x: 0, y: 1, width: 10, height: 1)]
        let out = OverlayLayer.arrangingPeers(
            [
                panel("Button", view: 0, 0, anchorWidth: 8, width: 19),
                panel("Text", view: 0, 1, anchorWidth: 10, width: 17),
            ], maxWidth: 50, maxHeight: 14)
        #expect(out.count == 2, "both kept")
        let button = try #require(placed("B", in: out))
        let text = try #require(placed("T", in: out))
        #expect(!overlap(button, text), "the panels overlap: \(button) \(text)")
        for view in views {
            #expect(!overlap(button, view) && !overlap(text, view), "a panel covers a view: \(view)")
        }
        #expect(out.allSatisfy { $0.peerPlacement == nil && $0.anchorHeight == 0 }, "placed for good")
    }

    /// A lone panel goes where the shared rule would put it: directly below
    /// its view, left-aligned (§5's rule 1).
    @Test("A lone panel goes directly below its view")
    func lonePanelBelow() throws {
        let out = OverlayLayer.arrangingPeers(
            [panel("Only", view: 4, 2, anchorWidth: 6, width: 12)], maxWidth: 40, maxHeight: 10)
        let only = try #require(placed("O", in: out))
        #expect(only == CellRect(x: 4, y: 3, width: 12, height: 3), "got \(only)")
    }

    /// Reading order, not emission order: the same page draws the same panels
    /// in the same places, however its views were built.
    @Test("The order the views were emitted in moves no panel")
    func emissionOrderMovesNothing() {
        let layers = [
            panel("Alpha", view: 0, 0, anchorWidth: 6, width: 20),
            panel("Bravo", view: 0, 1, anchorWidth: 6, width: 20),
            panel("Charlie", view: 10, 1, anchorWidth: 6, width: 20),
        ]
        let forward = OverlayLayer.arrangingPeers(layers, maxWidth: 60, maxHeight: 12)
        let backward = OverlayLayer.arrangingPeers(layers.reversed(), maxWidth: 60, maxHeight: 12)
        for letter in ["A", "B", "C"] as [Character] {
            #expect(placed(letter, in: forward) == placed(letter, in: backward), "\(letter) moved")
        }
    }

    /// No room for both: the first in reading order keeps its panel and the
    /// other is left out rather than drawn over it.
    @Test("A panel with no room is dropped, not drawn over another")
    func noRoomDrops() throws {
        let out = OverlayLayer.arrangingPeers(
            [
                panel("First", view: 0, 0, anchorWidth: 5, width: 18),
                panel("Second", view: 0, 1, anchorWidth: 6, width: 18),
            ], maxWidth: 20, maxHeight: 5)
        #expect(out.count == 1, "one fits: \(out.map(rect))")
        #expect(placed("F", in: out) != nil, "and it is the first in reading order")
    }

    /// The rank comes before reading order: the caller ranks the view under the
    /// pointer first, so pointing at a view whose panel lost its place brings
    /// it back.
    @Test("The view ranked first gets the room")
    func rankWins() {
        let out = OverlayLayer.arrangingPeers(
            [
                panel("First", view: 0, 0, anchorWidth: 5, width: 18),
                panel("Second", view: 0, 1, anchorWidth: 6, width: 18, rank: 0),
            ], maxWidth: 20, maxHeight: 5)
        #expect(out.count == 1)
        #expect(placed("S", in: out) != nil, "the ranked panel kept its place")
    }

    /// Everything else on the page passes through as it was, in its order: a
    /// drop-down is not a tooltip, and the set has no say over where it goes.
    @Test("Layers that are not panels of the set are untouched")
    func otherLayersUntouched() {
        let menu = OverlayLayer(
            offsetX: 3, offsetY: 1, content: FrameBuffer(lines: ["menu"]), level: .popover, anchorHeight: 1)
        let dialog = OverlayLayer(
            offsetX: 0, offsetY: 0, content: FrameBuffer(lines: ["dialog"]), level: .modal, centered: true)
        let out = OverlayLayer.arrangingPeers(
            [menu, panel("Help", view: 0, 0, anchorWidth: 4, width: 10), dialog], maxWidth: 40, maxHeight: 10)
        #expect(out.count == 3)
        #expect(out.first == menu && out.last == dialog, "moved or reordered: \(out.map(\.content.lines))")
        #expect(OverlayLayer.arrangingPeers([menu, dialog], maxWidth: 40, maxHeight: 10) == [menu, dialog])
    }
}
