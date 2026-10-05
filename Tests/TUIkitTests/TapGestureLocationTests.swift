//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TapGestureLocationTests.swift
//
//  SwiftUI's two tap spellings: `onTapGesture(count:perform:)` with `count`
//  defaulting to one, so `.onTapGesture { … }` compiles; and
//  `onTapGesture(count:coordinateSpace:perform:)`, whose action is given the
//  location — the release's cell, in the view's own cells or the terminal's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the tap actions under test saw, in order.
private final class TapLog: @unchecked Sendable {
    var entries: [String] = []
}

/// "0123" on the top row; on the second, "ab" and then the tapped "XYZ",
/// which therefore spans columns 2…4 of row 1.
@MainActor
private func page(_ target: some View) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Text("0123")
        HStack(spacing: 0) {
            Text("ab")
            target
        }
    }
}

@MainActor
@Suite("SwiftUI's onTapGesture spellings")
struct TapGestureLocationTests {
    /// A left click at `(x, y)`: the press and its release.
    private func click(_ harness: InputChainHarness, _ x: Int, _ y: Int) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: y))
    }

    @Test("A bare trailing closure is a single tap, count defaulting to one")
    func countDefaultsToOne() {
        let log = TapLog()
        let harness = InputChainHarness()
        let view = { page(Text("XYZ").onTapGesture { log.entries.append("tap") }) }
        harness.frame(view())
        click(harness, 3, 1)
        #expect(log.entries == ["tap"])
    }

    @Test("The location is the release's cell in the view, or the terminal's under .global")
    func location() {
        let log = TapLog()
        let harness = InputChainHarness()
        let view = {
            page(
                Text("XYZ")
                    .onTapGesture { cell in log.entries.append("local \(cell.x),\(cell.y)") }
                    .onTapGesture(coordinateSpace: .global) { cell in
                        log.entries.append("global \(cell.x),\(cell.y)")
                    })
        }
        harness.frame(view())
        click(harness, 3, 1)
        // A tap attached outside another ranks below it, as on macOS 15.8:
        // the inner one takes the click.
        #expect(log.entries == ["local 1,0"])

        log.entries = []
        let outer = {
            page(Text("XYZ").onTapGesture(coordinateSpace: .global) { cell in log.entries.append("global \(cell.x),\(cell.y)") })
        }
        harness.frame(outer())
        click(harness, 4, 1)
        #expect(log.entries == ["global 4,1"])
    }

    @Test("The protocol-typed spaces route as the enum cases do")
    func protocolSpaces() {
        let log = TapLog()
        let harness = InputChainHarness()
        harness.frame(page(Text("XYZ").onTapGesture(coordinateSpace: GlobalCoordinateSpace()) { cell in
            log.entries.append("global \(cell.x),\(cell.y)")
        }))
        click(harness, 3, 1)
        harness.frame(page(Text("XYZ").onTapGesture(coordinateSpace: LocalCoordinateSpace()) { cell in
            log.entries.append("local \(cell.x),\(cell.y)")
        }))
        click(harness, 4, 1)
        #expect(log.entries == ["global 3,1", "local 2,0"])
    }

    /// SwiftUI: a tap gesture inside a disabled view never fires; one attached
    /// outside the disabled scope still does (the 2026-08 audit, #27).
    @Test("A tap inside .disabled(true) never fires; one outside the scope does")
    func disabledScope() {
        let log = TapLog()
        let harness = InputChainHarness()
        harness.frame(page(Text("XYZ").onTapGesture { log.entries.append("inside") }.disabled(true)))
        click(harness, 3, 1)
        #expect(log.entries.isEmpty)

        harness.frame(page(Text("XYZ").disabled(true).onTapGesture { log.entries.append("outside") }))
        click(harness, 3, 1)
        #expect(log.entries == ["outside"])

        log.entries = []
        harness.frame(
            page(
                Text("XYZ")
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("drag") })
                    .disabled(true)))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 3, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 4, y: 1))
        #expect(log.entries.isEmpty, "nor a drag")
    }

    @Test("A located double tap fires on the second click with its location")
    func locatedDoubleTap() {
        let log = TapLog()
        let harness = InputChainHarness()
        let view = { page(Text("XYZ").onTapGesture(count: 2) { cell in log.entries.append("\(cell.x),\(cell.y)") }) }
        harness.frame(view())
        click(harness, 2, 1)
        #expect(log.entries.isEmpty)
        click(harness, 2, 1)
        #expect(log.entries == ["0,0"])
    }
}
