//  🖥️ TUI — A Terminal UI framework for Swift
//  DropTargetReshapeTests.swift
//
//  A held drag whose pointer does not move while the page moves under it: the
//  destination it is over is the one drawn there now, as each frame's regions
//  are published, not the one it was over when it last moved.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Drop targets under a still pointer")
struct DropTargetReshapeTests {
    private final class Log {
        var targeted: [Int: Bool] = [:]
    }

    /// A chip, over three one-line drop zones in a two-line scroll view.
    private func build(_ log: Log) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("seed")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<3, id: \.self) { zone in
                        Text("ZONE\(zone)").dropDestination(for: String.self) { _, _ in
                            true
                        } isTargeted: { log.targeted[zone] = $0 }
                    }
                }
            }
            .frame(height: 2)
        }
    }

    /// Hunt DND-2: only a drag report moved the target, and a pointer held
    /// still sends none, which is the one way to auto-scroll. The zone that
    /// scrolled away stayed targeted and the one now under the pointer was not.
    @Test("A zone scrolled under a still pointer is targeted, and the one scrolled away is not")
    func targetFollowsTheScroll() {
        let log = Log()
        let harness = InputChainHarness(width: 20, height: 6)
        harness.frame(build(log))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build(log))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 1))
        let over = harness.frame(build(log))
        #expect(over.lines[1].stripped.hasPrefix("ZONE0"))
        #expect(log.targeted == [0: true])

        // The mid-drag navigator scrolls the view under the pointer, and
        // nothing reports the pointer.
        #expect(harness.press(KeyEvent(key: .down)))
        let scrolled = harness.frame(build(log))
        #expect(scrolled.lines[1].stripped.hasPrefix("ZONE1"), "\(scrolled.lines.map(\.stripped))")
        #expect(log.targeted == [0: false, 1: true])
    }
}
