//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaneScopedInputTests.swift
//
//  Panes — a live sheet docked under the page it was presented over (A19,
//  design C) — share the keyboard by the focus: `.keyboardShortcut` and the
//  claim on Escape are the pane's the focus is in. Rendered here through a
//  test host that renders its content as a pane, as the live sheet will.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation

/// Renders `content` as pane `id`: its own focus section, rendered through
/// `renderingPane`, as a live sheet's presenter renders its content.
private struct PaneHost<Content: View>: View, Renderable {
    let id: String
    let content: Content

    init(id: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }

    var body: Never { fatalError("PaneHost renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var paneContext = context.withChildIdentity(type: Content.self, index: 0)
        paneContext.environment.activeFocusSectionID = id
        return renderingPane(id, context: context) {
            if !context.isMeasuring { context.environment.focusManager?.registerSection(id: id) }
            return TUIkitView.renderToBuffer(content, context: paneContext)
        }
    }
}

/// What the page's and the pane's shortcuts did.
@MainActor
private final class Fired {
    var pageDefault = 0
    var paneDefault = 0
    var pageChord = 0
    var paneChord = 0
    var pageCancel = 0
    var path = NavigationPath()
    var pathBinding: Binding<NavigationPath> { Binding(get: { self.path }, set: { self.path = $0 }) }
}

@MainActor
@Suite("Panes share the keyboard by the focus", .rendersEnglishUI)
struct PaneScopedInputTests {
    /// A page and a pane, each with a field that lets Return through and a
    /// default button, and a chord of its own.
    private func twoPanes(_ fired: Fired) -> some View {
        VStack {
            TextField("page", text: .constant(""))
            Button("Page OK") { fired.pageDefault += 1 }.keyboardShortcut(.defaultAction)
            Button("Page new") { fired.pageChord += 1 }.keyboardShortcut("n", modifiers: .control)
            PaneHost(id: "pane") {
                VStack {
                    TextField("pane", text: .constant(""))
                    Button("Pane OK") { fired.paneDefault += 1 }.keyboardShortcut(.defaultAction)
                    Button("Pane reload") { fired.paneChord += 1 }.keyboardShortcut("r", modifiers: .control)
                }
            }
        }
    }

    /// Tabs until the focus is in pane `id` (`nil`: on the page), at most
    /// `limit` times.
    private func tab(into id: String?, _ harness: InputChainHarness, limit: Int = 8, _ build: () -> some View) {
        for _ in 0..<limit where harness.focusManager.activePaneID != id {
            harness.press(KeyEvent(key: .tab))
            harness.frame(build())
        }
    }

    @Test("Return fires the default button of the pane the focus is in, and no other")
    func defaultActionIsThePanes() {
        let harness = InputChainHarness(width: 60, height: 20)
        let fired = Fired()
        harness.frame(twoPanes(fired))
        harness.frame(twoPanes(fired))
        #expect(harness.focusManager.activePaneID == nil, "precondition: the focus starts on the page")
        harness.press(KeyEvent(key: .enter))
        #expect((fired.pageDefault, fired.paneDefault) == (1, 0), "on the page")

        tab(into: "pane", harness) { twoPanes(fired) }
        #expect(harness.focusManager.activePaneID == "pane", "precondition: Tab reached the pane")
        // To the pane's field, which lets Return through.
        harness.frame(twoPanes(fired))
        #expect(harness.focusManager.currentFocused is any TextInputFocusHandler, "precondition: on the pane's field")
        harness.press(KeyEvent(key: .enter))
        #expect((fired.pageDefault, fired.paneDefault) == (1, 1), "in the pane")
    }

    @Test("A key equivalent the pane does not bind reaches the page's; the page never reaches the pane's")
    func chordsGoUpToThePage() {
        let harness = InputChainHarness(width: 60, height: 20)
        let fired = Fired()
        harness.frame(twoPanes(fired))
        harness.frame(twoPanes(fired))
        harness.press(KeyEvent(key: .character("r"), ctrl: true))
        #expect(fired.paneChord == 0, "the pane's chord fired from the page")

        tab(into: "pane", harness) { twoPanes(fired) }
        harness.press(KeyEvent(key: .character("n"), ctrl: true))
        #expect(fired.pageChord == 1, "the page's chord did not reach it from the pane")
        harness.press(KeyEvent(key: .character("r"), ctrl: true))
        #expect(fired.paneChord == 1)
    }

    /// A framework default — a split view's sidebar chord — fell back past
    /// the pane rule: with an alert opened inside a live sheet holding the
    /// keyboard, the page's app chords were held and its defaults fired.
    @Test("A framework default is its pane's, and the page's reaches a pane only where the page's chords do")
    func defaultsArePaneScoped() {
        let registry = KeyboardShortcutRegistry()
        var page = 0
        var pane = 0
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { page += 1 }
        registry.currentPane = "sheet"
        registry.registerDefault(KeyboardShortcut("d", modifiers: .control)) { pane += 1 }
        registry.currentPane = nil
        let pageChord = KeyEvent(key: .character("s"), ctrl: true)
        let paneChord = KeyEvent(key: .character("d"), ctrl: true)
        #expect(!registry.trigger(for: pageChord, activePane: "sheet", reachesPage: false))
        #expect(page == 0, "the page's default fired from under a modal in the pane")
        #expect(registry.trigger(for: pageChord, activePane: "sheet"))
        #expect(page == 1, "the page's default did not reach the pane")
        #expect(!registry.trigger(for: paneChord, activePane: nil))
        #expect(pane == 0, "the pane's default fired with the focus on the page")
        #expect(registry.trigger(for: paneChord, activePane: "sheet"))
        #expect(pane == 1)
    }

    /// A page with a cancel button, and a pane holding a stack with a screen
    /// pushed, whose bar claims Escape as going back.
    private func stackInPane(_ fired: Fired) -> some View {
        VStack {
            Button("Page cancel") { fired.pageCancel += 1 }.keyboardShortcut(.cancelAction)
            PaneHost(id: "pane") {
                NavigationStack(path: fired.pathBinding) {
                    Button("root") {}
                        .navigationDestination(for: Int.self) { Button("screen \($0)") {} }
                }
            }
        }
    }

    @Test("A NavigationStack's claim in a pane the focus is not in leaves Escape to the page")
    func stackClaimIsThePanes() {
        let harness = InputChainHarness(width: 60, height: 20)
        let fired = Fired()
        fired.path.append(1)
        harness.frame(stackInPane(fired))
        harness.frame(stackInPane(fired))
        // The pushed screen took the focus; back to the page.
        tab(into: nil, harness) { stackInPane(fired) }
        #expect(harness.focusManager.activePaneID == nil, "precondition: the focus is on the page")
        #expect(harness.statusBar.escapeLabelOverride == nil, "the pane's claim stands on the page")
        harness.press(KeyEvent(key: .escape))
        harness.frame(stackInPane(fired))
        #expect(fired.path.count == 1, "the stack in the pane went back")
        #expect(fired.pageCancel == 1, "the page's cancel button did not fire")

        tab(into: "pane", harness) { stackInPane(fired) }
        #expect(harness.statusBar.escapeLabelOverride == "go back")
        harness.press(KeyEvent(key: .escape))
        harness.frame(stackInPane(fired))
        #expect(fired.path.isEmpty, "Escape in the pane did not go back")
        #expect(fired.pageCancel == 1)
    }

    // MARK: - The user's quit key

    /// The driver's quit on ⌃\ is set once a frame, for the whole screen
    /// (`Terminal.maskQuitKey(for:)`), so a binding on the chord in a pane — a
    /// live sheet's — masks it as one on the page does, wherever the focus is.
    /// Which of them the key then reaches is the pane rule's.
    @Test("A ⌃\\ shortcut in a pane masks the user's quit key with the focus on the page too")
    func paneBindingMasksTheQuitKey() {
        let harness = InputChainHarness(width: 60, height: 20)
        let quitChord = KeyEvent(key: .character("\\"), ctrl: true)
        func page() -> some View {
            VStack {
                Button("Page") {}
                PaneHost(id: "pane") {
                    Button("Mine") {}.keyboardShortcut("\\", modifiers: .control)
                }
            }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(harness.focusManager.activePaneID == nil, "precondition: the focus starts on the page")
        #expect(!harness.tui.keyboardShortcuts.hasAppShortcut(for: quitChord), "precondition: the page binds none")
        #expect(harness.handler.declaresBinding(forAnyOf: [quitChord]), "the pane's binding is declared")
    }

    /// An unclaimed ⌃\\ that may be ⌃4 goes round again to the bindings
    /// declared for ⌃4 by the rule ordinary dispatch follows: a pane's
    /// shortcut only with the focus in the pane. Asked of the page's table
    /// alone, the retry never reached a live sheet's ⌘4.
    @Test("An unclaimed ⌃\\ offered again as ⌃4 reaches a pane's ⌘4 only with the focus in the pane")
    func quitKeyRetryFollowsThePanes() {
        let harness = InputChainHarness(width: 60, height: 20)
        let fired = Fired()
        let four = KeyEvent(key: .character("4"), ctrl: true)
        func page() -> some View {
            VStack {
                Button("Page") {}
                PaneHost(id: "pane") {
                    Button("Four") { fired.paneChord += 1 }.keyboardShortcut("4", modifiers: .control)
                }
            }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(!harness.handler.dispatchToDeclaredBindings(four), "from the page")
        #expect(fired.paneChord == 0)

        tab(into: "pane", harness) { page() }
        #expect(harness.focusManager.activePaneID == "pane", "precondition: Tab reached the pane")
        #expect(harness.handler.dispatchToDeclaredBindings(four), "from the pane")
        #expect(fired.paneChord == 1)
    }
}
