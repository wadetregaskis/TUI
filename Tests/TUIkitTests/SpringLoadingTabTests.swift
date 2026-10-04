//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpringLoadingTabTests.swift
//
//  A tab spring-loads unless told not to: a drag carried out of one tab's
//  content and held still over another tab — its chip in a strip, its row in
//  a sidebar — selects that tab, and the drag carries on into its content.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The tab view's selection.
private final class Selected: @unchecked Sendable {
    var value = 1
}

@MainActor
@Suite("Spring loading a tab view's tabs")
struct SpringLoadingTabTests {
    private static let delay = Int64(DragAndDropSession.SpringLoading.delayNanos)

    /// Two tabs; the first's content is a draggable chip.
    private func tabs(_ selected: Selected, view: SpringLoadingBehavior, tab: SpringLoadingBehavior) -> some View {
        TabView(selection: Binding(get: { selected.value }, set: { selected.value = $0 })) {
            Tab("One", systemImage: "star", value: 1) { Text("CHIP").draggable("apple") }
            Tab("Two", systemImage: "star", value: 2) { Text("second") }
                .springLoadingBehavior(tab)
        }
        .springLoadingBehavior(view)
    }

    /// The same, with the second tab saying nothing of its own.
    private func plainTabs(_ selected: Selected, view: SpringLoadingBehavior) -> some View {
        TabView(selection: Binding(get: { selected.value }, set: { selected.value = $0 })) {
            Tab("One", systemImage: "star", value: 1) { Text("CHIP").draggable("apple") }
            Tab("Two", systemImage: "star", value: 2) { Text("second") }
        }
        .springLoadingBehavior(view)
    }

    /// Where `text` starts on screen, in cells: a tab's symbol before it is two.
    private func cell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
        for (y, line) in buffer.lines.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (String(line[..<range.lowerBound]).strippedLength, y)
            }
        }
        return nil
    }

    /// Carries the chip onto the second tab's label, holds it there for the
    /// delay, and reports which tab is selected after.
    private func pauseOnSecondTab(_ selected: Selected, _ build: () -> some View) -> Int {
        let harness = InputChainHarness(width: 50, height: 12)
        let drawn = harness.frame(build())
        guard let chip = cell(of: "CHIP", in: drawn), let two = cell(of: "Two", in: drawn) else {
            Issue.record("could not find the chip and the tab in \(drawn.lines.map(\.stripped))")
            return -1
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: chip.x, y: chip.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: chip.x + 1, y: chip.y))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: two.x + 1, y: two.y))
        harness.frame(build())
        let session = harness.tui.dragAndDropSession
        _ = session.driveSpringLoading(nowNanos: 0)
        harness.frame(build())
        _ = session.driveSpringLoading(nowNanos: UInt64(Self.delay))
        harness.frame(build())
        #expect(session.active != nil, "the drag is still in the hand")
        return selected.value
    }

    @Test("A tab spring-loads by default: a pause on its chip selects it")
    func automaticTabSpringLoads() {
        let selected = Selected()
        #expect(pauseOnSecondTab(selected) { plainTabs(selected, view: .automatic) } == 2)
    }

    @Test("A tab view told .disabled does not")
    func disabledTabViewDoesNot() {
        let selected = Selected()
        #expect(pauseOnSecondTab(selected) { plainTabs(selected, view: .disabled) } == 1)
    }

    @Test("A tab's own .enabled overrides the tab view's .disabled")
    func tabOverridesTabView() {
        let selected = Selected()
        #expect(pauseOnSecondTab(selected) { tabs(selected, view: .disabled, tab: .enabled) } == 2)
    }

    @Test("A tab's own .disabled overrides the tab view's default")
    func tabDisabledOverridesDefault() {
        let selected = Selected()
        #expect(pauseOnSecondTab(selected) { tabs(selected, view: .automatic, tab: .disabled) } == 1)
    }

    @Test("In a sidebar, a pause on a tab's row selects it")
    func sidebarRowSpringLoads() {
        let selected = Selected()
        let build = { plainTabs(selected, view: .automatic).tabViewStyle(.sidebarAdaptable) }
        #expect(pauseOnSecondTab(selected, build) == 2)
    }
}
