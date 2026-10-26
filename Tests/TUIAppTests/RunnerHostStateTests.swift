//  🖥️ TUI — A Terminal UI framework for Swift
//  RunnerHostStateTests.swift
//
//  The app runner's own half of the terminal host ledger: what its loop does
//  between frames — the progress bar sent again where it is due, and a wait
//  that ends at the bar's next send with no frame owed — and what its exit
//  writes before leaving the alternate screen, attention asked for on the way
//  out among it. `TerminalProgressTests` and `TerminalAttentionTests` cover the
//  render loop's half; these drive the runner's (`AppRunner.betweenFrames`,
//  `AppRunner.exitFarewell`), whose one caller each is the `while isRunning`
//  loop and its cleanup, which no unit test can reach.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation

/// A page stating a bar at a half.
private struct BarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("working").terminalProgress(.value(0.5)) }
    }
}

@MainActor
@Suite("The run loop's progress keep-alive and the exit's farewell", .serialized)
struct RunnerHostStateTests {
    private static let second: UInt64 = 1_000_000_000

    private static func progress(_ state: Int, _ percent: Int? = nil) -> String {
        "\u{1B}]9;4;\(state)" + (percent.map { ";\($0)" } ?? "") + "\u{1B}\\"
    }

    /// The runner's render-request queue, owned by the test.
    private let appState = AppState()

    /// A runner, and a loop over a mock terminal sharing its context, as
    /// `AppRunner` builds its own; the loop sends the bar, as the runner's does
    /// on a terminal that takes one, and has drawn a frame at one second.
    private func launched(postsNotifications: Bool = false) -> (AppRunner<BarApp>, RenderLoop<BarApp>, MockTerminal) {
        // `Terminal.init()` only reserves a buffer, so this touches no TTY.
        let runner = AppRunner(app: BarApp(), appState: appState)
        runner.tuiContext.terminalFeatures = TerminalFeatures(
            showsProgress: false, postsNotifications: postsNotifications)
        let harness = RenderLoopHarness(tuiContext: runner.tuiContext)
        let loop = harness.loop(BarApp())
        loop.sendsProgressReports = true
        _ = loop.render(frameNowNanos: Int64(Self.second))
        return (runner, loop, harness.terminal)
    }

    @Test("Between frames the loop waits for the bar's next send, owing no frame, and sends it when due")
    func betweenFramesKeepsTheBarUp() {
        let (runner, loop, terminal) = launched()
        let pacer = FramePacer(maxFrameRate: 60, startedAtNanos: 0)
        let written = terminal.writtenOutput.count
        #expect(terminal.writtenOutput.contains(Self.progress(1, 50)), "the frame put the bar up")

        // A second later nothing is due: no write, and the wait runs to the
        // bar's next send, five seconds after the first, where nothing else
        // would wake the loop at all.
        #expect(pacer.waitNanos(now: 2 * Self.second) == nil, "nothing else is pending")
        #expect(runner.betweenFrames(renderer: loop, pacer: pacer, now: 2 * Self.second) == 4 * Self.second)
        #expect(terminal.writtenOutput.count == written)

        // At the send: the bar again, alone, and a wait to the one after.
        #expect(runner.betweenFrames(renderer: loop, pacer: pacer, now: 6 * Self.second) == 5 * Self.second)
        #expect(Array(terminal.writtenOutput.dropFirst(written)) == [Self.progress(1, 50)])
        #expect(!pacer.isRenderPending, "the wake owes no frame")
    }

    @Test("The exit's farewell posts a notification asked for on the way out, then takes the bar down")
    func exitFarewellPostsLateAttention() {
        let (runner, loop, _) = launched(postsNotifications: true)
        runner.tuiContext.terminalBell.requestAttention("Done")
        #expect(runner.exitFarewell(renderer: loop) == "\u{1B}]9;Done\u{1B}\\" + Self.progress(0))
    }

    @Test("The exit's farewell rings the bell for attention asked for on the way out where no notification is posted")
    func exitFarewellRingsForLateAttention() {
        let (runner, loop, _) = launched(postsNotifications: false)
        runner.tuiContext.terminalBell.requestAttention("Done")
        #expect(runner.exitFarewell(renderer: loop) == "\u{07}" + Self.progress(0))
    }
}
