//  🖥️ TUI — A Terminal UI framework for Swift
//  SpringLoadingDelayTests.swift
//
//  Where `\.springLoadingDelay` comes from (owner ruling B82): the user's
//  `TUIKIT_SPRING_LOADING_DELAY`, the host's own setting where the user is at
//  it, macOS's default half second otherwise — and `.springLoadingDelay(_:)`
//  over all three.
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
@Suite("Spring-loading delay: the user's, the host's, the app's")
struct SpringLoadingDelayTests {
    @Test("TUIKIT_SPRING_LOADING_DELAY is seconds, zero or more; anything else says nothing")
    func userVariable() {
        func asked(_ text: String?) -> Duration? {
            TerminalClient.springLoadingDelayRequested(environment: text.map { ["TUIKIT_SPRING_LOADING_DELAY": $0] } ?? [:])
        }
        #expect(asked("0.3") == .milliseconds(300))
        #expect(asked("1") == .seconds(1))
        #expect(asked("0") == .zero)
        #expect(asked("-1") == nil)
        #expect(asked("soon") == nil)
        #expect(asked("inf") == nil)
        #expect(asked(nil) == nil)
    }

    @Test("macOS's preference is a number of seconds; anything else says nothing")
    func hostPreference() {
        #expect(TerminalClient.springLoadingDelay(preferenceValue: NSNumber(value: 0.5)) == .milliseconds(500))
        #expect(TerminalClient.springLoadingDelay(preferenceValue: NSNumber(value: 1.25)) == .milliseconds(1250))
        #expect(TerminalClient.springLoadingDelay(preferenceValue: "0.8") == .milliseconds(800))
        #expect(TerminalClient.springLoadingDelay(preferenceValue: NSNumber(value: -2)) == nil)
        #expect(TerminalClient.springLoadingDelay(preferenceValue: nil) == nil)
    }

    @Test("A host at its defaults asks for nothing, so its locality is not worth asking")
    func hostDefaultsAskNothing() {
        #expect(!HostSettings().asksForAnything)
        #expect(!HostSettings(springLoadingDelay: .milliseconds(500)).asksForAnything)
        #expect(HostSettings(springLoadingDelay: .seconds(1)).asksForAnything)
        #expect(HostSettings(accessibility: [.reduceMotion]).asksForAnything)
    }

    @Test("At the root: the user's over the host's, the host's over the default, half a second by default")
    func reachesTheRoot() {
        func seen(user: Duration?, host: Duration?) -> Duration? {
            let probe = DelayProbe()
            let loop = RenderLoopHarness().loop(DelayProbeApp(probe: probe), springLoadingDelay: user)
            loop.hostSpringLoadingDelay = host
            loop.render()
            return probe.seen
        }
        #expect(seen(user: nil, host: nil) == .milliseconds(500))
        #expect(seen(user: nil, host: .seconds(1)) == .seconds(1))
        #expect(seen(user: .milliseconds(200), host: .seconds(1)) == .milliseconds(200))
    }

    @Test("The app's .springLoadingDelay(_:) overrides the root for its subtree")
    func modifierOverrides() {
        let probe = DelayProbe()
        let loop = RenderLoopHarness().loop(
            DelayProbeApp(probe: probe, appDelay: .milliseconds(100)), springLoadingDelay: .seconds(2))
        loop.render()
        #expect(probe.seen == .milliseconds(100))
    }
}

@MainActor
private final class DelayProbe {
    var seen: Duration?
}

/// An app whose one view records the spring-loading delay it was drawn under,
/// under `.springLoadingDelay(appDelay)` where that is given.
private struct DelayProbeApp: App {
    let probe: DelayProbe
    let appDelay: Duration?

    init() { self.init(probe: DelayProbe()) }

    init(probe: DelayProbe, appDelay: Duration? = nil) {
        self.probe = probe
        self.appDelay = appDelay
    }

    var body: some Scene {
        WindowGroup {
            if let appDelay {
                DelayReader(probe: probe).springLoadingDelay(appDelay)
            } else {
                DelayReader(probe: probe)
            }
        }
    }
}

private struct DelayReader: View {
    let probe: DelayProbe
    @Environment(\.springLoadingDelay) private var delay

    var body: some View {
        probe.seen = delay
        return Text(verbatim: "probe")
    }
}
