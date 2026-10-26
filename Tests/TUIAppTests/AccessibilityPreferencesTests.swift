//  🖥️ TUI — A Terminal UI framework for Swift
//  AccessibilityPreferencesTests.swift
//
//  Reduce transparency, differentiate without colour and increase contrast,
//  read as reduce motion is (owner ruling P5 (c)): the user's `TUIKIT_*`
//  variables and the host's settings reach the root, and the defaults are
//  SwiftUI's on macOS.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

/// What the root's environment said, written by the view that reads it.
@MainActor
private final class PreferencesProbe {
    var reduceTransparency: Bool?
    var differentiateWithoutColor: Bool?
    var contrast: ColorSchemeContrast?
}

private struct PreferencesReader: View {
    let probe: PreferencesProbe
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        probe.reduceTransparency = reduceTransparency
        probe.differentiateWithoutColor = differentiateWithoutColor
        probe.contrast = contrast
        return Text(verbatim: "probe")
    }
}

private struct PreferencesApp: App {
    let probe: PreferencesProbe

    init() { self.init(probe: PreferencesProbe()) }

    init(probe: PreferencesProbe) {
        self.probe = probe
    }

    var body: some Scene {
        WindowGroup { PreferencesReader(probe: probe) }
    }
}

@MainActor
@Suite("Accessibility preferences beyond reduce motion")
struct AccessibilityPreferencesTests {
    @Test("Each TUIKIT_* variable set to 1 asks for its preference, and nothing else does")
    func variables() {
        #expect(
            TerminalClient.accessibilityRequested(environment: [
                "TUIKIT_REDUCE_TRANSPARENCY": "1", "TUIKIT_DIFFERENTIATE_WITHOUT_COLOR": "1",
                "TUIKIT_INCREASE_CONTRAST": "1",
            ]) == [.reduceTransparency, .differentiateWithoutColor, .increaseContrast])
        #expect(TerminalClient.accessibilityRequested(environment: ["TUIKIT_INCREASE_CONTRAST": "0"]).isEmpty)
        #expect(TerminalClient.accessibilityRequested(environment: [:]).isEmpty)
    }

    @Test("Unset, the values are SwiftUI's defaults on macOS")
    func defaults() {
        let environment = EnvironmentValues()
        #expect(!environment.accessibilityReduceTransparency)
        #expect(!environment.accessibilityDifferentiateWithoutColor)
        #expect(environment.colorSchemeContrast == .standard)
    }

    @Test("The user's and the host's preferences reach the root; a loop told nothing draws as if unset")
    func reachTheRoot() {
        let probe = PreferencesProbe()
        let loop = RenderLoopHarness().loop(
            PreferencesApp(probe: probe), accessibility: [.reduceTransparency, .increaseContrast])
        loop.render()
        #expect(probe.reduceTransparency == true)
        #expect(probe.differentiateWithoutColor == false)
        #expect(probe.contrast == .increased)

        loop.hostAccessibility = [.differentiateWithoutColor]
        loop.render()
        #expect(probe.differentiateWithoutColor == true, "the host's adds to the user's")

        let unset = PreferencesProbe()
        RenderLoopHarness().loop(PreferencesApp(probe: unset)).render()
        #expect(unset.reduceTransparency == false && unset.contrast == .standard)
    }

    @Test("GNOME's high contrast is read as a switch, and anything else it prints says nothing")
    func gnomeSwitch() {
        #expect(TerminalClient.gnomeSwitch(gsettingsOutput: "true\n") == true)
        #expect(TerminalClient.gnomeSwitch(gsettingsOutput: "false") == false)
        #expect(TerminalClient.gnomeSwitch(gsettingsOutput: "No such key “high-contrast”") == nil)
        #expect(TerminalClient.gnomeSwitch(gsettingsOutput: nil) == nil)
    }

    @Test("The underscored spellings write the values, as SwiftUI's do")
    func underscoredSetters() {
        var environment = EnvironmentValues()
        environment._accessibilityDifferentiateWithoutColor = true
        environment._colorSchemeContrast = .increased
        #expect(environment.accessibilityDifferentiateWithoutColor)
        #expect(environment.colorSchemeContrast == .increased)
    }
}
