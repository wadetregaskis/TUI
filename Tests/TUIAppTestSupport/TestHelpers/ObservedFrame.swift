//  🖥️ TUI — A Terminal UI framework for Swift
//  ObservedFrame.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// One frame of `view` through `tui`'s render cache, as the render loop draws
/// it — each pass fenced (preferences, state, the render cache) and a pass
/// tracker installed, which is what turns the per-pass measure memo on — and
/// the screen stripped of styling.
///
/// For the observation tests, which compare what a warm cache draws after an
/// observed write with what a cold one draws: the cache's pass lifecycle is
/// where what it keeps is dropped and what it observed is let go of, so
/// every frame must run it.
@MainActor
func observedFrame<V: View>(_ view: V, tui: TUIContext, width: Int = 40, height: Int = 8) -> [String] {
    var environment = EnvironmentValues()
    environment.applyRuntimeServices(from: tui)
    environment.installVolatileReadTracker(VolatileReadTracker())
    tui.preferences.beginRenderPass()
    tui.stateStorage.beginRenderPass()
    tui.renderCache.beginRenderPass()
    let buffer = renderToBuffer(
        view,
        context: RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui))
    tui.stateStorage.endRenderPass()
    tui.renderCache.removeInactive()
    return buffer.lines.map(\.stripped)
}

#endif
