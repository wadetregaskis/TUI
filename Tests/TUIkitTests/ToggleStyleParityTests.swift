//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToggleStyleParityTests.swift
//
//  SwiftUI's toggle-style surface: `configuration.isOn` as a Bool with a
//  `$isOn` binding, built-in styles whose bodies compose, `Toggle(configuration)`
//  drawing the toggle a style was applied over, and the `.button` style.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

/// SwiftUI's documented `Toggle(_:)` example: the current toggle, bordered.
private struct RedBorderToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .border(.red)
    }
}

/// Composes a built-in style's body, as a SwiftUI style may.
private struct ComposesSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchToggleStyle().makeBody(configuration: configuration)
    }
}

/// Reads the state as SwiftUI source reads it: a Bool, and `$isOn` to bind.
private struct StateWords: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let binding: Binding<Bool> = configuration.$isOn
        return Text(verbatim: configuration.isOn == binding.wrappedValue
            ? (configuration.isOn ? "on" : "off") : "?")
    }
}

@MainActor
private final class Flag {
    var isOn = false
}

@MainActor
@Suite("Toggle style parity")
struct ToggleStyleParityTests {

    private func lines<V: View>(_ view: V, context: RenderContext? = nil) -> [String] {
        renderToBuffer(view, context: context ?? makeRenderContext(width: 30, height: 4))
            .lines.map { $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
    }

    private func binding(_ flag: Flag) -> Binding<Bool> {
        Binding(get: { flag.isOn }, set: { flag.isOn = $0 })
    }

    @Test("configuration.isOn is the state, and $isOn the binding to it")
    func isOnIsABool() {
        let flag = Flag()
        #expect(lines(Toggle("x", isOn: binding(flag)).toggleStyle(StateWords())).first == "off")
        flag.isOn = true
        #expect(lines(Toggle("x", isOn: binding(flag)).toggleStyle(StateWords())).first == "on")
    }

    @Test("A built-in style's body draws that style")
    func builtInBodiesCompose() {
        let flag = Flag()
        #expect(lines(Toggle("Wi-Fi", isOn: binding(flag)).toggleStyle(ComposesSwitch()))
            == lines(Toggle("Wi-Fi", isOn: binding(flag)).toggleStyle(.switch)))
    }

    @Test("Toggle(configuration) draws the toggle the style was applied over")
    func wrapsTheOuterStyle() {
        let flag = Flag()
        let overCheckbox = lines(Toggle("Wi-Fi", isOn: binding(flag)).toggleStyle(RedBorderToggleStyle()))
        let overSwitch = lines(
            Toggle("Wi-Fi", isOn: binding(flag)).toggleStyle(RedBorderToggleStyle()).toggleStyle(.switch))
        #expect(overCheckbox.count >= 3 && overCheckbox[1].contains("Wi-Fi"))
        #expect(overCheckbox[1].contains(lines(Toggle("Wi-Fi", isOn: binding(flag)))[0]),
                "inside the border, the default toggle")
        #expect(overSwitch[1].contains(lines(Toggle("Wi-Fi", isOn: binding(flag)).toggleStyle(.switch))[0]),
                "inside the border, the switch")
    }

    @Test("A wrapped toggle is one focus stop, and Space flips it once")
    func oneStopAndKeyboard() throws {
        let context = makeRenderContext(width: 30, height: 4)
        let flag = Flag()
        _ = lines(Toggle("Wi-Fi", isOn: binding(flag)).toggleStyle(RedBorderToggleStyle()), context: context)
        let focus = try #require(context.environment.focusManager)
        let first = focus.currentFocusedID
        focus.focusNext()
        #expect(focus.currentFocusedID == first, "one focus stop")
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .space)))
        #expect(flag.isOn)
    }

    @Test("The button style draws a bracketed button, prominent while on")
    func buttonStyle() {
        let flag = Flag()
        let context = makeRenderContext(width: 30, height: 4)
        context.environment.focusManager!.register(FocusSentinel())
        func ansi() -> String {
            renderToBuffer(Toggle("Bold", isOn: binding(flag)).toggleStyle(.button), context: context)
                .lines.joined()
        }
        let off = ansi()
        flag.isOn = true
        let on = ansi()
        #expect(off.stripped.contains("Bold") && off.stripped != "Bold", "a bracketed button")
        #expect(on != off, "on and off are drawn differently")
        #expect(on.contains("\u{1B}[1") && !off.contains("\u{1B}[1;"), "prominent (bold) while on")
    }
}
