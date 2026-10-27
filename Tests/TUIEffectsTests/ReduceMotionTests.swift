//  🖥️ TUI — A Terminal UI framework for Swift
//  ReduceMotionTests.swift
//
//  `\.accessibilityReduceMotion`: where it comes from — the user's
//  `TUI_REDUCE_MOTION`, the app's `Scene.reduceMotion(_:)` — and what follows
//  it: a transition with motion plays as a fade.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIEffects
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

/// A view that comes and goes, in a slot that survives it — two cells of
/// content in a slot six wide, so a picture moved inside the slot shows.
private struct Host: View {
    let showing: Bool
    let transition: AnyTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showing {
                Text("XX").frame(width: 6, alignment: .leading).transition(transition)
            }
            Text("------")
        }
    }
}

/// A transition of the app's own that indents its view four cells away from
/// rest — motion, by the default properties.
private struct Indent: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.padding(.leading, phase.isIdentity ? 0 : 4)
    }
}

/// The same, saying it has no motion.
private struct StillIndent: Transition {
    static let properties = TransitionProperties(hasMotion: false)

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.padding(.leading, phase.isIdentity ? 0 : 4)
    }
}

@MainActor
@Suite("Reduce motion")
struct ReduceMotionTests {

    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 8, height: 6)

        init(reducesMotion: Bool) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: .linear(duration: 1))
            context.environment.accessibilityReduceMotion = reducesMotion
        }

        func draw(_ showing: Bool, _ transition: AnyTransition, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(
                Host(showing: showing, transition: transition), context: context
            ).lines.map(\.stripped)
        }

        /// The first row halfway through an arrival under `transition`.
        func halfway(_ transition: AnyTransition) -> String {
            _ = draw(false, transition, atMillis: 0)
            _ = draw(true, transition, atMillis: 0)
            return draw(true, transition, atMillis: 500)[0]
        }
    }

    @Test("A transition with motion plays as a fade where motion is reduced")
    func motionBecomesAFade() {
        #expect(!Screen(reducesMotion: false).halfway(.move(edge: .trailing)).hasPrefix("XX"), "it moves")
        // A fade draws the view where it rests, in a colour part-way there.
        #expect(Screen(reducesMotion: true).halfway(.move(edge: .trailing)).hasPrefix("XX"))
        #expect(!Screen(reducesMotion: false).halfway(.scale(scale: 0, anchor: .trailing)).hasPrefix("XX"))
        #expect(Screen(reducesMotion: true).halfway(.scale(scale: 0, anchor: .trailing)).hasPrefix("XX"))
    }

    @Test("A transition of the app's own follows what its properties say")
    func customTransitionsFollowTheirProperties() {
        #expect(Screen(reducesMotion: false).halfway(AnyTransition(Indent())).hasPrefix(" "), "it moves")
        #expect(Screen(reducesMotion: true).halfway(AnyTransition(Indent())).hasPrefix("XX"), "a fade instead")
        #expect(Screen(reducesMotion: true).halfway(AnyTransition(StillIndent())).hasPrefix(" "), "no motion, kept")
    }

    @Test("Motion is the move, offset and scale effects, at either end, or a body that says so")
    func whatHasMotion() {
        #expect(!AnyTransition.opacity.hasMotion)
        #expect(!AnyTransition.identity.hasMotion)
        #expect(AnyTransition.move(edge: .top).hasMotion)
        #expect(AnyTransition.offset(x: 1, y: 0).hasMotion)
        #expect(AnyTransition.opacity.combined(with: .slide).hasMotion)
        #expect(AnyTransition.asymmetric(insertion: .opacity, removal: .move(edge: .top)).hasMotion)
        #expect(AnyTransition(Indent()).hasMotion)
        #expect(!AnyTransition(StillIndent()).hasMotion)
        #expect(AnyTransition(StillIndent()).combined(with: .move(edge: .top)).hasMotion)
    }

    @Test("The fade keeps the transition's own animation")
    func fadeKeepsTheAnimation() {
        var environment = EnvironmentValues()
        environment.accessibilityReduceMotion = true
        let slow = AnyTransition.move(edge: .top).animation(.linear(duration: 3))
        let reduced = slow.reducingMotion(in: environment)
        #expect(!reduced.hasMotion)
        #expect(reduced.insertionAnimation == slow.insertionAnimation)
        #expect(reduced.removalAnimation == slow.removalAnimation)
    }

    @Test("The user asks with TUI_REDUCE_MOTION=1, and nothing else asks")
    func environmentVariable() {
        #expect(TerminalClient.reduceMotionRequested(environment: ["TUI_REDUCE_MOTION": "1"]))
        #expect(!TerminalClient.reduceMotionRequested(environment: ["TUI_REDUCE_MOTION": "0"]))
        #expect(!TerminalClient.reduceMotionRequested(environment: [:]))
    }

    /// The review's failing input: with `TUI_REDUCE_MOTION=1` exported in
    /// the shell that ran the tests, every `HeadlessApp` played its moves as
    /// fades, because the loop read the process's environment itself. Only
    /// the app runner reads it now, and hands it to its loop.
    @Test("A headless app and a test's loop draw as if TUI_REDUCE_MOTION were unset, wherever they run")
    func headlessLoopsIgnoreTheProcess() {
        let headlessProbe = ReduceMotionProbe()
        let headless = HeadlessApp(ReduceMotionProbeApp(probe: headlessProbe), width: 20, height: 4)
        headless.frame(atNanos: 0)
        #expect(headlessProbe.seen == false)

        let loopProbe = ReduceMotionProbe()
        RenderLoopHarness().loop(ReduceMotionProbeApp(probe: loopProbe)).render()
        #expect(loopProbe.seen == false)
    }

    @Test("The user's TUI_REDUCE_MOTION=1, as the app runner reads it, reaches the root, and the scene cannot turn it off")
    func userSettingReachesTheRoot() {
        let asked = TerminalClient.accessibilityRequested(environment: ["TUI_REDUCE_MOTION": "1"])
        #expect(asked == [.reduceMotion])
        let probe = ReduceMotionProbe()
        RenderLoopHarness().loop(ReduceMotionProbeApp(probe: probe), accessibility: asked).render()
        #expect(probe.seen == true)

        let declining = ReduceMotionProbe()
        RenderLoopHarness().loop(ReduceMotionProbeApp(probe: declining, appReduces: false), accessibility: asked)
            .render()
        #expect(declining.seen == true, "the user's ask stands over the scene's false")
    }

    @Test("The app's scene turns it on, and never off")
    func sceneSetting() {
        func root(_ scene: some Scene, userAsked: Bool) -> Bool {
            var environment = EnvironmentValues()
            environment.accessibilityReduceMotion = userAsked
            scene.sceneConfiguration.applyEnvironmentWrites(to: &environment)
            return environment.accessibilityReduceMotion
        }
        #expect(root(WindowGroup { Text("app") }.reduceMotion(), userAsked: false))
        #expect(!root(WindowGroup { Text("app") }.reduceMotion(false), userAsked: false))
        #expect(root(WindowGroup { Text("app") }.reduceMotion(false), userAsked: true), "the user's ask stands")
        #expect(!root(WindowGroup { Text("app") }, userAsked: false))
    }
}

/// What the last frame's root environment said about reduce motion.
@MainActor
private final class ReduceMotionProbe {
    var seen: Bool?
}

/// An app whose one view records whether it was drawn reducing motion, its
/// scene saying `.reduceMotion(appReduces)` where that is given.
private struct ReduceMotionProbeApp: App {
    let probe: ReduceMotionProbe
    let appReduces: Bool?

    init() { self.init(probe: ReduceMotionProbe()) }

    init(probe: ReduceMotionProbe, appReduces: Bool? = nil) {
        self.probe = probe
        self.appReduces = appReduces
    }

    var body: some Scene {
        WindowGroup { ReduceMotionReader(probe: probe) }
            .reduceMotion(appReduces ?? false)
    }
}

private struct ReduceMotionReader: View {
    let probe: ReduceMotionProbe
    @Environment(\.accessibilityReduceMotion) private var reduces

    var body: some View {
        probe.seen = reduces
        return Text(verbatim: "probe")
    }
}

// MARK: - The host's setting

/// A test's stand-in for the host: what it says, how often it was asked, and
/// what the refresher passed on. Written by a reading off the main actor and
/// read by the test once the refresher has settled, never at the same time.
private final class HostStandIn: @unchecked Sendable {
    var reduces = false
    var readings = 0
    var changes: [Bool] = []

    func read() -> HostSettings {
        readings += 1
        return HostSettings(accessibility: reduces ? [.reduceMotion] : [])
    }
}

@MainActor
@Suite("Reduce motion: the host's setting")
struct HostReduceMotionTests {
    private func refresher(
        _ host: HostStandIn, onChange: @escaping @MainActor (HostSettings) -> Void = { _ in }
    ) -> HostSettingsRefresher {
        HostSettingsRefresher(
            read: { host.read() },
            onChange: { settings in
                host.changes.append(settings.accessibility.contains(.reduceMotion))
                onChange(settings)
            })
    }

    /// Waits for the refresher's reading, which hops through a detached task.
    private func settle(_ refresher: HostSettingsRefresher) async throws {
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            if refresher.isIdleForTesting { return }
        }
        Issue.record("the refresher never settled")
    }

    @Test("GNOME's animations off is reduced motion, and anything else it prints says nothing")
    func gnome() {
        #expect(TerminalClient.gnomeReducesMotion(gsettingsOutput: "false\n") == true)
        #expect(TerminalClient.gnomeReducesMotion(gsettingsOutput: "true\n") == false)
        #expect(TerminalClient.gnomeReducesMotion(gsettingsOutput: "No such schema “org.gnome.desktop.interface”") == nil)
        #expect(TerminalClient.gnomeReducesMotion(gsettingsOutput: nil) == nil)
    }

    @Test("A reading lands, and only a change is passed on")
    func passesChangesOn() async throws {
        let host = HostStandIn()
        let refresher = refresher(host)
        host.reduces = true
        refresher.refresh()
        try await settle(refresher)
        #expect(refresher.settings.accessibility == [.reduceMotion] && host.changes == [true])

        refresher.refresh()
        try await settle(refresher)
        #expect(host.changes == [true], "the same answer is not passed on again")

        host.reduces = false
        refresher.refresh()
        try await settle(refresher)
        #expect(refresher.settings.accessibility.isEmpty && host.changes == [true, false])
        #expect(host.readings == 3)
    }

    @Test("The host's setting, as the runner hands it on, reaches the root, and goes when it goes")
    func reachesTheRoot() {
        let probe = ReduceMotionProbe()
        let loop = RenderLoopHarness().loop(ReduceMotionProbeApp(probe: probe))
        loop.hostAccessibility = [.reduceMotion]
        loop.render()
        #expect(probe.seen == true)
        loop.hostAccessibility = []
        loop.render()
        #expect(probe.seen == false)
    }

    @Test("The terminal regaining the focus reads the host's setting again")
    func focusInReadsAgain() async throws {
        let appState = AppState()
        let runner = AppRunner(app: ReduceMotionProbeApp(), appState: appState)
        let loop = RenderLoopHarness().loop(ReduceMotionProbeApp())
        let host = HostStandIn()
        host.reduces = true
        let refresher = refresher(host) { loop.hostAccessibility = $0.accessibility }
        runner.hostSettings = refresher
        let timer = CursorTimer(renderNotifier: appState)

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        try await settle(refresher)
        #expect(host.readings == 0, "the focus going away reads nothing")
        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        try await settle(refresher)
        #expect(host.readings == 1)
        #expect(loop.hostAccessibility == [.reduceMotion], "and the loop was handed what it read")
    }
}
