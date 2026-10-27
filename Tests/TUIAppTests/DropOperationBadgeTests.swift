//  🖥️ TUI — A Terminal UI framework for Swift
//  DropOperationBadgeTests.swift
//
//  The badge a drag's preview wears to name the operation the destination
//  under it proposes (decisions B10): `+` for a copy, `↗` for a link, `⊘` for
//  a drop that is not allowed, nothing for a move, a delete or a cancel — one
//  cell at the preview's top-right, as the window draws the lifted preview.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import UniformTypeIdentifiers
#endif
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("The drop-operation badge")
struct DropOperationBadgeTests {
    @Test("Each operation wears its confirmed glyph, or none")
    func glyphs() {
        #expect(DropOperation.copy.badgeGlyph == "+")
        #expect(DropOperation.alias.badgeGlyph == "\u{2197}")
        #expect(DropOperation.forbidden.badgeGlyph == "\u{2298}")
        for operation in [DropOperation.move, .delete, .cancel] {
            #expect(operation.badgeGlyph == nil, "\(operation) wears a badge")
        }
    }

    @Test("The badge takes the preview's top-right cell in its colour, and leaves every other cell")
    func badgedPreview() {
        let palette = EnvironmentValues().palette
        let preview = FrameBuffer(lines: ["ab", "cd"])
        for operation in [DropOperation.copy, .alias, .forbidden] {
            let badged = DragAndDropSession.badged(preview, operation: operation, palette: palette)
            let glyph = operation.badgeGlyph ?? ""
            #expect(badged.lines[0].stripped == "a" + glyph, "\(operation)")
            #expect(
                badged.lines[0].contains(glyph.styled(foreground: operation.badgeColor(in: palette))),
                "\(operation)'s badge is not in its colour: \(badged.lines[0].debugDescription)")
            #expect(badged.lines[1] == "cd", "\(operation)")
            #expect(badged.width == 2 && badged.height == 2, "\(operation)")
        }
        #expect(DropOperation.forbidden.badgeColor(in: palette) == palette.error)
        #expect(DropOperation.copy.badgeColor(in: palette) == palette.accent)
        for operation in [DropOperation.move, .delete, .cancel] {
            #expect(DragAndDropSession.badged(preview, operation: operation, palette: palette).lines == preview.lines)
        }
        #expect(DragAndDropSession.badged(preview, operation: nil, palette: palette).lines == preview.lines)
    }

    @Test("The badge sits where the preview's top row ends, and no row gains blank cells over the page")
    func raggedTopRow() {
        let palette = EnvironmentValues().palette
        let badged = DragAndDropSession.badged(FrameBuffer(lines: ["ab", "cdef"]), operation: .copy, palette: palette)
        #expect(badged.lines[0].stripped == "a+", "\(badged.lines[0].debugDescription)")
        #expect(badged.lines[1] == "cdef")
        #expect(badged.width == 4 && badged.height == 2)
        let blankTop = DragAndDropSession.badged(FrameBuffer(lines: ["", "cd"]), operation: .copy, palette: palette)
        #expect(blankTop.lines[0].stripped == "+", "a blank top row has no cell to cover, so the badge starts it")
        let raggedBelow = DragAndDropSession.badged(FrameBuffer(lines: ["abcd", "c"]), operation: .copy, palette: palette)
        #expect(raggedBelow.lines[0].stripped == "abc+")
        #expect(raggedBelow.lines[1] == "c", "a shorter row below keeps its own width")
        #expect(raggedBelow.lineWidths == nil || raggedBelow.lineWidths == [4, 1])
    }

    @Test("A top row of one cell wears the badge beside it, so the picture is not hidden whole")
    func oneCellPreview() {
        let palette = EnvironmentValues().palette
        let badged = DragAndDropSession.badged(FrameBuffer(lines: ["x"]), operation: .copy, palette: palette)
        #expect(badged.lines[0].stripped == "x+", "\(badged.lines[0].debugDescription)")
        let tall = DragAndDropSession.badged(FrameBuffer(lines: ["x", "yz"]), operation: .forbidden, palette: palette)
        #expect(tall.lines[0].stripped == "x\u{2298}" && tall.lines[1] == "yz")
    }

    #if canImport(UniformTypeIdentifiers)
        /// A delegate that takes the drag or not, and proposes `operation`.
        private struct Proposing: DropDelegate {
            var valid = true
            let operation: DropOperation?

            func validateDrop(info: DropInfo) -> Bool { valid }
            func dropUpdated(info: DropInfo) -> DropProposal? { operation.map { DropProposal(operation: $0) } }
            func performDrop(info: DropInfo) -> Bool { true }
        }

        /// A chip on row 0 and `zone` on row 4, as `ItemProviderDragAndDropTests` lays them out,
        /// in the window's chrome host — which draws the lifted preview — filled from the top
        /// left so its centring moves nothing.
        private func tree(_ zone: some View) -> some View {
            _WindowChromeHost(
                content: VStack(alignment: .leading, spacing: 0) {
                    Text("CHIP").draggable("apple")
                    Text("").frame(height: 3)
                    zone
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        }

        /// Picks the chip up and carries it over the zone, without letting go.
        private func hold(_ harness: InputChainHarness) {
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 4, y: 4))
        }

        /// The lifted preview's top-right cell, as the window draws the next frame.
        private func corner(_ harness: InputChainHarness, _ view: some View) throws -> Character {
            let composited = harness.frame(view)
            let frame = try #require(harness.tui.dragAndDropSession.liftedPreviewFrame(), "no preview is lifted")
            let row = paintedCells(composited.lines[frame.y])
            return try #require(row.indices.contains(frame.x + frame.width - 1) ? row[frame.x + frame.width - 1].glyph : nil)
        }

        @Test("Over a plain onDrop the preview wears +, and off it, nothing")
        func plainOnDropProposesCopy() throws {
            let harness = InputChainHarness(width: 30, height: 8)
            let page = tree(Text("ZONE========").onDrop(of: [.text], isTargeted: nil) { _ in true })
            harness.frame(page)
            hold(harness)
            #expect(harness.tui.dragAndDropSession.proposedOperation == .copy)
            #expect(try corner(harness, page) == "+")
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 25, y: 7))
            #expect(harness.tui.dragAndDropSession.proposedOperation == nil)
            #expect(try corner(harness, page) == "P", "the chip's own last letter, unbadged")
        }

        @Test(
            "A delegate's proposal names the badge, narrowed to what the source allows",
            arguments: [
                (DropOperation.copy, DropOperation.copy, Character("+")), (.alias, .alias, "\u{2197}"),
                (.forbidden, .forbidden, "\u{2298}"), (.move, .copy, "+"), (.delete, .delete, "P"),
                (.cancel, .cancel, "P"),
            ])
        func delegateProposal(operation: DropOperation, effective: DropOperation, glyph: Character) throws {
            // A `.draggable` allows a copy only, so a proposed move is a copy.
            let harness = InputChainHarness(width: 30, height: 8)
            let page = tree(Text("ZONE========").onDrop(of: [.text], delegate: Proposing(operation: operation)))
            harness.frame(page)
            hold(harness)
            #expect(harness.tui.dragAndDropSession.proposedOperation == effective)
            #expect(try corner(harness, page) == glyph)
        }

        @Test("A delegate that proposes nothing keeps copy; one that refuses the drag is a cancel, unbadged")
        func delegateDefaultsAndRefusal() throws {
            let harness = InputChainHarness(width: 30, height: 8)
            let keeps = tree(Text("ZONE========").onDrop(of: [.text], delegate: Proposing(operation: nil)))
            harness.frame(keeps)
            hold(harness)
            #expect(try corner(harness, keeps) == "+")

            let refusing = InputChainHarness(width: 30, height: 8)
            let page = tree(Text("ZONE========").onDrop(of: [.text], delegate: Proposing(valid: false, operation: .copy)))
            refusing.frame(page)
            hold(refusing)
            #expect(refusing.tui.dragAndDropSession.proposedOperation == .cancel)
            #expect(try corner(refusing, page) == "P")
        }

    #endif

    // MARK: - The three-party model (owner ruling B-BITEMS1-1)

    /// A chip that allows `operations` within the app, three lines above a
    /// zone, both inside a destination when `around`, else the zone alone one.
    private func modelTree(_ configuration: DragConfiguration?, around: Bool) -> some View {
        let zone = Text("ZONE========")
        let chip = Text("CHIP").draggable("apple")
        let column = VStack(alignment: .leading, spacing: 0) {
            if let configuration { chip.dragConfiguration(configuration) } else { chip }
            Text("").frame(height: 3)
            if around { zone } else { zone.dropDestination(for: String.self) { _, _ in } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        return _WindowChromeHost(
            content: Group {
                if around { column.dropDestination(for: String.self) { _, _ in } } else { column }
            })
    }

    private func held(_ page: some View, meta: Bool = false) -> InputChainHarness {
        let harness = InputChainHarness(width: 30, height: 8)
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 4, y: 4, meta: meta))
        harness.frame(page)
        return harness
    }

    @Test("TUI's own dropDestination proposes a copy into another container, and wears +")
    func dropDestinationCopies() {
        let harness = held(modelTree(nil, around: false))
        #expect(harness.tui.dragAndDropSession.active?.targeted != nil, "the drag is over the destination")
        #expect(harness.tui.dragAndDropSession.proposedOperation == .copy)
    }

    @Test("Into the container the drag came from it proposes a move, where the source allows one")
    func moveWithinTheContainer() {
        let moving = held(modelTree(DragConfiguration(allowMove: true), around: true))
        #expect(moving.tui.dragAndDropSession.proposedOperation == .move)
        // The source allows a copy only: the move is a copy.
        let copying = held(modelTree(nil, around: true))
        #expect(copying.tui.dragAndDropSession.proposedOperation == .copy)
    }

    @Test("The pointer's modifier flips a copy to a move and back")
    func modifierFlips() {
        let flipped = held(modelTree(DragConfiguration(allowMove: true), around: true), meta: true)
        #expect(flipped.tui.dragAndDropSession.proposedOperation == .copy)
        let flippedOut = held(modelTree(DragConfiguration(allowMove: true), around: false), meta: true)
        #expect(flippedOut.tui.dragAndDropSession.proposedOperation == .move)
    }

    @Test("A source that allows neither a copy nor a move is forbidden there, and the drop is refused")
    func neitherAllowed() {
        let page = modelTree(
            DragConfiguration(operationsWithinApp: .init(allowCopy: false), operationsOutsideApp: .init()),
            around: false)
        let harness = held(page)
        #expect(harness.tui.dragAndDropSession.proposedOperation == .forbidden)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 4, y: 4))
        #expect(harness.tui.dragAndDropSession.returnFlight != nil, "the drop was refused and the chip flies home")
    }
}
