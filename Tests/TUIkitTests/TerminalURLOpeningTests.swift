//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalURLOpeningTests.swift
//
//  `OpenURLAction`'s system opener runs on the machine the APPLICATION is on.
//  Over ssh that is the server: either headless, where the launch is a silent
//  no-op, or somebody's desktop, where the URL lands in front of a person who
//  did not ask for it. The framework cannot tell which — `SSH_*` is reliable
//  when present and proves nothing when absent, and a multiplexer session
//  outlives the hop that started it — so it declines by default.
//
//  These pin the default and the two ways of changing it. They cannot assert
//  what a browser did, so they assert the DECISION, which is the whole of what
//  this code contributes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The ladder is asked on its inputs, so those tests set nothing. The one test
/// about publication sets the override, which republishes the flag the
/// activation path reads — and while that flag is on, activating a link with
/// the default action in ANY test hands its URL to its context's opener, and
/// reports it opened. (A test's context never has the system's, which only the
/// app's run loop installs, so no browser is launched either way.) So it runs
/// in an exit test, whose child process no other test shares. See
/// `ProcessWideState`. These used to set and restore the override and
/// `TUIKIT_OPEN_URLS` in the shared process, `.serialized`, which kept out
/// only this suite's own tests and other main-actor ones.
@MainActor
@Suite("Opening a URL is off unless something says this machine is the user's")
struct TerminalURLOpeningTests {

    /// The ladder, asked with `TUIKIT_OPEN_URLS` set to `value` or unset.
    private static func answer(override: Bool?, environment value: String?) -> Bool {
        TerminalClient.urlOpeningEnabled(
            override: override, environment: value.map { ["TUIKIT_OPEN_URLS": $0] } ?? [:])
    }

    @Test("The default is off")
    func defaultIsOff() {
        #expect(!Self.answer(override: nil, environment: nil))
    }

    @Test("An app can turn it on, and off again")
    func overrideWins() {
        #expect(Self.answer(override: true, environment: nil))
        #expect(!Self.answer(override: false, environment: nil))
    }

    /// The doc promised this and the code could not deliver it: the `"0"`
    /// arm sat behind the override, where nothing ever reached it.
    @Test("TUIKIT_OPEN_URLS=0 is a kill switch, even against an app that turned it on")
    func environmentZeroWins() {
        #expect(!Self.answer(override: true, environment: "0"))
        #expect(!Self.answer(override: nil, environment: "0"))
    }

    @Test("TUIKIT_OPEN_URLS=1 answers for the user only where the app has not answered")
    func environmentOneIsAnOptIn() {
        #expect(Self.answer(override: nil, environment: "1"))
        #expect(!Self.answer(override: false, environment: "1"))
        #expect(!Self.answer(override: nil, environment: nil))
    }

    /// The published flag is what the activation path actually reads — it is
    /// `nonisolated`, because that path has no actor — so setting the override
    /// and not publishing it would change nothing where it counts.
    ///
    /// An exit test, because the publication is the subject. `TUIKIT_OPEN_URLS`
    /// is cleared first, in the child, so a developer who exported `0` cannot
    /// veto the override being published.
    ///
    /// The ladder's own tests above pose it on arguments, so they cannot see
    /// what the live answer passes it. The last part here can: the process's
    /// own `TUIKIT_OPEN_URLS=0` vetoing the real override, live and published.
    @Test("Setting the override publishes it to the path that reads it")
    func overridePublishes() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("TUIKIT_OPEN_URLS", to: nil)
                ProcessWideState.urlOpeningSupport = true
                #expect(TerminalURLOpening.isEnabled)
                ProcessWideState.urlOpeningSupport = false
                #expect(!TerminalURLOpening.isEnabled)

                ProcessWideState.setEnvironment("TUIKIT_OPEN_URLS", to: "0")
                ProcessWideState.urlOpeningSupport = true
                #expect(!TerminalClient.urlOpeningEnabled, "the process's TUIKIT_OPEN_URLS=0 reaches the ladder")
                #expect(!TerminalURLOpening.isEnabled, "and what is published is its veto")
            }
        }
    }

    /// A handler that does the work itself is NOT gated. What is gated is only
    /// the framework launching a process on the user's behalf; an app that
    /// knows how it wants to open a URL was never the risk.
    ///
    /// The gate is closed in this process — nothing in a test process
    /// publishes it open outside an exit test — and the `#require` checks that
    /// rather than assuming it.
    @Test("A handler that handles the URL itself still runs")
    func customHandlerIsNotGated() throws {
        try #require(!TerminalURLOpening.isEnabled, "the fixture: the system opener is gated")
        let sink = OpenedURL()
        let action = OpenURLAction { sink.url = $0 }
        action(URL(string: "https://swift.org")!)
        #expect(sink.url?.absoluteString == "https://swift.org")
    }

    /// The completion form reports what happened: a handler that handled it
    /// is a yes, one that discarded it a no, and a deferral to the system
    /// opener a no while the gate is closed, because nothing was started.
    @Test("The completion form reports whether the URL could be opened")
    func completionReportsAcceptance() throws {
        try #require(!TerminalURLOpening.isEnabled, "the fixture: the system opener is gated")
        let url = URL(string: "https://swift.org")!
        var answers: [Bool] = []
        OpenURLAction { _ in .handled }(url) { answers.append($0) }
        OpenURLAction { _ in .discarded }(url) { answers.append($0) }
        OpenURLAction { _ in .systemAction(prefersInApp: true) }(url) { answers.append($0) }
        #expect(answers == [true, false, false])
    }

    @Test("Preferring an in-app browser still runs the handler")
    func prefersInAppRunsTheHandler() {
        let sink = OpenedURL()
        OpenURLAction { sink.url = $0 }(URL(string: "https://swift.org")!, prefersInApp: true)
        #expect(sink.url?.absoluteString == "https://swift.org")
    }

    private final class OpenedURL: @unchecked Sendable {
        var url: URL?
    }
}

/// The system opener is injected (`URLOpenerBackend`): only the app's run loop
/// installs the one that launches `open`/`xdg-open`, every other context keeps
/// what it is handed in memory, and an action carries the opener of the
/// environment it was read from to wherever it is called.
@MainActor
@Suite("Opening a URL: the injected opener")
struct URLOpenerBackendTests {
    @Test("A context's opener is in memory unless the app's run loop installs the system's")
    func contextOpenerDefaultsToMemory() {
        #expect(TUIContext().urlOpener is InMemoryURLOpener)
        #expect(TUIContext(urlOpener: SystemURLOpener()).urlOpener is SystemURLOpener)
    }

    /// The one line that lets a running app's links open: the runner builds
    /// its context with this machine's opener. Built with the default instead,
    /// every link in every app would hand its URL to memory and launch nothing,
    /// whatever the setting — and nothing else in the suite would notice.
    @Test("The app's runner gives its context this machine's URL opener")
    func runnerInstallsTheSystemOpener() {
        // `Terminal.init()` only reserves a buffer, so this touches no TTY.
        let runner = AppRunner(app: FocusStillApp(), appState: AppState())
        #expect(runner.tuiContext.urlOpener is SystemURLOpener)
    }

    /// The action is read at render and called from an event handler, where no
    /// environment is in reach — so it must carry the opener itself, a custom
    /// handler's included, since a custom one may defer to the system.
    @Test("An action read from an environment carries that environment's opener, a custom one's too")
    func actionCarriesTheEnvironmentsOpener() {
        let opener = InMemoryURLOpener()
        var environment = EnvironmentValues()
        environment.urlOpener = opener
        #expect(environment.openURL.systemOpener as? InMemoryURLOpener === opener)

        environment.openURL = OpenURLAction { _ in .systemAction }
        #expect(environment.openURL.systemOpener as? InMemoryURLOpener === opener)

        #expect(EnvironmentValues().openURL.systemOpener == nil, "no context, no opener")
    }

    @Test("A context's services publish its opener")
    func servicesPublishTheOpener() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        #expect(environment.urlOpener as? InMemoryURLOpener === tui.urlOpener as? InMemoryURLOpener)
    }

    /// With the gate open — an exit test, because the gate is the process's —
    /// a deferral reaches the context's opener and nothing else: an action
    /// read where no context reached launches nothing at all.
    @Test("With opening on, a deferral reaches the environment's opener, and no opener launches nothing")
    func gateOpenReachesTheOpener() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("TUIKIT_OPEN_URLS", to: nil)
                ProcessWideState.urlOpeningSupport = true
                #expect(TerminalURLOpening.isEnabled)

                let url = URL(string: "https://example.invalid/tuikit-test")!
                let opener = InMemoryURLOpener()
                var environment = EnvironmentValues()
                environment.urlOpener = opener
                var answers: [Bool] = []
                environment.openURL(url) { answers.append($0) }
                #expect(opener.opened == [url])

                EnvironmentValues().openURL(url) { answers.append($0) }
                #expect(answers == [true, false])
                #expect(opener.opened == [url], "the bare environment's action reached no opener")
            }
        }
    }
}
