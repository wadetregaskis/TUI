//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTargetBehaviorLifetimeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

private struct PlainScrollApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView { ForEach(0..<30, id: \.self) { Text("line \($0)") } }
        }
    }
}

private struct PagingScrollApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView { ForEach(0..<30, id: \.self) { Text("line \($0)") } }
                .scrollTargetBehavior(.paging)
        }
    }
}

/// A scroll view keeps what its scroll target behaviour reads at event time on
/// its handler, which lives in the state storage. What it keeps must not hold
/// the storage, the render cache or any other of the app's objects: the handler
/// is in the storage, so a reference the other way is a cycle, and the app's
/// whole state and cache outlive it.
@MainActor
@Suite("A scroll target behaviour does not keep the app alive")
struct ScrollTargetBehaviorLifetimeTests {
    /// Weak probes, by name, of the objects a run held.
    private typealias Probes = [(name: String, probe: () -> AnyObject?)]

    /// Runs `app` for two frames through a render loop assembled as `AppRunner`
    /// assembles it, and returns weak probes of its objects with the loop gone.
    private static func runAndRelease<A: App>(_ app: A) -> Probes {
        weak var storage: StateStorage?
        weak var cache: RenderCache?
        weak var focus: FocusManager?
        weak var statusBar: StatusBarState?
        weak var mouse: MouseEventDispatcher?
        weak var keys: KeyEventDispatcher?
        do {
            let harness = RenderLoopHarness()
            storage = harness.tuiContext.stateStorage
            cache = harness.tuiContext.renderCache
            focus = harness.focusManager
            statusBar = harness.statusBar
            mouse = harness.tuiContext.mouseEventDispatcher
            keys = harness.tuiContext.keyEventDispatcher
            let loop = harness.loop(app)
            let timer = CursorTimer(renderNotifier: harness.appState)
            _ = loop.render(cursorTimer: timer)
            _ = loop.render(cursorTimer: timer)
        }
        return [
            ("state storage", { storage }), ("render cache", { cache }), ("focus manager", { focus }),
            ("status bar", { statusBar }), ("mouse dispatcher", { mouse }), ("key dispatcher", { keys }),
        ]
    }

    /// Draws `view` for two frames through a context wired with the runtime
    /// services, and returns weak probes of them with the context gone.
    private static func drawAndRelease<V: View>(_ view: V) -> Probes {
        weak var storage: StateStorage?
        weak var cache: RenderCache?
        weak var focus: FocusManager?
        do {
            let tui = TUIContext()
            let focusManager = FocusManager()
            storage = tui.stateStorage
            cache = tui.renderCache
            focus = focusManager
            for _ in 0..<2 {
                var environment = EnvironmentValues()
                environment.focusManager = focusManager
                environment.applyRuntimeServices(from: tui)
                let context = RenderContext(
                    availableWidth: 20, availableHeight: 5, environment: environment, tuiContext: tui)
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                focusManager.beginRenderPass()
                _ = renderToBuffer(view, context: context)
                focusManager.endRenderPass()
                tui.stateStorage.endRenderPass()
                tui.renderCache.removeInactive()
            }
        }
        return [("state storage", { storage }), ("render cache", { cache }), ("focus manager", { focus })]
    }

    private func expectFreed(_ probes: Probes, _ comment: String) {
        for (name, probe) in probes {
            #expect(probe() == nil, "\(comment): the \(name) outlived its app")
        }
    }

    @Test("An app's objects go with its loop when a scroll view has no behaviour (the control)")
    func loopFreedWithoutABehaviour() {
        expectFreed(Self.runAndRelease(PlainScrollApp()), "no behaviour")
    }

    @Test("An app's objects go with its loop when a scroll view pages")
    func loopFreedWithABehaviour() {
        expectFreed(Self.runAndRelease(PagingScrollApp()), "paging")
    }

    @Test("A context's services go with it when a scroll view pages")
    func contextFreedWithABehaviour() {
        let lines = VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { Text("line \($0)") }
        }
        expectFreed(Self.drawAndRelease(ScrollView { lines }), "no behaviour")
        expectFreed(Self.drawAndRelease(ScrollView { lines }.scrollTargetBehavior(.paging)), "paging")
    }

    @Test("A behaviour still reads the scroll view's own environment")
    func behaviourReadsItsEnvironment() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 5, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(
            ScrollView { ForEach(0..<30, id: \.self) { Text("line \($0)") } }
                .scrollTargetBehavior(.paging)
                .environment(\.horizontalSizeClass, .compact),
            context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        let handler = focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        let kept = handler?.scrollTargeting?.environment
        #expect(kept?.horizontalSizeClass == .compact, "the app's own values are kept")
        #expect(kept?.stateStorage == nil && kept?.renderCache == nil && kept?.focusManager == nil)
    }
}
