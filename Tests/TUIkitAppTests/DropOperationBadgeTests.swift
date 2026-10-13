//  🖥️ TUIkit — Terminal UI Kit for Swift
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

import TUIkit
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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
            "A delegate's proposal names the badge",
            arguments: [
                (DropOperation.copy, Character("+")), (.alias, "\u{2197}"), (.forbidden, "\u{2298}"),
                (.move, "P"), (.delete, "P"), (.cancel, "P"),
            ])
        func delegateProposal(operation: DropOperation, glyph: Character) throws {
            let harness = InputChainHarness(width: 30, height: 8)
            let page = tree(Text("ZONE========").onDrop(of: [.text], delegate: Proposing(operation: operation)))
            harness.frame(page)
            hold(harness)
            #expect(harness.tui.dragAndDropSession.proposedOperation == operation)
            #expect(try corner(harness, page) == glyph)
        }

        @Test("A delegate that proposes nothing keeps copy; one that refuses the drag shows no badge")
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
            #expect(refusing.tui.dragAndDropSession.proposedOperation == nil)
            #expect(try corner(refusing, page) == "P")
        }

        @Test("TUIkit's own dropDestination proposes nothing, so wears no badge")
        func dropDestinationShowsNone() throws {
            let harness = InputChainHarness(width: 30, height: 8)
            let page = tree(Text("ZONE========").dropDestination(for: String.self, action: { _, _ in true }, isTargeted: { _ in }))
            harness.frame(page)
            hold(harness)
            #expect(harness.tui.dragAndDropSession.active?.targeted != nil, "the drag is over the destination")
            #expect(harness.tui.dragAndDropSession.proposedOperation == nil)
            #expect(try corner(harness, page) == "P")
        }
    #endif
}
