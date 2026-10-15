//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationDockTests.swift
//
//  The dock ledger: a sheet docked live at the bottom of the content area
//  takes its rows from the page, which the root lays out in the rows above it
//  — at a height known before the walk, from the resolvers last frame posted.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What the probe posts, and the heights the page was laid out at.
@MainActor
private final class DockProbe {
    /// The rows the probe's resolver answers.
    var rows: Int? = 5
    /// Whether the probe posts its resolver at all this frame.
    var posts = true
    /// The height the content was proposed, frame by frame.
    var laidOutHeights: [Int] = []
}

/// A page that fills whatever height it is given with numbered rows, posts a
/// dock resolver (as a live sheet's presenter will), and emits a one-row layer
/// docked at the bottom of the content area (as the sheet will).
private struct DockingPage: View, Renderable {
    let probe: DockProbe

    var body: Never { fatalError("DockingPage renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let height = context.availableHeight
        if !context.isMeasuring {
            probe.laidOutHeights.append(height)
            if probe.posts {
                let probe = self.probe
                context.environment.focusManager?.notePresentationDock(id: "probe", presenter: context.identity) { _ in probe.rows }
            }
        }
        var page = FrameBuffer(lines: (0..<max(0, height)).map { "row \($0)" })
        page.overlays.append(
            .dockedAtBottom(content: FrameBuffer(lines: ["SHEET"]), level: .popover, dimsBackground: false))
        return page
    }
}

private struct DockingApp: App {
    let probe: DockProbe

    init() { probe = DockProbe() }

    init(probe: DockProbe) { self.probe = probe }

    var body: some Scene {
        WindowGroup { DockingPage(probe: probe) }
    }
}

@MainActor
@Suite("The presentation dock")
struct PresentationDockTests {
    private static let frameNanos: Int64 = 16_666_667

    @Test("The page is laid out short by the dock, from the frame after the dock is first posted")
    func pageIsLaidOutAboveTheDock() {
        let probe = DockProbe()
        let app = HeadlessApp(DockingApp(probe: probe), width: 30, height: 20)
        app.frame(atNanos: 0)
        #expect(probe.laidOutHeights.last == 20, "nothing was posted before the first walk")
        app.frame(atNanos: Self.frameNanos)
        #expect(probe.laidOutHeights.last == 15)
        let rows = app.screen.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(rows[14] == "row 14", "\(rows)")
        let dockRows = rows[15...18]
        #expect(dockRows.allSatisfy { $0.isEmpty }, "the dock's rows are the page's no longer: \(rows)")
        #expect(rows[19] == "SHEET", "a layer still clamps to the whole content area: \(rows)")
    }

    @Test("A dock learnt in the walk asks for exactly one more frame")
    func lateDockAsksForOneFrame() {
        let probe = DockProbe()
        let app = HeadlessApp(DockingApp(probe: probe), width: 30, height: 20)
        app.frame(atNanos: 0)
        #expect(app.nextWake(after: 0) != nil, "the frame laid out without the dock asked for none")
        app.frame(atNanos: Self.frameNanos)
        #expect(app.nextWake(after: Self.frameNanos) == nil, "a settled dock asked for another frame")
    }

    /// The point of posting a resolver rather than a height: a key that moves
    /// the sheet between two frames is answered by last frame's resolver, so
    /// the frame after the key is laid out right and nothing is learnt late.
    @Test("A dock that changes between frames is laid out on the next one, with no frame late")
    func resolverAnswersAtTheNextFrame() {
        let probe = DockProbe()
        let app = HeadlessApp(DockingApp(probe: probe), width: 30, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        probe.rows = 8
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(probe.laidOutHeights.last == 12)
        #expect(app.nextWake(after: 2 * Self.frameNanos) == nil)
        probe.rows = nil
        app.frame(atNanos: 3 * Self.frameNanos)
        #expect(probe.laidOutHeights.last == 20, "a resolver answering nil docks nothing")
    }

    @Test("A resolver not posted this frame is dropped the next")
    func unpostedResolverIsDropped() {
        let probe = DockProbe()
        let app = HeadlessApp(DockingApp(probe: probe), width: 30, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(probe.laidOutHeights.last == 15, "precondition: docked")
        probe.posts = false
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(probe.laidOutHeights.last == 15, "last frame's resolver still answers before this walk")
        #expect(app.nextWake(after: 2 * Self.frameNanos) != nil, "the dropped dock asked for no frame")
        app.frame(atNanos: 3 * Self.frameNanos)
        #expect(probe.laidOutHeights.last == 20)
    }

    @Test("A dock is never more than the content area")
    func dockIsClampedToTheContentArea() {
        let probe = DockProbe()
        probe.rows = 50
        let app = HeadlessApp(DockingApp(probe: probe), width: 30, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(probe.laidOutHeights.last == 0)
        #expect(app.screen.count == 20, "the frame is still the terminal's height")
    }
}
