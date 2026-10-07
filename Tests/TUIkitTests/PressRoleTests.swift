//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PressRoleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What a region's handler heard, in order.
final class HeardEvents: @unchecked Sendable {
    var events: [MouseEvent] = []
    var phases: [MousePhase] { events.map(\.phase) }
}

@MainActor
@Suite("Press roles: a press held for a region that acts only on the click")
struct PressRoleTests {
    /// A dispatcher with a background region over 20×10 at (2, 1), and a
    /// control (no role) over 4×1 at (5, 3) inside it.
    struct Fixture {
        let dispatcher = MouseEventDispatcher()
        let background = HeardEvents()
        let control = HeardEvents()

        init(role: PressRole? = .background) {
            dispatcher.setActiveSupport(.full)
            let background = self.background
            let backgroundID = dispatcher.register { event in
                background.events.append(event)
                return event.button == .left
            }
            let control = self.control
            let controlID = dispatcher.register { event in
                control.events.append(event)
                return true
            }
            if let role { dispatcher.pressRoles[backgroundID] = role }
            dispatcher.setRegions([
                HitTestRegion(offsetX: 2, offsetY: 1, width: 20, height: 10, handlerID: backgroundID),
                HitTestRegion(offsetX: 5, offsetY: 3, width: 4, height: 1, handlerID: controlID),
            ])
        }

        func left(_ phase: MousePhase, _ x: Int, _ y: Int) {
            dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: x, y: y))
        }
    }

    @Test("The region hears nothing at the press, and its press and release together at the release")
    func clickArrivesAtTheRelease() {
        let fixture = Fixture()
        fixture.left(.pressed, 12, 6)
        #expect(fixture.background.events.isEmpty)
        fixture.left(.released, 12, 6)
        #expect(fixture.background.phases == [.pressed, .released])
        // In the region's own coordinates.
        #expect(fixture.background.events.map(\.x) == [10, 10])
        #expect(fixture.background.events.map(\.y) == [5, 5])
    }

    @Test("Without a role the region hears its press at once, as before")
    func noRoleUnchanged() {
        let fixture = Fixture(role: nil)
        fixture.left(.pressed, 12, 6)
        #expect(fixture.background.phases == [.pressed])
    }

    @Test("A control inside the region still takes its press at once")
    func controlInsideTakesItsPress() {
        let fixture = Fixture()
        fixture.left(.pressed, 6, 3)
        #expect(fixture.control.phases == [.pressed])
        fixture.left(.released, 6, 3)
        #expect(fixture.control.phases == [.pressed, .released])
        #expect(fixture.background.events.isEmpty)
    }

    /// A Control-press selects nothing, so its drag makes nothing; released
    /// outside the pane it was held for, it is no click. Review round 2 of
    /// the follow-ups: delivered as the pane's click wherever it was
    /// released, a Control-drag into another pane focused the scroll view it
    /// left.
    @Test("A Control-press dragged out of its pane and released there is no click")
    func controlDragOutOfThePaneIsNoClick() {
        let fixture = Fixture()
        func ctrl(_ phase: MousePhase, _ x: Int, _ y: Int) {
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: x, y: y, ctrl: true))
        }
        ctrl(.pressed, 12, 6)
        ctrl(.dragged, 18, 6)
        ctrl(.dragged, 30, 6)
        ctrl(.released, 30, 6)
        #expect(fixture.background.events.isEmpty)
        // Released inside it, after a drag about it, it still is the pane's.
        ctrl(.pressed, 12, 6)
        ctrl(.dragged, 30, 6)
        ctrl(.released, 13, 7)
        #expect(fixture.background.phases == [.pressed, .released])
    }

    @Test("A double-click reaches the region with its count")
    func doubleClickKeepsItsCount() {
        let fixture = Fixture()
        for _ in 0..<2 {
            fixture.left(.pressed, 12, 6)
            fixture.left(.released, 12, 6)
        }
        #expect(fixture.background.events.map(\.clickCount) == [1, 1, 2, 2])
    }

    @Test("The wheel is not held")
    func wheelUnchanged() {
        let fixture = Fixture()
        fixture.dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 12, y: 6))
        #expect(fixture.background.phases == [.scrolled])
    }

    struct ScrollPage: View {
        var body: some View {
            VStack {
                Button("First") {}
                ScrollView {
                    VStack {
                        ForEach(0..<20, id: \.self) { Text("Line \($0)") }
                    }
                }
                .frame(height: 5)
            }
        }
    }

    /// The scroll view's contract — focused by a click on its content — holds
    /// through the held press, and the click still takes the focus from a
    /// button that had it.
    @Test("A click on a scroll view's content still focuses it")
    func scrollViewClickFocuses() throws {
        let harness = InputChainHarness(width: 30, height: 10)
        let page = ScrollPage()
        harness.frame(page)
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains("Line 1") })
        let column = try #require(lines[row].range(of: "Line 1")).lowerBound.utf16Offset(in: lines[row])
        let before = harness.focusManager.currentFocusedID
        let dispatcher = harness.tui.mouseEventDispatcher
        dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        #expect(harness.focusManager.currentFocusedID == before)
        dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: column, y: row))
        harness.frame(page)
        #expect(harness.focusManager.currentFocusedID != before)
        #expect(harness.focusManager.currentFocusedID?.hasPrefix("scrollview") == true)
    }

    /// A Control-click is the secondary click, which passes a scroll view's
    /// background over for a menu around it. With none, the follow-ups'
    /// review found it went nowhere: it falls through to the viewport's
    /// click again, focusing the scroll view, and selects nothing.
    @Test("A Control-click on a scroll view with no menu around it still focuses it")
    func scrollViewControlClickFocuses() throws {
        let harness = InputChainHarness(width: 30, height: 10)
        let page = ScrollPage()
        harness.frame(page)
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains("Line 1") })
        let column = try #require(lines[row].range(of: "Line 1")).lowerBound.utf16Offset(in: lines[row])
        let before = harness.focusManager.currentFocusedID
        let dispatcher = harness.tui.mouseEventDispatcher
        dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: column, y: row, ctrl: true))
        dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: column + 3, y: row, ctrl: true))
        dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: column, y: row, ctrl: true))
        dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: column, y: row, ctrl: true))
        harness.frame(page)
        #expect(harness.focusManager.currentFocusedID != before)
        #expect(harness.focusManager.currentFocusedID?.hasPrefix("scrollview") == true)
        #expect(harness.tui.screenSelection.current == nil)
    }
}
