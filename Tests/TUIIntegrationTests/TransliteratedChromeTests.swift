//  🖥️ TUI — A Terminal UI framework for Swift
//  TransliteratedChromeTests.swift
//
//  Under `TUI_PLAIN_TEXT=transliterate` the strings the framework draws without
//  a `Text` — a tab's title and badge, a list's empty placeholder and badges, a
//  spinner's label, a stepper's read-out — are spelled in ASCII as a `Text`'s
//  words are, and measured spelled. And a headless app spells them too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Framework strings under transliteration")
struct TransliteratedChromeTests {
    private func drawn(_ view: some View, width: Int = 40, height: Int = 8) -> String {
        let context = makeRenderContext(width: width, height: height) { environment, _ in
            environment.textSpelling = .ascii(.standard)
        }
        return renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
    }

    #if canImport(Darwin)
        @Test("A tab's title and badge, drawn by the strip, are spelled and the chip fits them")
        func tabTitle() {
            let lines = drawn(
                TabView(selection: .constant(0)) {
                    Tab("你好", value: 0) { Text(verbatim: "body") }.badge("新")
                    Tab("Мир", value: 1) { Text(verbatim: "other") }
                }
                .tabViewStyle(.compact))
            #expect(lines.contains("ni hao xin"), "\(lines)")
            #expect(lines.contains("Mir"), "\(lines)")
        }

        @Test("A list's empty placeholder and a row's badge are spelled")
        func listStrings() {
            let selection = Binding<String?>.constant(nil)
            let empty = drawn(List(selection: selection) { EmptyView() }.listEmptyPlaceholder("Пусто"))
            #expect(empty.contains("Pusto"), "\(empty)")
            let badged = drawn(List { Text(verbatim: "row").badge("新") })
            #expect(badged.contains("xin"), "\(badged)")
        }

        @Test("A spinner's label and a stepper's read-out are spelled")
        func spinnerAndStepper() {
            let spinner = drawn(Spinner("Загрузка"))
            #expect(spinner.contains("Zagruzka"), "\(spinner)")
            let stepper = drawn(Stepper("n", value: .constant(5), in: 0...9).stepperValueText("пять"))
            #expect(stepper.contains("pyat"), "\(stepper)")
        }

        @Test("A headless app spells text when its root asks, as the app runner's does")
        func headless() {
            let app = TestApp(width: 30, height: 3) { Text(verbatim: "你好 🙂") }
            app.headless.configureEnvironment { $0.spellTextInASCII() }
            #expect(app.screen.contains("ni hao :)"))
        }
    #endif
}
