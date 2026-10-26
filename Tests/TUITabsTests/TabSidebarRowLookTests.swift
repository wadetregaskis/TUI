//  🖥️ TUI — A Terminal UI framework for Swift
//  TabSidebarRowLookTests.swift
//
//  A tab view sidebar's row is served from the list's row memo only while its
//  look — what the row draws and does, as far as it can be compared — is
//  unchanged (`_TabRowLook`), and a row whose look cannot say so is drawn
//  afresh by that memo alone, not by every memo around the tab view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITabs
@testable import TUITestSupport
@testable import TUIView

/// What the views did, outside them.
private final class Probe: @unchecked Sendable {
    /// How often the selected tab's content was drawn.
    var renders = 0
    /// The text a tab's label view of the app's own draws.
    var name = "Alpha"
    /// The tab view's selection: the first tab, whose chip is carried.
    var selected = 1
    /// What the drops a tab took said.
    var dropped: [String] = []
}

/// Counts its draws: a tab's content, which a memo around the tab view keeps
/// from being drawn again while it serves.
private struct DrawCounter: View, Renderable, Layoutable {
    let probe: Probe

    var body: Never { fatalError("DrawCounter renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { probe.renders += 1 }
        return FrameBuffer(lines: ["COUNTED"])
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(7, 1)
    }
}

/// A sidebar tab view whose first tab has a label of the app's own or a
/// title, compared by which: an `.equatable()` around it may keep it.
private struct LabelledTabs: View, Equatable {
    let customLabel: Bool
    let probe: Probe

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.customLabel == rhs.customLabel }

    var body: some View {
        let probe = self.probe
        return TabView(selection: .constant(1)) {
            if customLabel {
                Tab(value: 1) { DrawCounter(probe: probe) } label: { Text(verbatim: "Custom") }
            } else {
                Tab("Plain", value: 1) { DrawCounter(probe: probe) }
            }
            Tab("Other", value: 2) { Text("OTHER BODY") }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

@MainActor
@Suite("A tab view sidebar's rows and the memos around them")
struct TabSidebarRowLookTests {
    /// A button the focus rests on, so nothing in the tab view breathes, and
    /// the tab view behind an `.equatable()`.
    private func page(customLabel: Bool, _ probe: Probe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Elsewhere") {}
            LabelledTabs(customLabel: customLabel, probe: probe).equatable()
        }
    }

    /// How often the selected tab's content is drawn over three quiet frames,
    /// once the page has settled.
    private func drawsOnQuietFrames(customLabel: Bool) -> Int {
        let probe = Probe()
        let harness = InputChainHarness(width: 50, height: 12)
        for _ in 0..<3 { harness.frame(page(customLabel: customLabel, probe)) }
        let before = probe.renders
        for _ in 0..<3 { harness.frame(page(customLabel: customLabel, probe)) }
        return probe.renders - before
    }

    /// The sidebar draws a label view of the app's own afresh on every frame,
    /// as its row's look cannot compare it: missed by the row memo, which
    /// keys on that look. It declared a read no memo keys on instead, which
    /// turned every memo around the tab view off as well, on every frame — an
    /// `.equatable()` around it, a row of a loop it is in.
    @Test("A tab's label view of its own does not keep a memo around the tab view from serving it")
    func customLabelLeavesOuterMemosOn() {
        #expect(drawsOnQuietFrames(customLabel: false) == 0, "precondition: the memo serves a titled tab's view")
        #expect(drawsOnQuietFrames(customLabel: true) == 0, "the memo around the tab view drew it afresh")
    }

    /// A label view of the app's own is drawn afresh: what it draws can
    /// change with no change the row's look can see.
    @Test("A sidebar row draws its tab's label view afresh when what the view draws changes")
    func customLabelIsDrawnAfresh() {
        let probe = Probe()
        func view() -> some View {
            TabView(selection: .constant(1)) {
                Tab(value: 1) { Text("FIRST BODY") } label: { Text(verbatim: probe.name) }
                Tab("Other", value: 2) { Text("OTHER BODY") }
            }
            .tabViewStyle(.sidebarAdaptable)
        }
        let harness = InputChainHarness(width: 50, height: 12)
        for _ in 0..<3 { harness.frame(view()) }
        probe.name = "Beta"
        let drawn = harness.frame(view()).lines.map(\.stripped).joined(separator: "\n")
        #expect(drawn.contains("Beta") && !drawn.contains("Alpha"), "\(drawn)")
    }

    /// Where `text` is last drawn on screen, in cells.
    private func lastCell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
        for (y, line) in buffer.lines.map(\.stripped).enumerated().reversed() {
            if let range = line.range(of: text) {
                return (String(line[..<range.lowerBound]).strippedLength, y)
            }
        }
        return nil
    }

    /// Draws `tabs(true)` settled, then `tabs(false)` — what changed between
    /// the two the test's to say — and carries the chip `tabs` draws onto the
    /// last row titled "Untitled", then holds it there, or drops it there.
    private func carryOntoTheLastUntitledRow(drop: Bool, _ tabs: (_ before: Bool) -> some View) {
        let harness = InputChainHarness(width: 50, height: 12)
        for _ in 0..<3 { harness.frame(tabs(true)) }
        harness.frame(tabs(false))
        let drawn = harness.frame(tabs(false))
        guard let chip = lastCell(of: "CHIP", in: drawn), let row = lastCell(of: "Untitled", in: drawn) else {
            Issue.record("no chip or row in \(drawn.lines.map(\.stripped))")
            return
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: chip.x, y: chip.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: chip.x + 1, y: chip.y))
        harness.frame(tabs(false))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: row.x + 1, y: row.y))
        harness.frame(tabs(false))
        if drop {
            harness.mouse(MouseEvent(button: .left, phase: .released, x: row.x + 1, y: row.y))
            harness.frame(tabs(false))
            return
        }
        let session = harness.tui.dragAndDropSession
        _ = session.driveSpringLoading(nowNanos: 0)
        harness.frame(tabs(false))
        _ = session.driveSpringLoading(nowNanos: UInt64(DragAndDropSession.SpringLoading.delayNanos))
        harness.frame(tabs(false))
    }

    /// A row is its place; served from the memo, it replays what it
    /// registered for the tab it held then. With the tab's value left out of
    /// its look, a row whose tab left and whose place another tab took,
    /// looking just the same, kept the leaver's: a pause on it selected a tab
    /// no longer there, and its menu's opener was filed under that one.
    @Test("A pause on a sidebar row selects the tab it holds now, not the one it held")
    func springLoadsTheTabTheRowHolds() {
        let probe = Probe()
        let selection = Binding(get: { probe.selected }, set: { probe.selected = $0 })
        carryOntoTheLastUntitledRow(drop: false) { showsSecond in
            TabView(selection: selection) {
                Tab("Home", value: 1) { Text("CHIP").draggable("apple") }
                if showsSecond { Tab("Untitled", value: 2) { Text("SECOND BODY") } }
                Tab("Untitled", value: 3) { Text("THIRD BODY") }
            }
            .tabViewStyle(.sidebarAdaptable)
        }
        #expect(probe.selected == 3, "the pause selected \(probe.selected)")
    }

    /// A drop's action is a closure of the app's, which a look cannot
    /// compare: the row of a tab that takes drops is drawn afresh, and a drop
    /// on it runs the action its tab has now — not one from a frame when
    /// the tab looked the same.
    @Test("A drop on a sidebar row runs the action its tab has now")
    func dropRunsTheTabsActionNow() {
        let probe = Probe()
        let selection = Binding(get: { probe.selected }, set: { probe.selected = $0 })
        carryOntoTheLastUntitledRow(drop: true) { before in
            // The action names the frame it was made in.
            let made = before ? "before" : "now"
            return TabView(selection: selection) {
                Tab("Home", value: 1) { Text("CHIP").draggable("apple") }
                Tab("Untitled", value: 2) { Text("SECOND BODY") }
                    .dropDestination(for: String.self) { probe.dropped.append("\($0) \(made)") }
            }
            .tabViewStyle(.sidebarAdaptable)
        }
        #expect(probe.dropped == ["[\"apple\"] now"], "\(probe.dropped)")
    }
}
