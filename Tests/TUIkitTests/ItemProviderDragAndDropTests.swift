//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemProviderDragAndDropTests.swift
//
//  SwiftUI's item-provider drag and drop, within the app: onDrag carries a
//  provider, onDrop takes a drag whose providers conform to its types (a
//  TUIkit draggable string counts as text), and a DropDelegate is called in
//  SwiftUI's order — validate, enter, update on each move, then exit or
//  perform — with a cancel or forbidden proposal refusing the drop. Apple
//  platforms only: the payloads are NSItemProviders and the types UTTypes.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import Testing
    import UniformTypeIdentifiers

    import TUIkit
    @testable import TUIkitCore
    @testable import TUIkitFoundation
    @testable import TUIkitTestSupport

    /// What the destination under test was told, in order.
    private final class DropLog: @unchecked Sendable {
        var entries: [String] = []
        var targeted = false
    }

    /// A delegate that logs every call, answers validation with `valid` and
    /// each move with `proposal`.
    @MainActor
    private struct LoggingDelegate: DropDelegate {
        let log: DropLog
        var valid = true
        var proposal: DropProposal?

        func validateDrop(info: DropInfo) -> Bool {
            log.entries.append("validate \(info.location.x),\(info.location.y)")
            return valid
        }
        func dropEntered(info: DropInfo) { log.entries.append("entered") }
        func dropUpdated(info: DropInfo) -> DropProposal? {
            log.entries.append("updated \(info.location.x),\(info.location.y)")
            return proposal
        }
        func dropExited(info: DropInfo) { log.entries.append("exited") }
        func performDrop(info: DropInfo) -> Bool {
            log.entries.append("perform \(info.itemProviders(for: [.text]).count) text")
            return true
        }
    }

    @MainActor
    @Suite("SwiftUI's onDrag, onDrop and DropDelegate")
    struct ItemProviderDragAndDropTests {
        /// A source on row 0 and `zone` on row 4.
        private func tree(_ source: some View, _ zone: some View) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                source
                Text("").frame(height: 3)
                zone
            }
        }

        /// Carries the source from row 0 over the zone at (3, 4) and (4, 4),
        /// and lets go at `release`.
        private func carry(_ harness: InputChainHarness, release: (x: Int, y: Int) = (x: 4, y: 4)) {
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: release.x, y: release.y))
            harness.mouse(MouseEvent(button: .left, phase: .released, x: release.x, y: release.y))
        }

        @Test("onDrag's provider lands in an onDrop of a type it conforms to, which is targeted meanwhile")
        func onDragToOnDrop() {
            let log = DropLog()
            let harness = InputChainHarness(width: 30, height: 8)
            let targeted = Binding(get: { log.targeted }, set: { log.targeted = $0; log.entries.append("targeted \($0)") })
            harness.frame(
                tree(
                    Text("CHIP").onDrag { NSItemProvider(object: "apple" as NSString) },
                    Text("ZONE========").onDrop(of: [.plainText], isTargeted: targeted) { providers in
                        log.entries.append("dropped \(providers.count)")
                        return true
                    }))
            carry(harness)
            #expect(log.entries == ["targeted true", "dropped 1", "targeted false"])
            #expect(harness.tui.dragAndDropSession.returnFlight == nil)
        }

        @Test("A draggable string is text to an onDrop, which hears where it landed")
        func draggableStringIsText() {
            let log = DropLog()
            let harness = InputChainHarness(width: 30, height: 8)
            harness.frame(
                tree(
                    Text("CHIP").draggable("apple"),
                    Text("ZONE========").onDrop(of: [.text], isTargeted: nil) { providers, cell in
                        log.entries.append("dropped \(providers.count) at \(cell.x),\(cell.y)")
                        return true
                    }))
            carry(harness)
            #expect(log.entries == ["dropped 1 at 4,0"])
        }

        @Test("A drag of a type the view does not take is no drop, and goes home")
        func unsupportedType() {
            let log = DropLog()
            let harness = InputChainHarness(width: 30, height: 8)
            let targeted = Binding(get: { log.targeted }, set: { log.targeted = $0; log.entries.append("targeted \($0)") })
            harness.frame(
                tree(
                    Text("CHIP").draggable("apple"),
                    Text("ZONE========").onDrop(of: [.image], isTargeted: targeted) { _ in
                        log.entries.append("dropped")
                        return true
                    }))
            carry(harness)
            #expect(log.entries.isEmpty)
            #expect(harness.tui.dragAndDropSession.returnFlight != nil)
        }

        @Test("A delegate is validated, entered, updated on each move, and performs the drop")
        func delegateOrder() {
            let log = DropLog()
            let harness = InputChainHarness(width: 30, height: 8)
            harness.frame(
                tree(
                    Text("CHIP").draggable("apple"),
                    Text("ZONE========").onDrop(of: [.text], delegate: LoggingDelegate(log: log))))
            carry(harness)
            #expect(log.entries == ["validate 3,0", "entered", "updated 3,0", "updated 4,0", "perform 1 text"])
        }

        @Test("A delegate that does not validate the drop never performs it")
        func delegateRefuses() {
            let log = DropLog()
            let harness = InputChainHarness(width: 30, height: 8)
            harness.frame(
                tree(
                    Text("CHIP").draggable("apple"),
                    Text("ZONE========").onDrop(of: [.text], delegate: LoggingDelegate(log: log, valid: false))))
            carry(harness)
            #expect(log.entries == ["validate 3,0"])
            #expect(harness.tui.dragAndDropSession.returnFlight != nil)
        }

        @Test("A forbidden or cancelling proposal refuses the drop; a move accepts it")
        func proposals() {
            for (operation, performs) in [(DropOperation.forbidden, false), (.cancel, false), (.move, true)] {
                let log = DropLog()
                let harness = InputChainHarness(width: 30, height: 8)
                let delegate = LoggingDelegate(log: log, proposal: DropProposal(operation: operation))
                harness.frame(
                    tree(
                        Text("CHIP").draggable("apple"),
                        Text("ZONE========").onDrop(of: [.text], delegate: delegate)))
                carry(harness)
                #expect(log.entries.contains("perform 1 text") == performs, "\(operation)")
            }
        }

        @Test("A delegate whose drag leaves without dropping hears it exit")
        func delegateExit() {
            let log = DropLog()
            let harness = InputChainHarness(width: 30, height: 8)
            harness.frame(
                tree(
                    Text("CHIP").draggable("apple"),
                    Text("ZONE========").onDrop(of: [.text], delegate: LoggingDelegate(log: log))))
            carry(harness, release: (x: 25, y: 7))
            #expect(log.entries == ["validate 3,0", "entered", "updated 3,0", "exited"])
        }

        @Test("itemProvider's provider is what a drag of the view carries; a nil one starts no drag")
        func itemProvider() {
            for vends in [true, false] {
                let log = DropLog()
                let harness = InputChainHarness(width: 30, height: 8)
                harness.frame(
                    tree(
                        Text("ROW").itemProvider { vends ? NSItemProvider(object: "row" as NSString) : nil },
                        Text("ZONE========").onDrop(of: [.text], isTargeted: nil) { providers in
                            log.entries.append("dropped \(providers.count)")
                            return true
                        }))
                harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
                harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
                #expect((harness.tui.dragAndDropSession.active != nil) == vends, "vends \(vends)")
                harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
                harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
                #expect(log.entries == (vends ? ["dropped 1"] : []), "vends \(vends)")
            }
        }

        @Test("DropOperation and DropProposal read as SwiftUI spells them")
        func values() {
            let proposal = DropProposal(operation: .move)
            #expect(proposal.operation == .move)
            #expect(proposal.operationOutsideApplication == nil)
            let split = DropProposal(withinApplication: .move, outsideApplication: .copy)
            #expect(split.operation == .move)
            #expect(split.operationOutsideApplication == .copy)
            #expect(proposal.debugDescription == "DropProposal(operation: .move)")
            #expect(([.copy, .move] as DropOperation.Set).description == "[.copy, .move]")
            #expect(DropOperation.Set.forbidden.rawValue != DropOperation.Set.alias.rawValue)
        }
    }
#endif
