//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessInputChannelsTests.swift
//
//  The channels the Stress bench renders with are wired as the render loop
//  wires them, so a bench frame draws what an app's frame draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

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
}
