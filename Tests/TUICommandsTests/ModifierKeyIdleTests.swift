//  🖥️ TUI — A Terminal UI framework for Swift
//  ModifierKeyIdleTests.swift
//
//  A view drawn from the modifier keys held asks for a frame when they change,
//  and for none while they don't: under the kitty keyboard protocol, the menu
//  bar's letters and a `modifierKeyAlternate` once kept the animation clock
//  ticking for as long as they were on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUICore
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// A menu bar over a page that animates nothing.
private struct MenuBarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commandsRemoved()
            .commands { CommandMenu("Fig") { Button("F1") {} } }
    }
}

/// A view with an alternate on Option, and no menu bar.
private struct AlternateApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("Forward").modifierKeyAlternate(.option) { Text("Go to…") } }
            .commandsRemoved()
    }
}

// MARK: - Tests

/// Ghostty, kitty and WezTerm report a modifier key held alone, so there a
/// frame drawn from the modifier keys is a frame of the menu bar, which every
/// app with commands has. The read was counted as a read of the pulse
/// (`VolatileReadTracker.recordVolatileRead()`), which is what keeps the
/// clock ticking, and every tick then walked the whole scene again rather than
/// replaying the breathing focus: nearly a core of CPU, idle, in the Example's
/// debug build on Ghostty (2026-11-10). The keys move only when the terminal
/// says so, and that report asks for its own frame (`ModifierKeyMonitor.record`).
@MainActor
@Suite("Modifier keys ask for frames only as they change", .serialized)
struct ModifierKeyIdleTests {
    /// A harness whose terminal took the kitty keyboard protocol's flags, as
    /// Ghostty's negotiation grants them.
    private func reportingHarness() -> RenderLoopHarness {
        let harness = RenderLoopHarness()
        harness.tuiContext.keyboardReporting = KeyboardReporting(flags: .requested)
        return harness
    }

    @Test("A menu bar where the terminal reports Option held alone asks for no ticks")
    func menuBarAsksForNoTicks() {
        let harness = reportingHarness()
        let activity = harness.loop(MenuBarApp()).render()

        #expect(harness.terminal.allOutput.contains("Fig"), "the bar is on screen")
        #expect(!activity.usesPulse)
        #expect(!activity.usesCursor)
    }

    @Test("A modifier key alternate where the terminal reports the keys asks for no ticks")
    func alternateAsksForNoTicks() {
        let harness = reportingHarness()
        let activity = harness.loop(AlternateApp()).render()

        #expect(harness.terminal.allOutput.contains("Forward"))
        #expect(!activity.usesPulse)
    }

    @Test("Option held still asks for the frame that shows it")
    func optionStillAsksForAFrame() {
        let harness = reportingHarness()
        harness.loop(AlternateApp()).render()

        #expect(harness.tuiContext.modifierKeys.record(ModifierKeyState(option: true)))
    }
}
