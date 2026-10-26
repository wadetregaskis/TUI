//  🖥️ TUI — A Terminal UI framework for Swift
//  HeadlessInputChannelsTests.swift
//
//  The channels the Stress bench renders with are wired as the render loop
//  wires them, so a bench frame draws what an app's frame draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("Headless input channels")
struct HeadlessInputChannelsTests {

    @Test("StatusBar() drawn in a backdrop reads the app's line from the headless channels, as from the render loop")
    func backdropStatusBarIsTheApps() throws {
        let tuiContext = TUIContext()
        let channels = HeadlessInputChannels()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        channels.install(into: &environment)
        channels.beginWalk()
        let state = try #require(environment.statusBar)
        state.setItemsSilently([StatusBarItem(shortcut: "n", label: "new")])
        let context = RenderContext(
            availableWidth: 40, availableHeight: 1, environment: environment, tuiContext: tuiContext)
        let live = renderToBuffer(StatusBar(), context: context).lines.map(\.stripped)
        #expect(live.contains { $0.contains("new") }, "sanity: the line, drawn live: \(live)")
        // A backdrop swaps the status bar it declares into for a throwaway;
        // the line of key hints is still the app's.
        let backdrop = renderToBuffer(StatusBar(), context: context.isolatedForBackground()).lines.map(\.stripped)
        #expect(backdrop == live, "the app's line, not the throwaway's: \(backdrop)")
    }

    /// The Stress bench's `--cold` shares one set of channels across the fresh
    /// context it makes every frame. What a walk registers with the channels
    /// holds closures over the walk's context — a `List` row's hit-test handler
    /// holds the list's handler and the `RenderContext` — and that context's
    /// environment holds its state storage and render cache. Emptying only the
    /// context's own stores left the last frame's whole render alive in the
    /// channels until the next frame's `beginWalk()` emptied them, inside that
    /// frame's timed region.
    @Test("discard(_:) frees a context whose walk registered with the channels, while the channels live on")
    func discardFreesTheContextFromTheChannels() {
        let channels = HeadlessInputChannels()
        weak var storage: StateStorage?
        weak var cache: RenderCache?
        do {
            var environment = EnvironmentValues()
            channels.install(into: &environment)
            let stateStorage = StateStorage()
            let renderCache = RenderCache(valueHashPlans: .tuikit())
            environment.stateStorage = stateStorage
            environment.renderCache = renderCache
            environment.preferenceStorage = PreferenceStorage()
            let context = RenderContext(availableWidth: 30, availableHeight: 8, environment: environment)
            channels.beginWalk()
            stateStorage.beginRenderPass()
            renderCache.beginRenderPass()
            let list = List(selection: .constant(String?.none)) {
                ForEach(["one", "two", "three"], id: \.self) { Text($0) }
            }
            let drawn = renderToBuffer(list, context: context).lines.map(\.stripped)
            stateStorage.endRenderPass()
            renderCache.removeInactive()
            #expect(drawn.contains { $0.contains("two") }, "sanity: the list was not drawn: \(drawn)")
            #expect(channels.mouseHandlerCount > 0, "sanity: the list registered nothing with the channels")
            channels.discard(context)
            storage = stateStorage
            cache = renderCache
        }
        #expect(storage == nil, "the discarded context's state storage outlived it")
        #expect(cache == nil, "the discarded context's render cache outlived it")
        // The channels outlive the context, as the bench's do: the next frame's
        // context is installed into the same ones.
        withExtendedLifetime(channels) {}
    }
}
