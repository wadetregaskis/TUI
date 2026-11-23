//  🖥️ TUI — A Terminal UI framework for Swift
//  DisabledDragAndDropTests.swift
//
//  Drag and drop under `.disabled(true)` (hunt H-35, DND-5), as SwiftUI does
//  it (`Tools/SwiftUIProbes/Drags and drops on a disabled view (H-35)`): a
//  drag source the disabled scope covers starts no drag, from the pointer as
//  from the keyboard, and one attached outside it still does; a destination
//  still takes the pointer's drop, the disabled scope around it or not; and a
//  disabled view is no focus stop, though it keeps its place in the ring.
//  A drag carried from the keyboard reaches a disabled destination all the
//  same, without the focus, and Return drops there as the pointer does (owner
//  2026-11-23, H35-DROP (c): a keyboard route or neither).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// What the destination under test was handed, and the buttons pressed.
private final class Dropped: @unchecked Sendable {
    var entries: [String] = []
    var pressed: [String] = []
    var targeted: [Bool] = []
    #if canImport(UniformTypeIdentifiers)
        var providers: [NSItemProvider] = []
    #endif
}

private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

@MainActor
@Suite("Drag and drop under .disabled(true)")
struct DisabledDragAndDropTests {
    /// `source` on row 0 and a drop zone for strings on row 4.
    private func tree(_ dropped: Dropped, _ source: some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            source
            Text("").frame(height: 3)
            Text("ZONE========").dropDestination(for: String.self) { titles, _ in
                dropped.entries.append("\(titles)")
                return true
            }
        }
    }

    /// Presses row 0, drags to the zone at (3, 4), and lets go; answers
    /// whether a drag was under way before the release.
    @discardableResult
    private func carry(_ harness: InputChainHarness) -> Bool {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        let dragging = harness.tui.dragAndDropSession.active != nil
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
        return dragging
    }

    @Test("The pointer starts no drag from a draggable inside .disabled(true)")
    func disabledDraggable() {
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 8)
        harness.frame(tree(dropped, Text("CHIP").draggable("apple").disabled(true)))
        #expect(!carry(harness))
        #expect(dropped.entries.isEmpty)
    }

    #if canImport(UniformTypeIdentifiers)
        @Test("The pointer starts no drag from an onDrag inside .disabled(true)")
        func disabledOnDrag() {
            let dropped = Dropped()
            let harness = InputChainHarness(width: 30, height: 8)
            harness.frame(
                tree(dropped, Text("CHIP").onDrag { NSItemProvider(object: "apple" as NSString) }.disabled(true)))
            #expect(!carry(harness))
            #expect(dropped.entries.isEmpty)
        }
    #endif

    @Test("A draggable attached outside .disabled(true) still drags, as SwiftUI's does")
    func disabledOutsideStillDrags() {
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 8)
        harness.frame(tree(dropped, Text("CHIP").disabled(true).draggable("apple")))
        #expect(carry(harness))
        #expect(dropped.entries == ["[\"apple\"]"])
    }

    @Test("A destination inside .disabled(true) still takes the pointer's drop, as SwiftUI's does")
    func disabledDestinationTakesThePointersDrop() {
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 8)
        harness.frame(
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                Text("").frame(height: 3)
                Text("ZONE========").dropDestination(for: String.self) { titles, _ in
                    dropped.entries.append("\(titles)")
                    return true
                }
                .disabled(true)
            })
        #expect(carry(harness))
        #expect(dropped.entries == ["[\"apple\"]"])
    }

    @Test("A disabled draggable and destination are no stops: Ctrl-R picks nothing up and Tab reaches neither")
    func disabledIsNoStop() {
        let log = Dropped()
        let harness = InputChainHarness()
        let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) {
            VStack {
                Text("card").draggable("ace").disabled(true)
                Text("bin").dropDestination(for: String.self) { _, _ in true }.disabled(true)
                Button("only") { log.pressed.append("only") }
            }
        }
        #expect(consumed.first == false, "nothing to pick up")
        #expect(harness.tui.dragAndDropSession.active == nil)
        #expect(log.pressed == ["only"], "Tab from the button wraps to it again: \(log.pressed)")
    }

    @Test("A focused draggable that becomes disabled hands the focus to its neighbour in the ring")
    func disablingHandsTheFocusOn() {
        let log = Dropped()
        let harness = InputChainHarness()
        let board = {
            VStack {
                Button("first") { log.pressed.append("first") }
                Text("card").draggable("ace").disabled(!log.pressed.isEmpty)
                Button("last") { log.pressed.append("last") }
            }
        }
        harness.play([KeyEvent(key: .tab)], board)
        let card = harness.focusManager.currentFocusedID
        #expect(card?.hasPrefix("draggable-") == true, "\(card ?? "nil")")
        log.pressed = ["disable"]
        harness.play([KeyEvent(key: .enter)], board)
        #expect(harness.focusManager.currentFocusedID != card)
        #expect(log.pressed == ["disable", "last"], "the focus went to the card's next stop: \(log.pressed)")
    }

    // MARK: - A carry to a disabled destination (owner 2026-11-23, H35-DROP (c))

    /// A card, a button, and a disabled bin for strings, down the page.
    private func disabledBin(_ log: Dropped) -> some View {
        VStack(alignment: .leading) {
            Text("card").draggable("ace")
            Button("other") { log.pressed.append("other") }
            Text("bin").dropDestination(for: String.self) { titles, _ in
                log.entries.append("\(titles)")
                return true
            } isTargeted: {
                log.targeted.append($0)
            }
            .disabled(true)
        }
    }

    @Test("A carry reaches a disabled dropDestination without focusing it, and Return drops there")
    func carryDropsOnADisabledDestination() {
        let log = Dropped()
        let harness = InputChainHarness()
        harness.play([pickUp]) { disabledBin(log) }
        let card = harness.focusManager.currentFocusedID
        #expect(card?.hasPrefix("draggable-") == true, "\(card ?? "nil")")
        #expect(harness.tui.dragAndDropSession.carryCues.count == 1, "the bin is marked as a place to go")
        let consumed = harness.play([KeyEvent(key: .tab)]) { disabledBin(log) }
        #expect(consumed == [true])
        #expect(harness.focusManager.currentFocusedID == card, "the bin takes no focus; it waits at the card")
        #expect(log.targeted == [true], "the bin is targeted, as under the pointer")
        #expect(harness.tui.dragAndDropSession.carryLabels?.returnKey != nil, "Return says it drops")
        harness.play([KeyEvent(key: .enter)]) { disabledBin(log) }
        #expect(log.entries == ["[\"ace\"]"])
        #expect(log.pressed.isEmpty, "the button between them was passed over")
        #expect(harness.tui.dragAndDropSession.active == nil)
        #expect(harness.focusManager.currentFocusedID == card, "the focus stays where it waited")
    }

    @Test("Escape at a disabled destination puts the carry back, dropping nothing")
    func escapeAtADisabledDestination() {
        let log = Dropped()
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .escape)]) { disabledBin(log) }
        #expect(log.entries.isEmpty)
        #expect(harness.tui.dragAndDropSession.active == nil)
        #expect(harness.focusManager.currentFocusedID?.hasPrefix("draggable-") == true)
    }

    @Test("Tab from a disabled destination goes on round the carry's stops, to the card")
    func tabOnFromADisabledDestination() {
        let log = Dropped()
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .tab)]) { disabledBin(log) }
        let session = harness.tui.dragAndDropSession
        #expect(session.carryLabels?.returnKey == session.carryLabels?.escape, "home: Return puts it back")
        harness.play([KeyEvent(key: .enter)]) { disabledBin(log) }
        #expect(log.entries.isEmpty)
        #expect(log.targeted == [true, false])
    }

    @Test("Outside a carry, Tab still passes a disabled destination by")
    func tabOutsideACarrySkipsADisabledDestination() {
        let log = Dropped()
        let harness = InputChainHarness()
        var visited: [String] = []
        for _ in 0..<4 {
            harness.play([KeyEvent(key: .tab)]) { disabledBin(log) }
            visited.append(harness.focusManager.currentFocusedID ?? "nil")
        }
        #expect(!visited.contains { $0.hasPrefix("dropdestination-") }, "\(visited)")
        #expect(log.targeted.isEmpty)
    }

    #if canImport(UniformTypeIdentifiers)
        @Test("A carry reaches a disabled onDrop, and Return drops the onDrag's provider there")
        func carryDropsOnADisabledOnDrop() {
            let log = Dropped()
            let provider = NSItemProvider(object: "ace" as NSString)
            let harness = InputChainHarness()
            let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) {
                VStack(alignment: .leading) {
                    Text("card").onDrag { provider }
                    Button("other") { log.pressed.append("other") }
                    Text("bin").onDrop(of: [.text], isTargeted: nil) { providers in
                        log.providers += providers
                        return true
                    }
                    .disabled(true)
                }
            }
            #expect(consumed == [true, true, true])
            #expect(log.providers.count == 1 && log.providers.first === provider, "\(log.providers)")
            #expect(log.pressed.isEmpty)
            #expect(harness.tui.dragAndDropSession.active == nil)
        }
    #endif
}
