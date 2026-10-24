//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragReduceMotionTests.swift
//
//  Under reduce motion a drag's preview does not travel (owner decision
//  A-D3M-1, 2026-10-05): it is under the cursor from its first frame, and a
//  cancelled or refused drop does not fly home.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Drag and drop under reduce motion")
struct DragReduceMotionTests {

    /// A session with a drag of `source` opened from a press at (2, 3) and the
    /// cursor since moved to (20, 9).
    private func dragging(reducesMotion: Bool, source: ViewIdentity) -> DragAndDropSession {
        let session = DragAndDropSession()
        session.reducesMotion = reducesMotion
        session.beginFrame()
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: 2, y: 3)
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 20, y: 9)
        session.begin(payload: "row", preview: FrameBuffer(lines: ["ROW"]), source: source)
        return session
    }

    @Test("The preview is under the cursor from the first frame, with no lift to drive")
    func noLift() {
        let source = ViewIdentity(path: "row")
        let lifting = dragging(reducesMotion: false, source: source)
        #expect(lifting.liftedPreviewFrame().map { ($0.x, $0.y) } ?? (-1, -1) == (2, 3), "it lifts")

        let session = dragging(reducesMotion: true, source: source)
        #expect(session.liftedPreviewFrame().map { ($0.x, $0.y) } ?? (-1, -1) == (20, 9))
        #expect(!session.driveLift(nowNanos: 0), "no frames are asked for")
    }

    @Test("A cancelled drag does not fly home: the preview goes, and the row is back at once")
    func noFlightHome() {
        let source = ViewIdentity(path: "row")
        let flying = dragging(reducesMotion: false, source: source)
        flying.cancelReturningToOrigin()
        #expect(flying.returnFlight != nil, "it flies")
        #expect(flying.isDragSource(source), "the row waits for its picture")

        let session = dragging(reducesMotion: true, source: source)
        session.cancelReturningToOrigin()
        #expect(session.returnFlight == nil)
        #expect(session.driveReturnFlight(nowNanos: 0) == nil)
        #expect(!session.isDragSource(source), "the row draws again in place")
        #expect(session.active == nil)
    }

    @Test("A refused drop does not fly home either")
    func refusedDropDoesNotFly() {
        let session = dragging(reducesMotion: true, source: ViewIdentity(path: "row"))
        #expect(!session.performDrop(), "nothing is under the cursor to take it")
        #expect(session.returnFlight == nil)
        #expect(session.active == nil)
    }

    @Test("The render loop hands the scene's setting to the session")
    func theLoopWritesTheSetting() {
        let harness = RenderLoopHarness()
        harness.loop(ReducingApp(), accessibility: []).render()
        #expect(harness.tuiContext.dragAndDropSession.reducesMotion, "the scene's .reduceMotion() reached it")
    }
}

private struct ReducingApp: App {
    var body: some Scene {
        WindowGroup { Text("app") }.reduceMotion()
    }
}
