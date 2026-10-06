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

@testable import TUIkit

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
            return TUIkit.renderToBuffer(content, context: paneContext)
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
}
