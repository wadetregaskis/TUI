//  🖥️ TUI — A Terminal UI framework for Swift
//  SecureFieldWidePromptTests.swift
//
//  A focused, empty `SecureField` draws its prompt unmasked, but measured the
//  prompt through the field's bullet mapping, where every character is one
//  cell. A two-cell prompt character was drawn two cells wide and counted as
//  one, so the padding after it overshot by a cell per wide character and the
//  focused field came out wider than the unfocused one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
import TUITextInput

@MainActor
@Suite("SecureField with a wide prompt")
struct SecureFieldWidePromptTests {

    private func context(_ focusManager: FocusManager, path: String) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: 20, availableHeight: 1, environment: environment, tuiContext: TUIContext(),
            identity: ViewIdentity(path: path)
        ).isolatingRenderCache()
    }

    private func line(focused: Bool, prompt: String) -> String {
        let focusManager = FocusManager()
        if !focused {
            // Something else takes the focus first, so the field renders unfocused.
            _ = renderToBuffer(
                SecureField("Decoy", text: .constant("x")).focusID("decoy"),
                context: context(focusManager, path: "decoy"))
        }
        let field = SecureField("Password", text: .constant(""), prompt: Text(prompt)).focusID("sf")
        let real = context(focusManager, path: "real")
        _ = renderToBuffer(field, context: real)
        return renderToBuffer(field, context: real).lines[0].stripped
    }

    @Test("A focused field with a wide prompt is as wide as it is unfocused", arguments: ["密码", "🔑key"])
    func focusedWidthMatches(prompt: String) {
        let focused = line(focused: true, prompt: prompt)
        let unfocused = line(focused: false, prompt: prompt)
        #expect(focused.strippedLength == 20, ">>\(focused)<<")
        #expect(unfocused.strippedLength == 20, ">>\(unfocused)<<")
        #expect(focused.contains(prompt), ">>\(focused)<<")
        // The caret is an inverted cell, so with the styling stripped the two
        // draw the same: the prompt, then blanks to the closing cap.
        #expect(focused == unfocused, ">>\(focused)<< against >>\(unfocused)<<")
    }
}
