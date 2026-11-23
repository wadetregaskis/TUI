//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorPickerLocaleTests.swift
//
//  The colour picker's and the gradient editor's own words are TUI's, in the
//  language a subtree's `\.locale` names, as a `Button(localized:)` is: they
//  were English literals in no table (hunt REST-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIColorPicker
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("The colour picker's words follow a locale", .rendersEnglishUI)
struct ColorPickerLocaleTests {
    private func drawn(_ view: some View, width: Int = 80, height: Int = 45) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
            .joined(separator: "\n")
    }

    private let german = Locale(identifier: "de")

    @Test("The colour panel's title, tabs and opacity row are in the subtree's language")
    func colourPanel() {
        let english = drawn(ColorPickerPanel(selection: .constant(.rgb(10, 20, 30)), isPresented: .constant(true)))
        for word in ["Colour", "Semantic", "Greyscale", "Named", "Web Safe", "Crayons", "Opacity"] {
            #expect(english.contains(word), "\(word): \(english)")
        }
        let panel = ColorPickerPanel(selection: .constant(.rgb(10, 20, 30)), isPresented: .constant(true))
            .environment(\.locale, german)
        let text = drawn(panel)
        for word in ["Farbe", "Semantisch", "Graustufen", "Benannt", "Websicher", "Farbstifte", "Deckkraft"] {
            #expect(text.contains(word), "\(word): \(text)")
        }
        for word in ["Colour", "Semantic", "Greyscale", "Crayons", "Opacity"] {
            #expect(!text.contains(word), "no English \(word): \(text)")
        }
    }

    @Test("A title the app gives is drawn as given")
    func givenTitle() {
        let panel = ColorPickerPanel("Tint" as String, selection: .constant(.rgb(1, 2, 3)), isPresented: .constant(true))
            .environment(\.locale, german)
        #expect(drawn(panel).contains("Tint"))
    }

    @Test("The gradient panel's default title is TUI's word for gradient")
    func gradientPanel() {
        let panel = GradientEditorPanel(
            gradient: .constant(Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])), isPresented: .constant(true))
        let english = drawn(panel)
        #expect(english.contains("Gradient"), "\(english.prefix(300))")
        let text = drawn(panel.environment(\.locale, german))
        #expect(text.contains("Verlauf"), "de.json's label.gradient: \(text.prefix(300))")
        #expect(!text.contains("Gradient"), "no English title: \(text.prefix(300))")
    }

    @Test("The 256 tab's toggle is in the subtree's language")
    func showNumbers() {
        let editor = _Palette256Editor(selection: .constant(.rgb(1, 2, 3)))
        #expect(drawn(editor, width: 60, height: 20).contains("Show numbers"))
        let text = drawn(editor.environment(\.locale, german), width: 60, height: 20)
        #expect(text.contains("Nummern anzeigen"), "\(text)")
    }
}
