//  🖥️ TUI — A Terminal UI framework for Swift
//  AppLifetime.swift
//
//  Whether an app's objects go with its render loop: run it, let the loop go,
//  and probe what is left through weak references.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// Weak probes, by name, of the objects a run held.
typealias AppLifetimeProbes = [(name: String, probe: () -> AnyObject?)]

/// Runs apps through a render loop and reports which of their objects outlive it.
@MainActor
enum AppLifetime {
    /// Runs `app` for two frames through a render loop assembled as `AppRunner`
    /// assembles it, and returns weak probes of its objects with the loop gone
    /// — after checking it drew each of `markers`, so a probe cannot pass by
    /// drawing less than it says.
    static func runAndRelease<A: App>(_ app: A, drawing markers: [String] = []) -> AppLifetimeProbes {
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
            let drawn = harness.terminal.writtenOutput.joined()
            for marker in markers {
                #expect(drawn.contains(marker), "the app drew no \"\(marker)\"")
            }
        }
        return [
            ("state storage", { storage }), ("render cache", { cache }), ("focus manager", { focus }),
            ("status bar", { statusBar }), ("mouse dispatcher", { mouse }), ("key dispatcher", { keys }),
        ]
    }

    /// Expects every probe to have been freed.
    static func expectFreed(_ probes: AppLifetimeProbes, _ comment: String) {
        for (name, probe) in probes {
            #expect(probe() == nil, "\(comment): the \(name) outlived its app")
        }
    }
}

#endif
