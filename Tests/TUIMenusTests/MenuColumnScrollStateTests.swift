//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuColumnScrollStateTests.swift
//
//  An inline menu squeezed short of its rows scrolls inside its border, and
//  given them back stops scrolling. The scroll position belongs to the
//  squeezed drawing: given its rows back the menu drops it, so squeezed again
//  it starts at the top — even where everything under the menu is kept alive,
//  as a cache hit above it keeps it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIApp
@testable import TUIFoundation
import TUIMenus
@testable import TUIView

@MainActor
@Suite("An inline menu's scroll position")
struct MenuColumnScrollStateTests {
    private func page(height: Int) -> some View {
        VStack(spacing: 0) {
            Button("Other") {}.focusID("other")
            Menu("Actions") {
                ForEach(0..<10, id: \.self) { index in
                    Button("item \(index)") {}.focusID("item\(index)")
                }
            }
            .menuStyle(.inline)
        }
        .frame(height: height, alignment: .top)
    }

    /// One frame; `retainingAll` keeps every state under the page alive, as a
    /// memo hit above the menu does for what it serves.
    private func frame(
        height: Int, tui: TUIContext, focus: FocusManager, retainingAll: Bool = false
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 30, environment: environment, tuiContext: tui)
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(page(height: height), context: context)
        if retainingAll { tui.stateStorage.retainSubtree(context.identity) }
        tui.stateStorage.endRenderPass()
        focus.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    @Test("Squeezed again, it starts at the top")
    func squeezedAgainStartsAtTheTop() {
        let tui = TUIContext()
        let focus = FocusManager()
        let fresh = frame(height: 7, tui: tui, focus: focus)
        #expect(fresh.contains { $0.contains("Actio") }, "\(fresh)")

        // Walked to its last item, the squeezed menu scrolls to show it.
        focus.focus(id: "item9")
        _ = frame(height: 7, tui: tui, focus: focus)
        let scrolled = frame(height: 7, tui: tui, focus: focus)
        #expect(scrolled.contains { $0.contains("item 9") }, "\(scrolled)")
        #expect(!scrolled.contains { $0.contains("Actio") }, "\(scrolled)")

        // Its rows given back, and everything under the page kept alive.
        focus.focus(id: "other")
        _ = frame(height: 20, tui: tui, focus: focus, retainingAll: true)

        let again = frame(height: 7, tui: tui, focus: focus)
        #expect(again.contains { $0.contains("Actio") }, "\(again)")
    }
}
