//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalProgressTests.swift
//
//  A view's `.terminalProgress(_:)` (the Ghostty adoption study, C3): sent as
//  `OSC 9 ; 4` to a terminal that draws a progress bar, on a change, and again
//  between frames when it has gone five seconds unsent; never to one that
//  does not; taken down on the hand-back. And `\.terminalFeatures`, which
//  tells a view which it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation

// MARK: - Fixtures

/// What the fixtures' views state, changed between frames by a test.
@MainActor
private final class ProgressScript {
    var outer: TerminalProgress?
    var inner: TerminalProgress?
    var sibling: TerminalProgress?
}

private struct ProgressApp: App {
    let script: ProgressScript
    init() { script = ProgressScript() }
    init(_ script: ProgressScript) { self.script = script }

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("inner").terminalProgress(script.inner)
                Text("sibling").terminalProgress(script.sibling)
            }
            .terminalProgress(script.outer)
        }
        WindowGroup(id: "plain") { Text("plain window") }
    }
}

/// Says what `\.terminalFeatures` tells it.
private struct FeaturesReader: View {
    @Environment(\.terminalFeatures) private var features
    var body: some View { Text(features.showsProgress ? "shows progress" : "shows none") }
}

private struct FeaturesApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { FeaturesReader() }
    }
}

// MARK: - Tests

@MainActor
@Suite("A view's progress on the terminal's tab", .serialized)
struct TerminalProgressTests {
    private var now: Int64 = 0
    private static let second: Int64 = 1_000_000_000

    private static func progress(_ state: Int, _ percent: Int? = nil) -> String {
        "\u{1B}]9;4;\(state)" + (percent.map { ";\($0)" } ?? "") + "\u{1B}\\"
    }

    private mutating func launched<A: App>(_ app: A, showsProgress: Bool = true) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: 40, height: 8)
        headless.services.terminalFeatures = TerminalFeatures(showsProgress: showsProgress)
        frame(headless)
        return headless
    }

    private mutating func frame<A: App>(_ app: HeadlessApp<A>, after nanos: Int64 = 20_000_000) {
        now += nanos
        app.frame(atNanos: now)
    }

    @Test("A view's progress is sent once, and frames that leave it as it is send nothing")
    mutating func sentOnce() {
        let script = ProgressScript()
        script.outer = .value(0.5)
        let app = launched(ProgressApp(script))
        frame(app)
        frame(app)
        #expect(app.hostWrites == [Self.progress(1, 50)])
    }

    @Test("A terminal that draws no progress bar is sent nothing")
    mutating func notSentWhereNotShown() {
        let script = ProgressScript()
        script.outer = .value(0.5)
        let app = launched(ProgressApp(script), showsProgress: false)
        frame(app, after: 6 * Self.second)
        app.keepHostStateAlive(atNanos: now + 6 * Self.second)
        #expect(app.hostWrites.isEmpty)
        #expect(app.hostStateKeepAliveDeadline == nil)
    }

    @Test("A change is sent, and no view stating progress any more takes the bar down")
    mutating func changesAndRemoval() {
        let script = ProgressScript()
        script.outer = .value(0.25)
        let app = launched(ProgressApp(script))
        script.outer = .error(nil)
        frame(app)
        script.outer = nil
        frame(app)
        frame(app)
        #expect(app.hostWrites == [Self.progress(1, 25), Self.progress(2), Self.progress(0)])
    }

    @Test("The last view drawn wins, and a view stating none leaves another's standing")
    mutating func lastDrawnWins() {
        let script = ProgressScript()
        script.outer = .value(0.1)
        script.inner = .value(0.2)
        script.sibling = .value(0.3)
        let app = launched(ProgressApp(script))
        script.sibling = nil
        frame(app)
        script.inner = nil
        frame(app)
        #expect(app.hostWrites == [Self.progress(1, 30), Self.progress(1, 20), Self.progress(1, 10)])
    }

    @Test("A bar gone five seconds unsent is sent again between frames, with no frame drawn for it")
    mutating func keptAliveBetweenFrames() {
        let script = ProgressScript()
        script.outer = .indeterminate
        let app = launched(ProgressApp(script))
        let sent = now
        #expect(app.hostStateKeepAliveDeadline == sent + 5 * Self.second)
        let bytes = app.bytesWritten
        app.keepHostStateAlive(atNanos: sent + 5 * Self.second - 1)
        #expect(app.bytesWritten == bytes)
        app.keepHostStateAlive(atNanos: sent + 5 * Self.second)
        #expect(app.hostWrites == [Self.progress(3), Self.progress(3)])
        #expect(app.bytesWritten == bytes + Self.progress(3).utf8.count, "the bar and nothing else")
        #expect(app.hostStateKeepAliveDeadline == sent + 10 * Self.second)
    }

    @Test("A frame drawn when the bar is due sends it again with the frame")
    mutating func keptAliveByAFrame() {
        let script = ProgressScript()
        script.outer = .paused(0.4)
        let app = launched(ProgressApp(script))
        frame(app, after: 5 * Self.second)
        #expect(app.hostWrites == [Self.progress(4, 40), Self.progress(4, 40)])
    }

    @Test("Handing the terminal back takes the bar down, and the next frame puts it up again")
    mutating func handBack() {
        let script = ProgressScript()
        script.outer = .value(1)
        let app = launched(ProgressApp(script))
        app.handBackHostState()
        #expect(app.hostStateKeepAliveDeadline == nil)
        frame(app)
        #expect(app.hostWrites == [Self.progress(1, 100), Self.progress(0), Self.progress(1, 100)])
    }

    @Test("A window held behind the one in front still states its progress")
    mutating func heldWindowStates() {
        let script = ProgressScript()
        script.outer = .value(0.5)
        let app = launched(ProgressApp(script))
        app.scenes.open(WindowTarget(id: "plain"))
        frame(app)
        frame(app)
        #expect(app.screen.map(\.stripped).joined().contains("plain window"))
        #expect(app.hostWrites == [Self.progress(1, 50)])
    }

    @Test("`\\.terminalFeatures` tells a view whether the terminal shows progress")
    mutating func featuresReachViews() {
        let showing = launched(FeaturesApp())
        #expect(showing.screen.map(\.stripped).joined().contains("shows progress"))
        let none = launched(FeaturesApp(), showsProgress: false)
        #expect(none.screen.map(\.stripped).joined().contains("shows none"))
    }
}
