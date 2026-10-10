//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PrimitiveButtonStyleTests.swift
//
//  SwiftUI's built-in button styles under SwiftUI's names, and the
//  PrimitiveButtonStyle protocol they belong to: a style that is the whole
//  button, and that builds the button it was applied over with
//  `Button(configuration)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// The example from SwiftUI's documentation of `Button(_:)`: the current
/// button, with a border added.
private struct RedBorderedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .border(.red)
    }
}

/// A style that draws the label alone and leaves operating it to nothing — so
/// the button is whatever the body is.
private struct LabelOnlyButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("~")
            configuration.label
        }
    }
}

/// Composes a built-in style's body, as a SwiftUI style may.
private struct ComposesBorderless: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BorderlessButtonStyle().makeBody(configuration: configuration)
    }
}

@MainActor
private final class Tally {
    var count = 0
}

@MainActor
@Suite("PrimitiveButtonStyle")
struct PrimitiveButtonStyleTests {

    private func lines<V: View>(_ view: V, context: RenderContext? = nil) -> [String] {
        renderToBuffer(view, context: context ?? makeRenderContext(width: 30, height: 4))
            .lines.map { $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
    }

    private func ansi<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 4)).lines.joined()
    }

    @Test("Bordered and automatic draw the bracketed button")
    func borderedIsTheBracketedButton() {
        let bordered = lines(Button("Go") {}.buttonStyle(.bordered))
        #expect(bordered == lines(Button("Go") {}))
        #expect(bordered == lines(Button("Go") {}.buttonStyle(.automatic)))
        #expect(bordered.first?.contains("Go") == true && bordered.first != "Go")
    }

    @Test("Bordered prominent draws the bracketed button bold")
    func borderedProminentIsBold() {
        #expect(ansi(Button("Go") {}.buttonStyle(.borderedProminent)).contains("\u{1B}[1"))
    }

    @Test("Borderless and plain draw no caps, and only borderless is tinted")
    func unborderedStyles() {
        #expect(lines(Button("Go") {}.buttonStyle(.borderless)).first?.hasSuffix("Go") == true)
        #expect(lines(Button("Go") {}.buttonStyle(.plain)).first?.hasSuffix("Go") == true)
        // Unfocused, which is where they differ: focus tints both.
        func unfocused<V: View>(_ view: V) -> String {
            let context = makeRenderContext(width: 30, height: 4)
            context.environment.focusManager!.register(FocusSentinel())
            return renderToBuffer(view, context: context).lines.joined()
        }
        let borderless = unfocused(Button("Go") {}.buttonStyle(.borderless))
        let plain = unfocused(Button("Go") {}.buttonStyle(.plain))
        #expect(borderless != plain)
        #expect(plain.hasSuffix("Go") || plain.contains("Go\u{1B}[0m"), "the label in the ordinary colour")
    }

    @Test("The link style underlines its label")
    func linkUnderlines() {
        let drawn = ansi(Button("Go") {}.buttonStyle(.link))
        let underline = /\u{1B}\[(?:[0-9]+;)*4(?:;[0-9]+)*m/
        #expect(drawn.contains(underline), "\(drawn.debugDescription)")
    }

    @Test("A style written as a value, not a static, resolves unambiguously")
    func explicitValueCompiles() {
        #expect(lines(Button("Go") {}.buttonStyle(PlainButtonStyle()))
            == lines(Button("Go") {}.buttonStyle(.plain)))
    }

    @Test("A theme can name a built-in style")
    func themeNamesBuiltIn() {
        let themed = Button("Go") {}.theme(Theme(palette: SystemPalette(.green), buttonStyle: .plain))
        #expect(lines(themed).first?.hasSuffix("Go") == true)
    }

    @Test("Button(configuration) draws the button the style was applied over")
    func wrapsTheOuterStyle() {
        let wrapped = lines(Button("Go") {}.buttonStyle(RedBorderedButtonStyle()))
        #expect(wrapped.count >= 3, "a border is three rows")
        #expect(wrapped[1].contains("Go") && wrapped[1] != "│Go│", "inside it, the default button")
        let overPlain = lines(Button("Go") {}.buttonStyle(RedBorderedButtonStyle()).buttonStyle(.plain))
        #expect(overPlain[1].contains("Go"))
        #expect(overPlain[1] != wrapped[1], "inside it now, the plain button")
    }

    @Test("A style that draws only the label is the whole button")
    func labelOnly() {
        #expect(lines(Button("Go") {}.buttonStyle(LabelOnlyButtonStyle())).first == "~Go")
    }

    @Test("The nearest buttonStyle wins, whichever kind it is")
    func nearestWins() {
        #expect(lines(Button("Go") {}.buttonStyle(LabelOnlyButtonStyle()).buttonStyle(.bordered)).first
            == "~Go")
        #expect(lines(Button("Go") {}.buttonStyle(.plain).buttonStyle(LabelOnlyButtonStyle())).first?
            .hasSuffix("Go") == true)
        #expect(lines(Button("Go") {}.buttonStyle(.plain).buttonStyle(LabelOnlyButtonStyle())).first
            != "~Go")
    }

    @Test("A style composing a built-in's body gets a button in that style")
    func composesBuiltIn() {
        #expect(lines(Button("Go") {}.buttonStyle(ComposesBorderless()))
            == lines(Button("Go") {}.buttonStyle(.borderless)))
    }

    @Test("A wrapped button is one focus stop, and the keyboard triggers it")
    func oneStopAndKeyboard() throws {
        let context = makeRenderContext(width: 30, height: 4)
        let tally = Tally()
        _ = lines(Button("Go") { tally.count += 1 }.buttonStyle(RedBorderedButtonStyle()), context: context)
        let focus = try #require(context.environment.focusManager)
        let first = focus.currentFocusedID
        focus.focusNext()
        #expect(focus.currentFocusedID == first, "one focus stop, not one per button view")
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(tally.count == 1)
    }
}
