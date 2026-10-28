//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusSectionIndicatorReachTests.swift
//
//  Which border draws an active focus section's ●: one that encloses the whole
//  section, reached from it through single-child steps. A section with no
//  border of its own over several bordered children used to draw a ● in each
//  of them, every one being the first border on its own way down.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Which border draws a focus section's indicator")
struct FocusSectionIndicatorReachTests {

    /// How many ● the second frame of `view` draws, with section `"s"` active.
    private static func dots(_ view: some View) -> Int {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.mouseEventDispatcher = nil
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(availableWidth: 40, availableHeight: 20, environment: environment, tuiContext: tui)
        var lines: [String] = []
        for _ in 0..<2 {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            focusManager.beginSceneRender()
            lines = renderToBuffer(view, context: context).lines.map(\.stripped)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            focusManager.activateSection(id: "s")
        }
        return lines.reduce(0) { $0 + $1.filter { $0 == "●" }.count }
    }

    @Test("A section with no border of its own draws no ● in its bordered children")
    func siblingsDrawNone() {
        let count = Self.dots(
            HStack {
                Text("a").focusable().border()
                Text("b").border()
            }
            .focusSection("s"))
        #expect(count == 0)
    }

    @Test("Rows of a ForEach in a section draw no ●")
    func forEachRowsDrawNone() {
        let count = Self.dots(
            VStack {
                ForEach(["a", "b"], id: \.self) { name in
                    Text(name).focusable().border()
                }
            }
            .focusSection("s"))
        #expect(count == 0)
    }

    @Test("A border around the whole section draws one ●, through modifiers, and its children none")
    func enclosingBorderDrawsOne() {
        let count = Self.dots(
            VStack {
                Text("a").focusable().border()
                Text("b").border()
            }
            .border()
            .padding(1)
            .focusSection("s"))
        #expect(count == 1)
    }
}
