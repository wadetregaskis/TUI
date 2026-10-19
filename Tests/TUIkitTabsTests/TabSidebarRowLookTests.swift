//  🖥️ TUIkit — Terminal UI Kit for Swift
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

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitTabs
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What the views did, outside them.
private final class Probe: @unchecked Sendable {
    /// How often the selected tab's content was drawn.
    var renders = 0
    /// The text a tab's label view of the app's own draws.
    var name = "Alpha"
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
}
