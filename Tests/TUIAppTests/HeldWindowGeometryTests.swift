//  🖥️ TUI — A Terminal UI framework for Swift
//  HeldWindowGeometryTests.swift
//
//  A frame asks the terminal its cell geometry once — each half is an `ioctl`
//  on a real one — whether it draws one window or holds one behind another,
//  and a window held behind another draws with that geometry all the same.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation

// MARK: - Fixtures

/// What the main window's view read of the terminal, each time it drew.
@MainActor
private enum GeometryProbe {
    static var seen: [String] = []
}

/// Records the cell aspect and the terminal's size it is drawn with.
private struct GeometryReader: View {
    @Environment(\.imageCellAspect) private var aspect
    @Environment(\.terminalWidth) private var width

    var body: some View {
        GeometryProbe.seen.append("\(aspect) \(width)")
        return Text("main window")
    }
}

private struct GeometryApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { GeometryReader() }
        Window("Other", id: "other") { Text("other window") }
    }
}

// MARK: - Tests

@MainActor
@Suite("The terminal's geometry with windows held behind another", .serialized)
struct HeldWindowGeometryTests {
    @Test("A frame of one window asks the terminal its cell geometry once")
    func oneWindowAsksOnce() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(GeometryApp())
        loop.render()
        let before = harness.terminal.cellGeometryReads
        loop.render()
        #expect(harness.terminal.cellGeometryReads - before == 2, "the aspect and the pixels, once each")
    }

    @Test("A frame holding a window behind another asks once too, and the held window draws with the geometry")
    func heldWindowAsksOnce() {
        let harness = RenderLoopHarness()
        harness.terminal.reportedCellAspect = 2.5
        harness.terminal.size = (70, 20)
        let loop = harness.loop(GeometryApp())
        loop.render()
        loop.scenes.open(WindowTarget(id: "other"))
        GeometryProbe.seen = []
        let before = harness.terminal.cellGeometryReads
        loop.render()
        #expect(loop.scenes.holdsWindows, "precondition: the main window is held behind the other")
        #expect(harness.terminal.cellGeometryReads - before == 2, "the aspect and the pixels, once each")
        #expect(!GeometryProbe.seen.isEmpty, "precondition: the held window drew")
        #expect(Set(GeometryProbe.seen) == ["2.5 70"], "the held window drew with the terminal's geometry")
    }
}
