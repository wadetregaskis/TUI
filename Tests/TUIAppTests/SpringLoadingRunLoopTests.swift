//  🖥️ TUI — A Terminal UI framework for Swift
//  SpringLoadingRunLoopTests.swift
//
//  A pointer resting still sends nothing, so the run loop has to be the one
//  that ends a spring-loading pause: the frame the pause starts in asks for a
//  frame at the instant it will have lasted the delay, and that frame presses
//  the control.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// How many times the button was pressed.
private final class Presses: @unchecked Sendable {
    var value = 0
}

/// A draggable chip, and two rows below it a spring-loaded button.
private struct SpringPage: App {
    let presses: Presses

    init() { self.init(presses: Presses()) }

    init(presses: Presses) { self.presses = presses }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                Text("").frame(height: 2)
                Button("GO") { presses.value += 1 }
                    .springLoadingBehavior(.enabled)
            }
        }
        .mouseSupport(.full)
    }
}

@MainActor
@Suite("The run loop ends a spring-loading pause")
struct SpringLoadingRunLoopTests {
    private static let millisecond: Int64 = 1_000_000

    /// Where `text` starts on the screen, in cells.
    private func cell(of text: String, in screen: [String]) -> (x: Int, y: Int)? {
        for (y, line) in screen.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (String(line[..<range.lowerBound]).strippedLength, y)
            }
        }
        return nil
    }

    @Test("The frame a pause starts in asks for one at its end, and that frame presses the button")
    func theLoopEndsThePause() throws {
        let presses = Presses()
        let app = HeadlessApp(SpringPage(presses: presses), width: 30, height: 10)
        app.frame(atNanos: 0)
        let chip = try #require(cell(of: "CHIP", in: app.screen), "\(app.screen.map(\.stripped))")
        let button = try #require(cell(of: "GO", in: app.screen), "\(app.screen.map(\.stripped))")

        app.send(MouseEvent(button: .left, phase: .pressed, x: chip.x, y: chip.y))
        app.send(MouseEvent(button: .left, phase: .dragged, x: chip.x + 1, y: chip.y))
        app.frame(atNanos: 10 * Self.millisecond)
        app.send(MouseEvent(button: .left, phase: .dragged, x: button.x, y: button.y))
        let start = 20 * Self.millisecond
        app.frame(atNanos: start)
        // Past the lift, so the pause's wake is the only thing left to draw for.
        app.frame(atNanos: 300 * Self.millisecond)
        let end = start + Int64(DragAndDropSession.SpringLoading.delayNanos)
        #expect(app.nextWake(after: 300 * Self.millisecond) == end)
        #expect(presses.value == 0)

        app.frame(atNanos: end)
        #expect(presses.value == 1, "the frame at the end of the pause pressed the button")
        // It draws as pressed for a moment as it fires (owner ruling B82), and
        // the frame that ends that is the last one waited for.
        let flashEnd = end + Int64(DragAndDropSession.SpringLoading.firingNanos)
        #expect(app.nextWake(after: end) == flashEnd, "the frame that draws it unpressed")
        app.frame(atNanos: flashEnd)
        #expect(app.nextWake(after: flashEnd) == nil, "and nothing more is waited for")
    }
}
