//  🖥️ TUI — A Terminal UI framework for Swift
//  AlertPanelLocaleTests.swift
//
//  An alert's title and message read from keys follow a subtree's `\.locale`,
//  as a `Text` made from a key does: read again when the alert is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("An alert's words follow a locale override", .rendersEnglishUI)
struct AlertPanelLocaleTests {
    private func drawn(_ view: some View) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 60, height: 12)).lines.map(\.stripped)
            .joined(separator: "\n")
    }

    @Test("A preset's own title is TUI's word, in the subtree's language")
    func presetTitle() {
        let english = drawn(AlertPanel.warning(message: "x"))
        #expect(english.contains("Warning"), "\(english)")
        let german = drawn(AlertPanel.warning(message: "x").environment(\.locale, Locale(identifier: "de")))
        #expect(german.contains("Warnung"), "\(german)")
    }

    @Test("A keyed alert's title and message are read again, and words given as written are not")
    func keyedAlert() {
        let german = Locale(identifier: "de")
        let keyed = drawn(AlertPanel(title: "label.error", message: "button.cancel").environment(\.locale, german))
        #expect(keyed.contains("Fehler") && keyed.contains("Abbrechen"), "\(keyed)")
        let written = drawn(AlertPanel(title: verbatim("label.error"), message: verbatim("x")).environment(\.locale, german))
        #expect(written.contains("label.error"), "\(written)")
    }

    /// What `view` draws with its dialogs composited over it, as the run loop
    /// draws the screen.
    private func screen(_ view: some View) -> String {
        let context = makeRenderContext(width: 60, height: 14)
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 60, maxHeight: 14, palette: context.environment.palette)
            .lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("An alert and a confirmation dialog presented with a key title follow the override")
    func presentedDialogs() {
        let german = Locale(identifier: "de")
        let alert = screen(
            Text("page").alert("label.error", isPresented: .constant(true)) { Button("OK") {} }
                .environment(\.locale, german))
        #expect(alert.contains("Fehler"), "\(alert)")
        let dialog = screen(
            Text("page").confirmationDialog("label.warning", isPresented: .constant(true), titleVisibility: .visible) {
                Button("OK") {}
            }
            .environment(\.locale, german))
        #expect(dialog.contains("Warnung"), "\(dialog)")
    }

    /// A computed `String`, which an alert displays as written.
    private func verbatim(_ text: String) -> String { text }
}
