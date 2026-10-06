//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetGrabberTests.swift
//
//  A detented sheet's grabber (`presentationDragIndicator(_:)`): the rule on
//  its top edge that the keys and the pointer move between its detents.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A page under a detented sheet, its detent bound or the sheet's own.
@MainActor
private struct GrabbedSheet: View {
    var isPresented: Binding<Bool> = .constant(true)
    var selection: Binding<PresentationDetent>?
    var detents: Set<PresentationDetent> = [.height(6), .medium, .large]
    var indicator: Visibility = .automatic
    var dismissDisabled = false

    var body: some View {
        VStack {
            Text("PAGE")
            Button("Page") {}.focusID("page-button")
        }
        .sheet(isPresented: isPresented) { content }
    }

    @ViewBuilder private var content: some View {
        if let selection {
            panel.presentationDetents(detents, selection: selection).presentationDragIndicator(indicator)
                .interactiveDismissDisabled(dismissDisabled)
        } else {
            panel.presentationDetents(detents).presentationDragIndicator(indicator)
                .interactiveDismissDisabled(dismissDisabled)
        }
    }

    private var panel: some View {
        Panel("SHEET") { Button("OK") {}.focusID("sheet-ok") }
    }
}

/// A value the test and the view share.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
    var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("Sheet grabber")
struct SheetGrabberTests {
    private static let width = 40
    private static let height = 20

    private func harness() -> InputChainHarness {
        InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = Self.height
        }
    }

    /// A frame, composited as the window does, with the composited regions
    /// live — the sheet's are on its layer until then.
    @discardableResult
    private func frame(_ harness: InputChainHarness, _ view: some View) -> FrameBuffer {
        let root = harness.frame(view)
        let composited = root.compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette)
        harness.tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        return root
    }

    /// The sheet's layer in `root`.
    private func sheet(_ root: FrameBuffer) -> OverlayLayer? {
        root.overlays.first { $0.level == .modal }
    }

    private func isGrabberFocused(_ harness: InputChainHarness) -> Bool {
        harness.focusManager.currentFocusedID?.hasPrefix("sheet-grabber") == true
    }

    // MARK: - Drawn

    @Test("A sheet with two detents or more has a rule on top with a handle, and is its detent's height")
    func drawsTheRule() throws {
        let harness = harness()
        let layer = try #require(sheet(frame(harness, GrabbedSheet())))
        let rows = layer.content.lines.map(\.stripped)
        #expect(rows.count == 6, "the smallest detent, the rule included: \(rows)")
        #expect(rows.first?.allSatisfy { $0 == "─" || $0 == "═" } == true, "\(rows)")
        #expect(rows.first?.contains("═══════") == true, "a seven-cell handle: \(rows)")
        #expect(rows[1].contains("SHEET"), "the panel under the rule: \(rows)")
    }

    @Test("One detent, or the indicator hidden: no rule, no stop, no drag", arguments: [false, true])
    func noGrabber(hidden: Bool) throws {
        let harness = harness()
        let view = GrabbedSheet(detents: hidden ? [.height(6), .large] : [.height(6)], indicator: hidden ? .hidden : .visible)
        let layer = try #require(sheet(frame(harness, view)))
        let rows = layer.content.lines.map(\.stripped)
        #expect(rows.count == 6)
        #expect(!rows.contains { $0.contains("═") }, "\(rows)")
        #expect(layer.content.hitTestRegions.allSatisfy { $0.focusID?.hasPrefix("sheet-grabber") != true })
        harness.press(KeyEvent(key: .tab))
        frame(harness, view)
        #expect(harness.focusManager.currentFocusedID == "sheet-ok", "the only stop in the sheet")
    }

    // MARK: - The keys

    @Test("The grabber follows the sheet's controls in the ring")
    func ringOrder() {
        let harness = harness()
        frame(harness, GrabbedSheet())
        frame(harness, GrabbedSheet())
        #expect(harness.focusManager.currentFocusedID == "sheet-ok", "the content takes the opening focus")
        harness.press(KeyEvent(key: .tab))
        frame(harness, GrabbedSheet())
        #expect(isGrabberFocused(harness))
        harness.press(KeyEvent(key: .tab))
        frame(harness, GrabbedSheet())
        #expect(harness.focusManager.currentFocusedID == "sheet-ok", "round inside the sheet, as a modal does")
    }

    @Test("Up, Down, Home, End, Return and Space move the sheet between its detents")
    func keysMoveTheSheet() throws {
        let harness = harness()
        let view = GrabbedSheet()
        frame(harness, view)
        harness.press(KeyEvent(key: .tab))
        frame(harness, view)
        #expect(isGrabberFocused(harness))

        func height(after key: Key) throws -> Int {
            #expect(harness.press(KeyEvent(key: key)), "the grabber takes \(key)")
            return try #require(sheet(frame(harness, view))).content.height
        }
        #expect(try height(after: .up) == 10)
        #expect(try height(after: .up) == 20)
        #expect(try height(after: .up) == 20, "taken at the top, and nothing moves")
        #expect(try height(after: .down) == 10)
        #expect(try height(after: .home) == 6)
        #expect(try height(after: .end) == 20)
        #expect(try height(after: .enter) == 6, "round to the smallest after the largest")
        #expect(try height(after: .space) == 10)
        #expect(isGrabberFocused(harness), "the focus stays on the grabber as the sheet moves")
    }

    @Test("A step writes the detent to the selection binding")
    func writesTheSelection() throws {
        let harness = harness()
        let detent = Box(PresentationDetent.height(6))
        let view = GrabbedSheet(selection: detent.binding)
        frame(harness, view)
        harness.press(KeyEvent(key: .tab))
        frame(harness, view)
        harness.press(KeyEvent(key: .up))
        #expect(detent.value == .medium)
        #expect(try #require(sheet(frame(harness, view))).content.height == 10)
        harness.press(KeyEvent(key: .end))
        #expect(detent.value == .large)
    }

    @Test("Closed and presented again, an unbound sheet opens at its smallest detent")
    func reopensAtTheSmallest() throws {
        let harness = harness()
        let presented = Box(true)
        let view = GrabbedSheet(isPresented: presented.binding)
        frame(harness, view)
        harness.press(KeyEvent(key: .tab))
        frame(harness, view)
        harness.press(KeyEvent(key: .end))
        #expect(try #require(sheet(frame(harness, view))).content.height == 20)
        presented.value = false
        frame(harness, view)
        presented.value = true
        #expect(try #require(sheet(frame(harness, view))).content.height == 6)
    }

    @Test("Escape on the grabber of a sheet that may not be dismissed by hand does nothing")
    func escapeInertWhenDismissDisabled() throws {
        let harness = harness()
        let presented = Box(true)
        let view = GrabbedSheet(isPresented: presented.binding, dismissDisabled: true)
        frame(harness, view)
        harness.press(KeyEvent(key: .tab))
        frame(harness, view)
        #expect(isGrabberFocused(harness))
        harness.press(KeyEvent(key: .escape))
        frame(harness, view)
        #expect(presented.value)
        #expect(try #require(sheet(frame(harness, view))).content.height == 6)
    }

    // MARK: - The pointer

    @Test("A drag on the rule snaps the sheet to the nearest detent as it goes, and a press focuses it")
    func dragSnaps() throws {
        let harness = harness()
        let view = GrabbedSheet()
        frame(harness, view)
        // The rule is the sheet's top row: 6 rows up from the bottom.
        let rule = Self.height - 6
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 20, y: rule))
        frame(harness, view)
        #expect(isGrabberFocused(harness))
        // Three rows up asks for 9: nearer medium's 10 than 6.
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 20, y: rule - 3))
        #expect(try #require(sheet(frame(harness, view))).content.height == 10)
        // Thirteen up asks for 19: the large detent.
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 20, y: rule - 13))
        #expect(try #require(sheet(frame(harness, view))).content.height == 20)
        // Back down to one row up asks for 7, and it snaps back to the smallest.
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 20, y: rule - 1))
        #expect(try #require(sheet(frame(harness, view))).content.height == 6)
    }

    // MARK: - Ink

    @Test("The handle breathes while the grabber holds the focus, and rests otherwise")
    func handleBreathesWhenFocused() throws {
        let harness = harness()
        let view = GrabbedSheet()
        let resting = try #require(sheet(frame(harness, view)))
        #expect(!resting.content.animatedCells.contains { $0.offsetY == 0 }, "no breath at rest")
        harness.press(KeyEvent(key: .tab))
        frame(harness, view)
        let focused = try #require(sheet(frame(harness, view)))
        #expect(focused.content.animatedCells.contains { $0.offsetY == 0 }, "the handle's breath on the rule")
    }
}
