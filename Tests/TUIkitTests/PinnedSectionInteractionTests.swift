//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PinnedSectionInteractionTests.swift
//
//  A pinned section header is interacted with where it is drawn: a click on
//  it reaches its control and not the row it covers, and a control in it that
//  takes a key does not scroll the view back to where the flow drew it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What the test's buttons record, and the scroll position it moves.
private final class PressLog: @unchecked Sendable {
    var pressed: [String] = []
    var position = ScrollPosition()
}

/// Ten sections of six button rows under a header — a button, or with
/// `textHeaders` a text that takes no click — in a scroll view eight lines
/// tall.
private struct ButtonSections: View {
    let log: PressLog
    let pinnedViews: PinnedScrollableViews
    var textHeaders = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pinnedViews) {
                ForEach(0..<10, id: \.self) { section in
                    Section {
                        ForEach(0..<6, id: \.self) { row in
                            Button("row \(section).\(row)") { log.pressed.append("row \(section).\(row)") }
                        }
                    } header: {
                        if textHeaders {
                            Text("Header \(section)")
                        } else {
                            Button("Header \(section)") { log.pressed.append("Header \(section)") }
                        }
                    }
                }
            }
        }
        .scrollPosition(Binding(get: { log.position }, set: { log.position = $0 }))
        .frame(height: 8)
    }
}

/// Renders frames of a view as the render loop does, with a focus manager and
/// a mouse dispatcher whose regions are the frame's.
@MainActor
private final class Frames {
    let tui = TUIContext()
    let focusManager = FocusManager()
    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

    init() { tui.mouseEventDispatcher.setActiveSupport(.full) }

    @discardableResult
    func frame(_ view: some View) -> FrameBuffer {
        dispatcher.beginRenderPass()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.mouseEventDispatcher = dispatcher
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    func click(x: Int, y: Int) {
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
    }
}

/// The screen's lines, styling stripped.
private func screen(_ buffer: FrameBuffer) -> [String] {
    buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
}

@MainActor
@Suite("A pinned section header is interacted with where it is drawn")
struct PinnedSectionInteractionTests {
    /// Scrolled three lines into the first section: rows 0.0 to 0.2 are above
    /// the top edge, and the header pinned there covers row 0.2.
    private func scrolledIntoTheFirstSection(
        _ pinnedViews: PinnedScrollableViews, textHeaders: Bool = false
    ) -> (PressLog, ButtonSections, Frames, FrameBuffer) {
        let log = PressLog()
        let view = ButtonSections(log: log, pinnedViews: pinnedViews, textHeaders: textHeaders)
        let frames = Frames()
        frames.frame(view)
        log.position.scrollTo(y: 3)
        frames.frame(view)
        return (log, view, frames, frames.frame(view))
    }

    @Test("A click on a pinned header presses its control, not the row it covers")
    func clickReachesThePinnedHeader() throws {
        let (log, view, frames, drawn) = scrolledIntoTheFirstSection(.sectionHeaders)
        let lines = screen(drawn)
        try #require(lines.first?.contains("Header 0") == true, "the header is pinned: \(lines)")
        #expect(lines.dropFirst().first?.contains("row 0.3") == true, "under it, row 0.3: \(lines)")
        frames.click(x: 3, y: 0)
        frames.frame(view)
        #expect(log.pressed == ["Header 0"])

        // Unpinned, the same click presses the row drawn there.
        let (twinLog, twinView, twinFrames, twinDrawn) = scrolledIntoTheFirstSection([])
        try #require(screen(twinDrawn).first?.contains("row 0.2") == true)
        twinFrames.click(x: 3, y: 0)
        twinFrames.frame(twinView)
        #expect(twinLog.pressed == ["row 0.2"])
    }

    @Test("A pinned header that takes no click still covers the row under it")
    func pinnedHeaderCoversTheRowsClicks() throws {
        // The row is not drawn there, so it cannot be what a click there
        // presses — even where the header has no control of its own to win.
        let (log, view, frames, drawn) = scrolledIntoTheFirstSection(.sectionHeaders, textHeaders: true)
        try #require(screen(drawn).first?.hasPrefix("Header 0") == true, "\(screen(drawn))")
        frames.click(x: 3, y: 0)
        frames.click(x: 3, y: 1)
        frames.frame(view)
        #expect(log.pressed == ["row 0.3"], "only the row drawn on line 1 is pressed")
    }

    @Test("A key taken by a control in a pinned header does not scroll back to the section's top")
    func keyInThePinnedHeaderKeepsThePlace() throws {
        let (log, view, frames, drawn) = scrolledIntoTheFirstSection(.sectionHeaders)
        let headerID = try #require(
            drawn.hitTestRegions.last { $0.offsetY == 0 && $0.focusID != nil }?.focusID,
            "the pinned header's control is found at the top edge")
        frames.focusManager.focus(id: headerID)
        frames.frame(view)
        // The reveal that follows a key the focused control took finds the
        // control where it is drawn — at the top edge, on screen — and leaves
        // the view where it is. Looked for where the flow drew it, it would
        // scroll back to the section's top.
        _ = frames.focusManager.dispatchKeyEvent(KeyEvent(key: .space))
        let after = screen(frames.frame(view))
        #expect(log.pressed == ["Header 0"])
        #expect(after.first?.contains("Header 0") == true, "\(after)")
        #expect(after.dropFirst().first?.contains("row 0.3") == true, "the view stayed put: \(after)")
    }

    @Test("Turning pinning on and off redraws the sections the stack keeps")
    func togglingPinningRedraws() {
        // Sections of plain text, so a row's value memo can keep what it drew:
        // drawn pinned, a section carries its header's copy, and served from
        // the memo after pinning is turned off it would still be pinned.
        let log = PressLog()
        let frames = Frames()
        frames.frame(TextSections(log: log, pinnedViews: []))
        log.position.scrollTo(y: 3)
        for pinnedViews: PinnedScrollableViews in [[], .sectionHeaders, [], .sectionHeaders, []] {
            let view = TextSections(log: log, pinnedViews: pinnedViews)
            frames.frame(view)
            let top = screen(frames.frame(view)).first ?? ""
            #expect(
                top.hasPrefix(pinnedViews.isEmpty ? "row 0.2 " : "Header 0 "),
                "pinned \(pinnedViews.rawValue): \(top)")
        }
    }
}

/// Twenty sections of six text rows, in a scroll view eight lines tall.
private struct TextSections: View {
    let log: PressLog
    let pinnedViews: PinnedScrollableViews

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pinnedViews) {
                ForEach(0..<20, id: \.self) { section in
                    Section("Header \(section)") {
                        Text("row \(section).0")
                        Text("row \(section).1")
                        Text("row \(section).2")
                        Text("row \(section).3")
                        Text("row \(section).4")
                        Text("row \(section).5")
                    }
                }
            }
        }
        .scrollPosition(Binding(get: { log.position }, set: { log.position = $0 }))
        .frame(height: 8)
    }
}
