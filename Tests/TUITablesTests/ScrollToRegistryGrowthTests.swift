//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollToRegistryGrowthTests.swift
//
//  A ScrollViewReader's registry outlives the scroll views it has seen: each
//  registers under its identity path, and the entry used to go only when a
//  `scrollTo` swept it. A reader whose scroll views come and go — one per row
//  of churning data — with a proxy never called kept every one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// Captures the registry the reader hands its content, through its proxy.
private final class RegistryBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}

@MainActor
@Suite("ScrollViewReader registry growth")
struct ScrollToRegistryGrowthTests {

    /// One frame of the real loop's bracketing (`RenderLoop.beginRenderPass`,
    /// `beginSceneRender`, `endRenderPass`, and the window chrome's drag
    /// session frame): every registry that would otherwise go on holding the
    /// scroll views drawn earlier is emptied as it is live, so a handler lives
    /// exactly as long as its view. Leave out the drag session's and the
    /// auto-scroll zones it holds keep every handler alive.
    private func renderFrame(_ view: some View, tuiContext: TUIContext, focusManager: FocusManager) {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 12, environment: environment, tuiContext: tuiContext)
        focusManager.beginRenderPass()
        tuiContext.lifecycle.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.mouseEventDispatcher.beginRenderPass()
        tuiContext.keyboardShortcuts.beginRenderPass()
        tuiContext.dragAndDropSession.beginFrame()
        tuiContext.preferences.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    /// Three small scroll views, one per element of `ids`.
    private func makeView(ids: [Int], box: RegistryBox) -> some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy  // swiftlint:disable:this redundant_discardable_let
            VStack(spacing: 0) {
                ForEach(ids, id: \.self) { id in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<6, id: \.self) { row in Text(verbatim: "\(id).\(row)") }
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }

    @Test("Scroll views that left the tree are swept without a scrollTo")
    func churningScrollViewsStayBounded() throws {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = RegistryBox()
        for frame in 0..<200 {
            renderFrame(
                makeView(ids: [frame * 3, frame * 3 + 1, frame * 3 + 2], box: box),
                tuiContext: tuiContext, focusManager: focusManager)
        }
        let registry = try #require(box.proxy?.registry)
        // 600 scroll views have come and gone, three at a time.
        #expect(
            registry.entryCount <= ScrollToRegistry.minimumSweepThreshold,
            "kept \(registry.entryCount) entries")
    }

    @Test("A sweep keeps the scroll views still alive")
    func sweepKeepsTheLive() {
        let registry = ScrollToRegistry()
        let live = ScrollViewHandler(focusID: "sv-live")
        registry.register(handler: live, identity: ViewIdentity(path: "Root/live"), renderCache: nil)
        for index in 0..<1_000 {
            // Registered, then gone with the frame that drew it.
            let gone = ScrollViewHandler(focusID: "sv-\(index)")
            registry.register(handler: gone, identity: ViewIdentity(path: "Root/\(index)"), renderCache: nil)
        }
        #expect(registry.entryCount < ScrollToRegistry.minimumSweepThreshold, "kept \(registry.entryCount)")

        registry.scrollTo(key: "7", anchor: .top)
        #expect(live.pendingScrollTo == ScrollToRequest(key: "7", anchor: .top), "the live one is still reached")
    }
}
