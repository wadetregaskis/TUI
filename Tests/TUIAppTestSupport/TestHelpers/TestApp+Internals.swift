//  🖥️ TUI — A Terminal UI framework for Swift
//  TestApp+Internals.swift
//
//  What the framework's own tests read and do to a `TestApp` that an app's
//  tests have no call to: frames drawn by hand at chosen instants, events with
//  no frame after them, and the app's insides.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

import Foundation

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITerminalHost
import TUITesting

extension TestApp {
    /// Draws exactly one frame at `nanos`, and nothing more: a test of what
    /// one frame does, where ``TestApp/advance(by:)`` draws what the app asks.
    func frame(atNanos nanos: Int64, date: Date = FrameClock.nowDate) {
        headless.frame(atNanos: nanos, date: date)
    }

    /// Delivers a key and draws nothing, for a test of what the next frame shows.
    /// - Returns: Whether something took it.
    @discardableResult
    func send(_ event: KeyEvent) -> Bool { headless.send(event) }

    /// Delivers a mouse event and draws nothing.
    /// - Returns: Whether something took it.
    @discardableResult
    func send(_ event: MouseEvent) -> Bool { headless.send(event) }

    /// Reports the modifier keys held on their own, and draws nothing.
    /// - Returns: Whether the screen needs a frame to show the change.
    @discardableResult
    func send(_ modifiers: ModifierKeyState) -> Bool { headless.send(modifiers) }

    var framesAsked: Int { headless.framesAsked }
    var quitsRequested: Int { headless.quitsRequested }
    var bytesWritten: Int { headless.bytesWritten }
    var bellsWritten: Int { headless.bellsWritten }
    var cursor: CellPoint? { headless.cursor }
    var renderCache: RenderCache { headless.renderCache }
    var effectSettling: EffectStage.Settling { headless.effectSettling }
    var services: TUIContext { headless.services }
    var scenes: ScenePresenter { headless.scenes }
    var terminalWindowTitle: String? { headless.terminalWindowTitle }
    var hostWrites: [String] { headless.hostWrites }
    var hostStateKeepAliveDeadline: Int64? { headless.hostStateKeepAliveDeadline }
    var departureCount: Int { headless.departureCount }

    var clearsRenderCacheEachFrame: Bool {
        get { headless.clearsRenderCacheEachFrame }
        set { headless.clearsRenderCacheEachFrame = newValue }
    }

    var observationCensus: ObservationCensus? {
        get { headless.observationCensus }
        set { headless.observationCensus = newValue }
    }

    var keyboardReporting: KeyboardReporting {
        get { headless.keyboardReporting }
        set { headless.keyboardReporting = newValue }
    }

    var terminalCapabilities: TerminalCapabilities {
        get { headless.terminalCapabilities }
        set { headless.terminalCapabilities = newValue }
    }

    var sendsProgressReports: Bool {
        get { headless.sendsProgressReports }
        set { headless.sendsProgressReports = newValue }
    }

    func takeFrameRequest() -> Bool { headless.takeFrameRequest() }
    func reportFocus(_ isFocused: Bool) { headless.reportFocus(isFocused) }
    func handBackHostState() { headless.handBackHostState() }
    func keepHostStateAlive(atNanos nanos: Int64) { headless.keepHostStateAlive(atNanos: nanos) }
    func nextWake(after nanos: Int64) -> Int64? { headless.nextWake(after: nanos) }

    /// Changes the terminal's size and draws nothing, for a test of what the
    /// next frame does with it.
    func setSize(width: Int, height: Int) { headless.resize(width: width, height: height) }
}

#endif
