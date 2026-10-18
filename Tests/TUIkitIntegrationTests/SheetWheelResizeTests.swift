//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetWheelResizeTests.swift
//
//  `presentationContentInteraction(_:)`: what the wheel does over a detented
//  sheet with a grabber — scroll its content, resize it first, or resize it
//  once its content can scroll no further.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A page under a detented sheet whose content scrolls, or does not.
@MainActor
private struct WheelSheet: View {
    var interaction: PresentationContentInteraction
    var scrolls = true
    var pressed: PressCount?
    /// How many rows the content scrolls through.
    var rows = 12

    var body: some View {
        Text("PAGE").sheet(isPresented: .constant(true)) {
            Panel("SHEET") { content }
                .presentationDetents([.height(6), .medium, .large])
                .presentationContentInteraction(interaction)
        }
    }

    @ViewBuilder private var content: some View {
        if scrolls {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { Text("row \($0)") }
                }
            }
            // The wheel chains to the sheet the moment the content is at its
            // end, rather than after the grace a nested scroller holds blocked
            // ticks for (two seconds of real time, which the test's clock does
            // not drive).
            .scrollChainingDelay(.zero)
        } else {
            Button("OK") { pressed?.count += 1 }
                .onHover { pressed?.hovering = $0 }
        }
    }
}

@MainActor
private final class PressCount {
    var count = 0
    var hovering = false
}

@MainActor
@Suite("A sheet's wheel resize")
struct SheetWheelResizeTests {
    private static let width = 40
    private static let height = 20

    private func harness() -> InputChainHarness {
        InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = Self.height
        }
    }

    /// A frame, composited, with the composited regions live.
    @discardableResult
    private func frame(_ harness: InputChainHarness, _ view: some View) -> Int {
        let root = harness.frame(view)
        let composited = root.compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette)
        harness.tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        return root.overlays.first { $0.level == .modal }?.content.height ?? 0
    }

    /// A wheel tick on the sheet's bottom content row, a third of a second
    /// after the last, and the sheet's height after it.
    private func wheel(
        _ button: MouseButton, _ harness: InputChainHarness, _ view: some View, sameInstant: Bool = false
    ) -> Int {
        if !sameInstant { harness.now += 300_000_000 }
        harness.mouse(MouseEvent(button: button, phase: .scrolled, x: Self.width / 2, y: Self.height - 3))
        return frame(harness, view)
    }

    @Test("Under .resizes the wheel grows the sheet before its content scrolls")
    func resizesFirst() {
        let harness = harness()
        let view = WheelSheet(interaction: .resizes)
        #expect(frame(harness, view) == 6)
        #expect(wheel(.scrollDown, harness, view) == 10)
        #expect(wheel(.scrollDown, harness, view) == 20)
        #expect(wheel(.scrollDown, harness, view) == 20, "at the largest the content scrolls")
    }

    @Test("Under .scrolls the wheel scrolls the content first, and grows the sheet at its end")
    func scrollsFirst() {
        let harness = harness()
        let view = WheelSheet(interaction: .scrolls)
        #expect(frame(harness, view) == 6)
        #expect(wheel(.scrollDown, harness, view) == 6, "the content scrolls")
        var height = 6
        for _ in 0..<12 where height == 6 { height = wheel(.scrollDown, harness, view) }
        #expect(height == 10, "at the content's end the sheet grows")
        // Pushed up: the content scrolls back to its top, then the sheet
        // shrinks.
        height = wheel(.scrollUp, harness, view)
        #expect(height == 10, "the content scrolls back first")
        for _ in 0..<12 where height == 10 { height = wheel(.scrollUp, harness, view) }
        #expect(height == 6)
    }

    @Test("Under .scrolls content that does not scroll lets the wheel resize the sheet")
    func scrollsWithNothingToScroll() {
        let harness = harness()
        let view = WheelSheet(interaction: .scrolls, scrolls: false)
        frame(harness, view)
        #expect(wheel(.scrollDown, harness, view) == 10)
        #expect(wheel(.scrollUp, harness, view) == 6)
    }

    @Test("Under .automatic the wheel never resizes the sheet")
    func automaticOnlyScrolls() {
        let harness = harness()
        for scrolls in [true, false] {
            let view = WheelSheet(interaction: .automatic, scrolls: scrolls)
            frame(harness, view)
            for _ in 0..<10 { #expect(wheel(.scrollDown, harness, view) == 6, "scrolls: \(scrolls)") }
        }
    }

    @Test("A burst of eight wheel ticks moves the sheet one detent")
    func burstMovesOneDetent() {
        let harness = harness()
        let view = WheelSheet(interaction: .resizes)
        frame(harness, view)
        harness.now += 300_000_000
        var height = 0
        for _ in 0..<8 { height = wheel(.scrollDown, harness, view, sameInstant: true) }
        #expect(height == 10)
        // A quarter of a second later, the next detent.
        harness.now += 250_000_000
        #expect(wheel(.scrollDown, harness, view, sameInstant: true) == 20)
    }

    /// The burst's first tick reaches the largest detent, and the sheet can
    /// go no further: the rest of it was declined, and scrolled the content
    /// by seven ticks, where the docs promise the ticks in between are spent.
    @Test("A burst that reaches the largest detent spends the rest of itself on the sheet, not the content")
    func burstIntoTheLargestDoesNotScroll() throws {
        let harness = harness()
        let view = WheelSheet(interaction: .resizes, rows: 60)
        #expect(frame(harness, view) == 6)
        #expect(wheel(.scrollDown, harness, view) == 10)
        harness.now += 300_000_000
        var height = 0
        for _ in 0..<8 { height = wheel(.scrollDown, harness, view, sameInstant: true) }
        #expect(height == 20)
        let screen = harness.frame(view).compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette)
        let rows = screen.lines.map(\.stripped)
        #expect(rows.contains { $0.contains("row 0 ") }, "the content scrolled: \(rows)")
    }

    @Test("The wheel's regions take nothing else: the hover and a click in a .resizes sheet reach its button")
    func clicksPassTheWheelRegions() throws {
        let harness = harness()
        let pressed = PressCount()
        let view = WheelSheet(interaction: .resizes, scrolls: false, pressed: pressed)
        let screen = harness.frame(view).compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette)
        frame(harness, view)
        let rows = screen.lines.map(\.stripped)
        let row = try #require(rows.lastIndex { $0.contains("OK") }, "\(rows)")
        let column = try #require(rows[row].range(of: "OK")).lowerBound.utf16Offset(in: rows[row])
        harness.mouse(MouseEvent(button: .none, phase: .moved, x: column, y: row))
        #expect(pressed.hovering, "the hover reaches what is under the wheel's region")
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        frame(harness, view)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: column, y: row))
        frame(harness, view)
        #expect(pressed.count == 1, "\(rows)")
    }
}
