//  🖥️ TUI — A Terminal UI framework for Swift
//  LostReleaseDragTests.swift
//
//  A pointer drag whose release never arrives — the button came up outside
//  the window, a multiplexer ate it — is ended by the next press, as a release
//  over nothing would end it, and the press then does what it would have.
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
@Suite("A drag whose release was lost")
struct LostReleaseDragTests {
    private final class Log {
        var targeted: [Bool] = []
        var dropped: [String] = []
        var clicks = 0
    }

    /// A chip, a drop zone and a button, a line each.
    private func build(_ log: Log) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("seed")
            Text("ZONE====").dropDestination(for: String.self) { values, _ in
                log.dropped += values
                return true
            } isTargeted: { log.targeted.append($0) }
            Button("GO") { log.clicks += 1 }
        }
    }

    /// Where `text` is drawn in `buffer`.
    private func cell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int) {
        for (y, line) in buffer.lines.map(\.stripped).enumerated() {
            if let range = line.range(of: text) { return (line.distance(from: line.startIndex, to: range.lowerBound), y) }
        }
        Issue.record("\(text) not drawn")
        return (0, 0)
    }

    /// Hunt DND-3: a press that supersedes a lost release told nobody, so the
    /// drag stayed in flight for good: the source drawn blank, the zone
    /// targeted, the focus path's keys dead, and nothing but another drag to
    /// end it — a pointer drag answers no cancel key.
    @Test("A press after a lost release ends the drag, untargets the zone, and still clicks")
    func pressEndsTheDrag() {
        let log = Log()
        let harness = InputChainHarness(width: 20, height: 6)
        let session = harness.tui.dragAndDropSession
        harness.frame(build(log))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build(log))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 1))
        harness.frame(build(log))
        #expect(session.active != nil)
        #expect(log.targeted == [true])

        // No release: the next thing heard is a click on the button.
        let go = cell(of: "GO", in: harness.frame(build(log)))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: go.x, y: go.y))
        #expect(session.active == nil, "the press ends the drag")
        #expect(log.targeted == [true, false], "and the zone hears it leave")
        #expect(session.returnFlight != nil, "the picture goes home, as a release over nothing sends it")
        harness.frame(build(log))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: go.x, y: go.y))
        harness.frame(build(log))
        #expect(log.clicks == 1, "the press is the button's, as it would have been")
        #expect(log.dropped.isEmpty)
    }
}
