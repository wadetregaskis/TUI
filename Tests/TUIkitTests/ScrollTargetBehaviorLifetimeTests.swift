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

/// Paging scroll views in the places that hand closures and objects down the
/// environment: a navigation stack (its `dismiss`, which holds the stack's
/// coordinator) and a presented sheet (its own `dismiss`).
///
/// No `Menu` or `Button`: whether those go with the loop is
/// `ControlLifetimeTests`' question (a `Button` used to keep the focus
/// manager, the status bar and the mouse dispatcher alive, with or without a
/// behaviour), apart from this suite's.
private struct PagingInPresentationsApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView { ForEach(0..<30, id: \.self) { Text("line \($0)") } }
                    .sheet(isPresented: .constant(true)) {
                        ScrollView { ForEach(0..<30, id: \.self) { Text("sheet \($0)") } }
                            .frame(height: 5)
                    }
            }
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
    private typealias Probes = AppLifetimeProbes

    private static func runAndRelease<A: App>(_ app: A, drawing markers: [String] = []) -> Probes {
        AppLifetime.runAndRelease(app, drawing: markers)
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
        AppLifetime.expectFreed(probes, comment)
    }

    @Test("An app's objects go with its loop when a scroll view has no behaviour (the control)")
    func loopFreedWithoutABehaviour() {
        expectFreed(Self.runAndRelease(PlainScrollApp()), "no behaviour")
    }

    @Test("An app's objects go with its loop when a scroll view pages")
    func loopFreedWithABehaviour() {
        expectFreed(Self.runAndRelease(PagingScrollApp()), "paging")
    }

    @Test("An app's objects go with its loop when scroll views page in a navigation stack and a sheet")
    func loopFreedWithBehavioursInPresentations() {
        expectFreed(
            Self.runAndRelease(PagingInPresentationsApp(), drawing: ["line 0", "sheet 0"]),
            "paging in presentations")
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
