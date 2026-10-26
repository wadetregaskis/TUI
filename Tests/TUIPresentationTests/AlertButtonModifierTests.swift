//  🖥️ TUI — A Terminal UI framework for Swift
//  AlertButtonModifierTests.swift
//
//  A dialog draws its actions' buttons itself, so the modifiers written on a
//  button were looked through and dropped. A macOS alert keeps two of them —
//  `.disabled` and `.keyboardShortcut`, read back on 15.8
//  (`Tools/SwiftUIProbes/Menu items and alert buttons/alert.out`) — and drops
//  `.help`, `.tint` and `.foregroundStyle`. These pin the two kept: a disabled
//  button cannot be chosen however the modifier was written, a key equivalent
//  chooses its button, the default action's Return reaches its button, and a
//  cancel action's button is what Escape answers with.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("An alert keeps .disabled and .keyboardShortcut written on its buttons", .rendersEnglishUI)
struct AlertButtonModifierTests {
    private struct StubTheme: Cyclable {
        let id = "stub"
        let name = "Stub"
    }

    @MainActor
    private final class Flag {
        var value = true
        var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// The input stack a running app has, as `AlertDismissalTests` builds it.
    @MainActor
    private struct Harness {
        let tui = TUIContext()
        let focus = FocusManager()
        let statusBar = StatusBarState()
        let context: RenderContext
        let handler: InputHandler

        init() {
            statusBar.focusManager = focus
            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.applyRuntimeServices(from: tui)
            environment.statusBar = statusBar
            environment.terminalWidth = 60
            context = RenderContext(availableWidth: 60, availableHeight: 24, environment: environment, tuiContext: tui)
            handler = InputHandler(
                statusBar: statusBar, keyEventDispatcher: tui.keyEventDispatcher, focusManager: focus,
                paletteManager: ThemeManager(items: [StubTheme()]),
                appearanceManager: ThemeManager(items: [StubTheme()]),
                keyboardShortcuts: tui.keyboardShortcuts, dragAndDropSession: nil, onQuit: {}, onSuspend: {})
        }

        /// One frame as the run loop draws it: composited, its regions armed.
        @discardableResult
        func frame(_ view: some View) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyEventDispatcher.clearHandlers()
            tui.keyboardShortcuts.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            statusBar.beginRenderPass()
            focus.beginRenderPass()
            let composited = renderToBuffer(view, context: context).compositingOverlays(
                maxWidth: context.availableWidth, maxHeight: context.availableHeight,
                palette: context.environment.palette)
            tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
            tui.stateStorage.endRenderPass()
            focus.endRenderPass()
            return composited
        }

        func click(_ label: String, on screen: FrameBuffer) throws {
            let row = try #require(screen.lines.lastIndex { $0.stripped.contains(label) }, "\(label) is on screen")
            let line = screen.lines[row].stripped
            let column = line.distance(from: line.startIndex, to: try #require(line.range(of: label)).lowerBound)
            for phase in [MousePhase.pressed, .released] {
                _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: column + 1, y: row))
            }
        }
    }

    @Test(".disabled written after another modifier leaves the alert's button unchoosable")
    func disabledBehindAnotherModifier() throws {
        let harness = Harness()
        let presented = Flag()
        var chose = "—"
        let view = Text("Page").alert("Sure?", isPresented: presented.binding) {
            Button("Off") { chose = "Off" }.keyboardShortcut("k").disabled(true)
            Button("On") { chose = "On" }
        }
        let screen = harness.frame(view)
        try harness.click("Off", on: screen)
        #expect(chose == "—", "a click chose the disabled button")
        #expect(presented.value, "…and closed the alert")
    }

    @Test("A key equivalent written on an alert's button chooses it")
    func keyEquivalentChooses() {
        let harness = Harness()
        let presented = Flag()
        var chose = "—"
        let view = Text("Page").alert("Sure?", isPresented: presented.binding) {
            Button("Keep") { chose = "Keep" }.keyboardShortcut("k")
            Button("Discard", role: .cancel) { chose = "Discard" }
        }
        harness.frame(view)
        // ⌘K, which the default command key spells Ctrl-K.
        _ = harness.handler.handle(KeyEvent(key: .character("k"), ctrl: true))
        #expect(chose == "Keep", "Ctrl-K chose \(chose)")
        #expect(!presented.value, "choosing it closed the alert")
    }

    @Test("Return that nothing focused takes reaches the alert's default button")
    func defaultActionRegisters() {
        let harness = Harness()
        let presented = Flag()
        var chose = "—"
        let view = Text("Page").alert("Sure?", isPresented: presented.binding) {
            Button("Other") { chose = "Other" }
            Button("Default") { chose = "Default" }.keyboardShortcut(.defaultAction)
        }
        harness.frame(view)
        // Layer 3.5 directly: what a Return the focused control let through
        // reaches (a focused button keeps its own Return, TUI's rule).
        let fired = harness.tui.keyboardShortcuts.trigger(
            for: KeyEvent(key: .enter), activePane: harness.focus.activePaneID,
            reachesPage: !harness.focus.activeSectionIsModal)
        #expect(fired && chose == "Default", "Return reached \(chose)")
    }

    @Test("Escape answers with a cancel action's button where no button has the cancel role")
    func cancelActionAnswersEscape() {
        let harness = Harness()
        let presented = Flag()
        var chose = "—"
        let view = Text("Page").alert("Sure?", isPresented: presented.binding) {
            Button("Go") { chose = "Go" }
            Button("Stop") { chose = "Stop" }.keyboardShortcut(.cancelAction)
        }
        harness.frame(view)
        _ = harness.handler.handle(KeyEvent(key: .escape))
        #expect(chose == "Stop", "Escape chose \(chose)")
        #expect(!presented.value, "Escape closed the alert")
    }

    @Test("The cancel role still answers Escape before a cancel action")
    func cancelRoleFirst() {
        let harness = Harness()
        let presented = Flag()
        var chose = "—"
        let view = Text("Page").alert("Sure?", isPresented: presented.binding) {
            Button("Stop") { chose = "Stop" }.keyboardShortcut(.cancelAction)
            Button("Cancel", role: .cancel) { chose = "Cancel" }
        }
        harness.frame(view)
        _ = harness.handler.handle(KeyEvent(key: .escape))
        #expect(chose == "Cancel", "Escape chose \(chose)")
    }
}
