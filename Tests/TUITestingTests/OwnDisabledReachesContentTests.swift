//  🖥️ TUI — A Terminal UI framework for Swift
//  OwnDisabledReachesContentTests.swift
//
//  A control's own `.disabled(_:)` — `Button(…).disabled(true)` resolves to
//  `Button`'s, which returns a `Button`, not the view modifier — reaches what
//  the control draws of the app's as the modifier does: `\.isEnabled` is false
//  in its label and in its style's body, and a primitive style's
//  `Button(configuration)` is a disabled button. CLAUDE.md: `.disabled()` on a
//  control must reach its content. Written as an app's tests are, with no
//  `@testable`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

/// Says whether the environment it is drawn in is enabled.
private struct EnabledWord: View {
    let name: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View { Text(verbatim: "\(name)=\(isEnabled ? "on" : "off")") }
}

/// A style whose body reads `\.isEnabled`, as SwiftUI's custom styles do: its
/// configuration has no such property there.
private struct WordStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EnabledWord(name: "styled")
    }
}

/// A primitive style whose body is the button it was applied over.
private struct PassThroughStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
    }
}

private struct PrimitiveHost: View {
    @State private var presses = 0
    var body: some View {
        VStack {
            Button("Other") {}
            Button("Press") { presses += 1 }.disabled(true).buttonStyle(PassThroughStyle())
            Text(verbatim: "presses=\(presses)")
        }
    }
}

@MainActor
@Suite("A control's own .disabled reaches what it draws")
struct OwnDisabledReachesContentTests {
    /// Seen failing before: `label=on`.
    @Test("A disabled Button's label reads isEnabled as false")
    func buttonLabel() {
        let app = TestApp(width: 40, height: 4) {
            Button {} label: { EnabledWord(name: "label") }.disabled(true)
        }
        #expect(app.screen.contains("label=off"), "\(app.screen)")
    }

    /// Seen failing before: `styled=on`.
    @Test("A disabled Button's custom style reads isEnabled as false")
    func buttonStyle() {
        let app = TestApp(width: 40, height: 4) {
            Button("Go") {}.disabled(true).buttonStyle(WordStyle())
        }
        #expect(app.screen.contains("styled=off"), "\(app.screen)")
    }

    /// Seen failing before: the click and Return each ran the action.
    @Test("A disabled Button under a primitive style takes no key and no click")
    func primitiveStyle() throws {
        let app = TestApp(width: 40, height: 6) { PrimitiveHost() }
        app.press(.tab)
        app.press(.enter)
        try app.click("Press")
        app.press(.enter)
        #expect(app.screen.contains("presses=0"), "\(app.screen)")
    }

    /// Seen failing before: `toggle=on`.
    @Test("A disabled Toggle's label reads isEnabled as false")
    func toggleLabel() {
        let app = TestApp(width: 40, height: 4) {
            Toggle(isOn: .constant(true)) { EnabledWord(name: "toggle") }.disabled(true)
        }
        #expect(app.screen.contains("toggle=off"), "\(app.screen)")
    }

    @Test("An enabled Button's and Toggle's labels read isEnabled as true")
    func enabledStaysEnabled() {
        let app = TestApp(width: 40, height: 4) {
            VStack {
                Button {} label: { EnabledWord(name: "label") }.disabled(false)
                Toggle(isOn: .constant(true)) { EnabledWord(name: "toggle") }
            }
        }
        #expect(app.screen.contains("label=on"), "\(app.screen)")
        #expect(app.screen.contains("toggle=on"), "\(app.screen)")
    }
}
