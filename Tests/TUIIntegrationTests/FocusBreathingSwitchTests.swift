//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusBreathingSwitchTests.swift
//
//  `TUI_BREATHING=0` and `Scene.focusBreathing(false)`: every focus
//  indication held still, whatever a view's own `.selectionIndicatorStyle`
//  says, and apart from Reduce Motion.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("The breathing switch")
struct FocusBreathingSwitchTests {
    @Test("`0` turns it off and `1` on; anything else says nothing")
    func variable() {
        #expect(TerminalClient.focusBreathingRequested(environment: ["TUI_BREATHING": "0"]) == false)
        #expect(TerminalClient.focusBreathingRequested(environment: ["TUI_BREATHING": "1"]) == true)
        #expect(TerminalClient.focusBreathingRequested(environment: ["TUI_BREATHING": "yes"]) == nil)
        #expect(TerminalClient.focusBreathingRequested(environment: [:]) == nil)
    }

    @Test(
        "Off, a view's own style reads as still", arguments: [TextCursorStyle.Animation.pulse, .blink, .none])
    func styleReadsStill(style: TextCursorStyle.Animation) {
        var environment = EnvironmentValues()
        environment.selectionIndicatorStyle = style
        #expect(environment.selectionIndicatorStyle == style)
        environment.focusBreathes = false
        #expect(environment.selectionIndicatorStyle == .none)
    }

    @Test("Off, a focused button leaves no run, though its view asks for a pulse")
    func focusedButtonIsStill() {
        let breathing = focusedRender(Button("Save") {}.appearance(.block))
        #expect(!breathing.animatedCells.isEmpty, "the control under test breathes by default")

        var context = makeRenderContext(width: 40, height: 8)
        context.environment.focusBreathes = false
        let still = renderToBuffer(
            Button("Save") {}.appearance(.block).selectionIndicatorStyle(.pulse), context: context)
        let animates = still.animatedCells.contains(where: \.isAnimating)
        #expect(!animates)
    }

    @Test("Reduce Motion leaves the breath alone")
    func apartFromReduceMotion() {
        var context = makeRenderContext(width: 40, height: 8)
        context.environment.accessibilityReduceMotion = true
        let buffer = renderToBuffer(Button("Save") {}.appearance(.block), context: context)
        let animates = buffer.animatedCells.contains(where: \.isAnimating)
        #expect(animates)
    }

    private struct ReadingApp: App {
        let breathes: Bool
        init() { breathes = true }
        init(breathes: Bool) { self.breathes = breathes }

        var body: some Scene {
            WindowGroup { Reading() }
                .focusBreathing(breathes)
        }
    }

    private struct Reading: View {
        @Environment(\.focusBreathes) private var focusBreathes
        var body: some View { Text(focusBreathes ? "breathes" : "still") }
    }

    @Test("The scene's `false` reaches every view, and its `true` asks for nothing", arguments: [false, true])
    func scene(breathes: Bool) {
        let app = TestApp(ReadingApp(breathes: breathes), width: 20, height: 3)
        #expect(app.screen.contains(breathes ? "breathes" : "still"))
    }
}
