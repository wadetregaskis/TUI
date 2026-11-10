//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogBorderTests.swift
//
//  `dialogBorder(_:style:titleColor:)` reaches every form of `alert` and
//  `confirmationDialog` (owner's ruling, 2026-11-10). Four of the fourteen
//  `alert` forms used to take `borderStyle:borderColor:titleColor:` of their
//  own and the other ten none, so a style reached some alerts and not others;
//  each form is presented here under the modifier.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("dialogBorder reaches every dialog", .rendersEnglishUI)
struct DialogBorderTests {
    private struct Full: LocalizedError {
        var errorDescription: String? { "The disk is full" }
        var recoverySuggestion: String? { "Free some space." }
    }

    /// The composited screen, escape codes and all: colour is half of what the
    /// modifier sets.
    private func screen(_ view: some View) -> [String] {
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines
    }

    /// Whether the screen draws a double-line border, the style the tests set.
    private func isDoubleLined(_ lines: [String]) -> Bool {
        lines.contains { $0.stripped.contains("═") }
    }

    private typealias Form = (name: String, view: @MainActor () -> AnyView)

    private static let title: String = "Erase?"
    private static let key: LocalizedStringKey = "Erase?"
    private static let text = Text(verbatim: "Erase?")

    /// Each of the fourteen `alert` forms, presented.
    private static let alertForms: [Form] = [
        ("key, message", {
            AnyView(Text("base").alert(key, isPresented: .constant(true)) { Button("OK") {} } message: { Text("m") })
        }),
        ("key", { AnyView(Text("base").alert(key, isPresented: .constant(true)) { Button("OK") {} }) }),
        ("string, message", {
            AnyView(Text("base").alert(title, isPresented: .constant(true)) { Button("OK") {} } message: { Text("m") })
        }),
        ("string", { AnyView(Text("base").alert(title, isPresented: .constant(true)) { Button("OK") {} }) }),
        ("text, message", {
            AnyView(Text("base").alert(text, isPresented: .constant(true)) { Button("OK") {} } message: { Text("m") })
        }),
        ("text", { AnyView(Text("base").alert(text, isPresented: .constant(true)) { Button("OK") {} }) }),
        ("key, presenting, message", {
            AnyView(
                Text("base").alert(key, isPresented: .constant(true), presenting: 1) { _ in Button("OK") {} }
                    message: { _ in Text("m") })
        }),
        ("key, presenting", {
            AnyView(Text("base").alert(key, isPresented: .constant(true), presenting: 1) { _ in Button("OK") {} })
        }),
        ("string, presenting, message", {
            AnyView(
                Text("base").alert(title, isPresented: .constant(true), presenting: 1) { _ in Button("OK") {} }
                    message: { _ in Text("m") })
        }),
        ("string, presenting", {
            AnyView(Text("base").alert(title, isPresented: .constant(true), presenting: 1) { _ in Button("OK") {} })
        }),
        ("text, presenting, message", {
            AnyView(
                Text("base").alert(text, isPresented: .constant(true), presenting: 1) { _ in Button("OK") {} }
                    message: { _ in Text("m") })
        }),
        ("text, presenting", {
            AnyView(Text("base").alert(text, isPresented: .constant(true), presenting: 1) { _ in Button("OK") {} })
        }),
        ("error", { AnyView(Text("base").alert(isPresented: .constant(true), error: Full()) { Button("OK") {} }) }),
        ("error, message", {
            AnyView(
                Text("base").alert(isPresented: .constant(true), error: Full()) { _ in Button("OK") {} }
                    message: { error in Text(error.recoverySuggestion ?? "") })
        }),
    ]

    /// Confirmation dialogs: titled every way, with and without a message, and
    /// presenting a value.
    private static let confirmationForms: [Form] = [
        ("key, message", {
            AnyView(
                Text("base").confirmationDialog(key, isPresented: .constant(true), titleVisibility: .visible) {
                    Button("Erase") {}
                } message: { Text("m") })
        }),
        ("string", {
            AnyView(
                Text("base").confirmationDialog(title, isPresented: .constant(true), titleVisibility: .visible) {
                    Button("Erase") {}
                })
        }),
        ("text", {
            AnyView(
                Text("base").confirmationDialog(text, isPresented: .constant(true), titleVisibility: .visible) {
                    Button("Erase") {}
                })
        }),
        ("key, presenting", {
            AnyView(
                Text("base").confirmationDialog(
                    key, isPresented: .constant(true), titleVisibility: .visible, presenting: 1
                ) { _ in Button("Erase") {} })
        }),
    ]

    @Test("The lists hold every alert form and the confirmation dialogs the tests below run")
    func listsAreWhole() {
        #expect(Self.alertForms.count == 14)
        #expect(Self.confirmationForms.count == 4)
    }

    @Test("Every alert form takes the border", arguments: 0..<14)
    func everyAlertForm(index: Int) {
        let form = Self.alertForms[index]
        #expect(!isDoubleLined(screen(form.view())), "\(form.name): drawn single-lined by default")
        #expect(
            isDoubleLined(screen(form.view().dialogBorder(style: .doubleLine))),
            "\(form.name): the style reaches it")
        #expect(
            screen(form.view().dialogBorder(.blue, titleColor: .green)) != screen(form.view()),
            "\(form.name): the colours reach it")
    }

    @Test("Every confirmation dialog form takes the border", arguments: 0..<4)
    func everyConfirmationForm(index: Int) {
        let form = Self.confirmationForms[index]
        #expect(!isDoubleLined(screen(form.view())), "\(form.name): drawn single-lined by default")
        #expect(
            isDoubleLined(screen(form.view().dialogBorder(style: .doubleLine))),
            "\(form.name): the style reaches it")
        #expect(
            screen(form.view().dialogBorder(.blue, titleColor: .green)) != screen(form.view()),
            "\(form.name): the colours reach it")
    }

    @Test("The border and the title take their own colours")
    func eachColourIsItsOwn() {
        let form = Self.alertForms[0]
        let border = screen(form.view().dialogBorder(.blue))
        let title = screen(form.view().dialogBorder(titleColor: .blue))
        #expect(border != screen(form.view()) && title != screen(form.view()))
        #expect(border != title, "colouring the border is not colouring the title")
    }

    @Test("The nearest dialogBorder wins, and an empty one puts the defaults back")
    func nearestWins() {
        let form = Self.alertForms[0]
        let reset = screen(form.view().dialogBorder().dialogBorder(style: .doubleLine))
        #expect(!isDoubleLined(reset))
        #expect(reset == screen(form.view()))
    }

    @Test("An AlertPanel's own border parameters win over the environment")
    func panelParametersWin() {
        let own = screen(
            AlertPanel(title: Self.title, message: "m", borderStyle: .rounded)
                .dialogBorder(style: .doubleLine))
        #expect(!isDoubleLined(own))
        let inherited = screen(AlertPanel(title: Self.title, message: "m").dialogBorder(style: .doubleLine))
        #expect(isDoubleLined(inherited), "a part the panel leaves nil comes from the environment")
    }
}
