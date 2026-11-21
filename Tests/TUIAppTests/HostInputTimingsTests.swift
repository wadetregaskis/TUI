//  🖥️ TUI — A Terminal UI framework for Swift
//  HostInputTimingsTests.swift
//
//  The host's double-click speed and text cursor blink: read from Windows,
//  counted where the user is at the machine, and written at the root.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

@MainActor
@Suite("Host input timings")
struct HostInputTimingsTests {
    @Test("Windows's answers map to timings: INFINITE is no blink, and 0 says nothing")
    func windowsAnswers() {
        let read = TerminalClient.windowsInputTimings(doubleClickMilliseconds:caretBlinkMilliseconds:)
        #expect(read(500, 530) == HostInputTimings(
            doubleClickInterval: .milliseconds(500), textCursorBlinkHalf: .milliseconds(530), textCursorBlinks: true))
        #expect(read(500, .max) == HostInputTimings(doubleClickInterval: .milliseconds(500), textCursorBlinks: false))
        #expect(read(0, 0) == HostInputTimings())
    }

    @Test("A host's timings at TUI's own ask nothing; Windows's defaults do")
    func asksForTimings() {
        #expect(!HostSettings(inputTimings: HostInputTimings(
            doubleClickInterval: .milliseconds(400), textCursorBlinkHalf: .milliseconds(350), textCursorBlinks: true)
        ).asksForAnything)
        #expect(HostSettings(inputTimings: HostInputTimings(doubleClickInterval: .milliseconds(500))).asksForAnything)
        #expect(HostSettings(inputTimings: HostInputTimings(textCursorBlinkHalf: .milliseconds(530))).asksForAnything)
        #expect(HostSettings(inputTimings: HostInputTimings(textCursorBlinks: false)).asksForAnything)
    }

    @Test("At the root, the host's blink is the text cursor's speed, and no blink stills it")
    func reachesTheRoot() {
        func seen(half: Duration?, blinks: Bool?) -> (rate: Double, blinks: Bool) {
            let probe = CursorProbe()
            let loop = RenderLoopHarness().loop(CursorProbeApp(probe: probe))
            loop.hostTextCursorBlinkHalf = half
            loop.hostTextCursorBlinks = blinks
            loop.render()
            return (probe.speed?.rate ?? 0, probe.blinks ?? true)
        }
        #expect(seen(half: nil, blinks: nil) == (1, true))
        let windows = seen(half: .milliseconds(530), blinks: true)
        #expect(abs(windows.rate - 350.0 / 530.0) < 1e-9 && windows.blinks)
        #expect(seen(half: nil, blinks: false).blinks == false)
    }
}

@MainActor
private final class CursorProbe {
    var speed: IndicatorAnimationSpeed?
    var blinks: Bool?
}

/// An app whose one view records the text cursor's speed and blinking it was
/// drawn under.
private struct CursorProbeApp: App {
    let probe: CursorProbe

    init() { self.init(probe: CursorProbe()) }

    init(probe: CursorProbe) { self.probe = probe }

    var body: some Scene {
        WindowGroup { CursorReader(probe: probe) }
    }
}

private struct CursorReader: View {
    let probe: CursorProbe
    @Environment(\.indicatorAnimationSpeeds) private var speeds
    @Environment(\.textCursorBlinks) private var blinks

    var body: some View {
        probe.speed = speeds.speed(for: .textCursor)
        probe.blinks = blinks
        return Text(verbatim: "probe")
    }
}
