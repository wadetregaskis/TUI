//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilitiesPublishingTests.swift
//
//  `\.terminalCapabilities` as the run loop publishes it: what a launch
//  settles, the progress bar's answer as the loop learns whether it shows
//  (under tmux, from the clients attached), a key that shows Option is sent
//  as Meta, and a memoized view that reads it drawn again when it changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost

// MARK: - Fixtures

/// Says what `\.terminalCapabilities` tells it of Option as Meta and of
/// links. Equatable, and drawn behind `.equatable()`, so that it is served
/// from the render cache unless the loop sees the environment change.
private struct CapabilitiesReader: View, Equatable {
    @Environment(\.terminalCapabilities) private var terminal

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        VStack {
            Text(verbatim: "meta \(Self.word(terminal.status(of: .optionAsMeta)))")
            Text(verbatim: "links \(Self.word(terminal.status(of: .hyperlinks)))")
        }
    }

    private static func word(_ status: TerminalCapabilities.Status) -> String {
        switch status {
        case .supported: "yes"
        case .unsupported: "no"
        case .undetermined: "unknown"
        }
    }
}

private struct CapabilitiesApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { CapabilitiesReader().equatable() }
    }
}

// MARK: - Tests

@MainActor
@Suite("What the terminal can do, as the run loop publishes it", .serialized)
struct TerminalCapabilitiesPublishingTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: HeadlessApp<CapabilitiesApp>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private static func shows(_ app: HeadlessApp<CapabilitiesApp>, _ text: String) -> Bool {
        app.screen.map(\.stripped).joined(separator: "\n").contains(text)
    }

    @Test("A memoized view reads what was published, and draws again when it changes")
    mutating func viewsFollowTheValue() {
        let app = HeadlessApp(CapabilitiesApp(), width: 30, height: 4)
        frame(app)
        #expect(Self.shows(app, "links unknown"), "nothing known outside a run")

        app.terminalCapabilities = TerminalCapabilities.nothingKnown.settling(.hyperlinks, as: .supported)
        frame(app)
        #expect(Self.shows(app, "links yes"))

        app.terminalCapabilities = app.terminalCapabilities.settling(.hyperlinks, as: .unsupported)
        frame(app)
        #expect(Self.shows(app, "links no"))
    }

    @Test("An Option chord read from the terminal settles Option as Meta, and the view says so")
    mutating func optionChordReachesViews() {
        let app = HeadlessApp(CapabilitiesApp(), width: 30, height: 4)
        frame(app)
        #expect(Self.shows(app, "meta unknown"))

        // ⌥← in a terminal whose key map sends `ESC b` shows nothing.
        app.send(KeyEvent(key: .character("b"), alt: true))
        frame(app)
        #expect(Self.shows(app, "meta unknown"))
        #expect(app.terminalCapabilities.status(of: .optionAsMeta) == .undetermined)

        app.send(KeyEvent(key: .character("x"), alt: true))
        frame(app)
        #expect(Self.shows(app, "meta yes"))
    }

    /// What tmux says of the clients attached: whether every one draws the
    /// progress bar tmux passes on.
    private static func clients(drawProgressBars: Bool) -> ClientCapabilities {
        ClientCapabilities(
            emojiChrome: false, skinTonesSafe: true, blockElementsFillTheLine: true, cornerTrianglesFillTheCell: true,
            drawsProgressBars: drawProgressBars, mayImproveShortly: false)
    }

    @Test(
        "The progress bar's answer follows whether it shows, and under tmux the clients attached",
        arguments: [
            // isTmux, sends, clients draw it, its absence, status
            (false, true, false, .unsupported, .supported),
            (true, true, true, .unsupported, .supported),
            (true, true, false, .unsupported, .unsupported),
            (false, false, false, .unsupported, .unsupported),
            (false, false, false, .undetermined, .undetermined),
        ] as [(Bool, Bool, Bool, TerminalCapabilities.Status, TerminalCapabilities.Status)])
    func progressFollowsTheLoop(
        isTmux: Bool, sends: Bool, clientsDrawIt: Bool, absence: TerminalCapabilities.Status,
        status: TerminalCapabilities.Status
    ) {
        let harness = RenderLoopHarness()
        let loop = harness.loop(
            CapabilitiesApp(), isTmux: isTmux, clientCapabilities: Self.clients(drawProgressBars: clientsDrawIt))
        loop.sendsProgressReports = sends
        loop.progressAbsence = absence
        _ = loop.render()
        #expect(harness.tuiContext.terminalCapabilities.status(of: .progressReports) == status)
        #expect(
            harness.tuiContext.terminalCapabilities.settling(.progressReports, as: .undetermined) == .nothingKnown,
            "nothing else settled")
    }

    @Test("A launch settles the keyboard from the negotiation, whatever the terminal")
    func launchSettlesTheKeyboard() {
        let all = TerminalCapabilities.atLaunch(
            features: .none,
            reporting: KeyboardReporting(flags: [
                .disambiguateEscapeCodes, .reportEventTypes, .reportAlternateKeys, .reportAllKeysAsEscapeCodes,
                .reportAssociatedText,
            ]),
            environment: [:])
        #expect(all.supported.isSuperset(of: TerminalCapabilities.negotiatedKeyboard))
        #expect(all.status(of: .optionAsMeta) == .undetermined, "only a key shows it")
        #expect(all.status(of: .progressReports) == .undetermined, "the loop's to publish")

        let legacy = TerminalCapabilities.atLaunch(features: .none, reporting: .legacy, environment: [:])
        #expect(legacy.unsupported.isSuperset(of: TerminalCapabilities.negotiatedKeyboard))
    }

    @Test("A switch settles notifications and pointer shapes at launch, wherever the app runs")
    func launchHonoursSwitches() {
        let on = TerminalCapabilities.atLaunch(
            features: TerminalFeatures(pointerShapes: true, postsNotifications: true), reporting: .legacy,
            environment: ["TUI_NOTIFICATIONS": "1", "TUI_POINTER_SHAPES": "all"])
        #expect(on.supports([.notifications, .pointerShapes]))
        let off = TerminalCapabilities.atLaunch(
            features: .none, reporting: .legacy,
            environment: ["TUI_NOTIFICATIONS": "0", "TUI_POINTER_SHAPES": "0"])
        #expect(off.status(of: [.notifications, .pointerShapes]) == .unsupported)
    }

    @Test("A bar that does not show says nothing of a terminal TUI did not identify, unless switched off")
    func progressAbsence() {
        #expect(TerminalCapabilities.progressAbsence(program: .unidentified, environment: [:]) == .undetermined)
        #expect(
            TerminalCapabilities.progressAbsence(program: .unidentified, environment: ["TUI_PROGRESS": "0"])
                == .unsupported)
        for program in TerminalClient.Program.allCases where program != .unidentified {
            #expect(TerminalCapabilities.progressAbsence(program: program, environment: [:]) == .unsupported)
        }
    }
}
