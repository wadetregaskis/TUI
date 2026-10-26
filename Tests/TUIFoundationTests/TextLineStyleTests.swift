//  🖥️ TUI — A Terminal UI framework for Swift
//  TextLineStyleTests.swift
//
//  Underline patterns and line colours (W11b): what each spells, and how a
//  terminal that lacks a shape or a colour gets the plain line instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITerminalHost
@testable import TUITestSupport

@MainActor
@Suite("Text line styles")
struct TextLineStyleTests {

    /// Warp, as the owner read it: a double line, no other shape, no colour.
    private static let warp = LineStyleSupport(
        doubleUnderline: true, patternedUnderlines: false, underlineColour: false, strikethroughColour: false)

    /// The bytes `view` renders to on a terminal that draws `support`.
    private func bytes(
        _ view: some View, support: LineStyleSupport = .underlines, depth: ColorDepth = .truecolor
    ) -> String {
        var context = RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: TUIContext())
            .isolatingRenderCache()
        context.environment.lineStyleSupport = support
        return ColorDepth.withCurrent(depth) { renderToBuffer(view, context: context).lines.joined() }
    }

    /// The SGR parameters `view`'s text is drawn with, each sequence's split on
    /// `;` and flattened.
    private func parameters(
        _ view: some View, support: LineStyleSupport = .underlines, depth: ColorDepth = .truecolor
    ) -> [String] {
        let rendered = bytes(view, support: support, depth: depth)
        var result: [String] = []
        var rest = Substring(rendered)
        while let start = rest.range(of: "\u{1B}[") {
            let body = rest[start.upperBound...]
            guard let end = body.firstIndex(of: "m") else { break }
            result += body[..<end].split(separator: ";").map(String.init)
            rest = body[body.index(after: end)...]
        }
        return result
    }

    @Test(
        "Each pattern is the underline shape a terminal has",
        arguments: [
            (Text.LineStyle.Pattern.solid, "4"), (.double, "4:2"), (.curly, "4:3"), (.dot, "4:4"), (.dash, "4:5"),
            (.dashDot, "4:5"), (.dashDotDot, "4:5"),
        ])
    func patterns(pattern: Text.LineStyle.Pattern, parameter: String) {
        let drawn = parameters(Text("ab").underline(pattern: pattern))
        #expect(drawn.contains(parameter), "\(drawn)")
        #expect(drawn.filter { $0.hasPrefix("4") }.count == 1, "one underline code: \(drawn)")
    }

    @Test("The line's colour is SGR 58, spelled with colons")
    func colour() {
        let drawn = parameters(Text("ab").underline(pattern: .curly, color: .rgb(255, 0, 0)))
        #expect(drawn.contains("4:3") && drawn.contains("58:2::255:0:0"), "\(drawn)")
        // At sixteen colours, a named ink is spelled by its index: 58 has no
        // named form. `.red` is bright red there (91), index 9.
        let basic = parameters(Text("ab").underline(color: .red), depth: .basic16)
        #expect(basic.contains("58:5:9"), "\(basic)")
        // A palette colour is resolved, as the text's own colours are.
        let accent = parameters(Text("ab").underline(color: .palette.accent))
        #expect(accent.contains { $0.hasPrefix("58:2::") }, "\(accent)")
    }

    @Test("Warp gets its double line, a single line for any other shape, and no colour")
    func warp() {
        #expect(parameters(Text("ab").underline(pattern: .double), support: Self.warp).contains("4:2"))
        let curly = parameters(Text("ab").underline(pattern: .curly, color: .rgb(255, 0, 0)), support: Self.warp)
        #expect(curly.contains("4") && !curly.contains { $0.hasPrefix("4:") || $0.hasPrefix("58") }, "\(curly)")
    }

    @Test("Apple Terminal, and any terminal not measured, gets the plain line: never a 4:n or a 58")
    func plain() {
        for pattern in [Text.LineStyle.Pattern.double, .curly, .dot, .dash] {
            let drawn = bytes(Text("ab").underline(pattern: pattern, color: .rgb(1, 2, 3)), support: .plain)
            #expect(drawn.contains("\u{1B}[4m") || drawn.contains(";4m") || drawn.contains("[4;"), "\(drawn.debugDescription)")
            #expect(!drawn.contains("4:") && !drawn.contains("58"), "\(drawn.debugDescription)")
        }
    }

    @Test("A strikethrough is SGR 9 whatever its pattern, coloured only where 58 reaches it (iTerm2)")
    func strikethrough() {
        let struck = Text("ab").strikethrough(pattern: .dot, color: .rgb(0, 0, 255))
        let iTerm = parameters(struck, support: .all)
        #expect(iTerm.contains("9") && iTerm.contains("58:2::0:0:255"), "\(iTerm)")
        #expect(!iTerm.contains { $0.hasPrefix("4") }, "no underline: \(iTerm)")
        let ghostty = parameters(struck, support: .underlines)
        #expect(ghostty.contains("9") && !ghostty.contains { $0.hasPrefix("58") }, "\(ghostty)")
        // Both lines coloured: 58 is the underline's, so the underline's wins.
        let both = parameters(
            Text("ab").underline(color: .rgb(255, 0, 0)).strikethrough(color: .rgb(0, 0, 255)), support: .all)
        #expect(both.contains("58:2::255:0:0") && !both.contains("58:2::0:0:255"), "\(both)")
    }

    @Test("The nearest statement decides the line: whether, and how")
    func cascade() {
        let dotted = VStack { Text("ab") }.underline(pattern: .dot, color: .rgb(9, 9, 9))
        #expect(parameters(dotted).contains("4:4"))
        // A text's own plain underline beats the cascade's dotted one, colour and all.
        let own = VStack { Text("ab").underline() }.underline(pattern: .dot, color: .rgb(9, 9, 9))
        let drawn = parameters(own)
        #expect(drawn.contains("4") && !drawn.contains("4:4") && !drawn.contains { $0.hasPrefix("58") }, "\(drawn)")
        // And its `false` escapes it.
        let escaped = parameters(VStack { Text("ab").underline(false) }.underline(pattern: .dot))
        #expect(!escaped.contains { $0.hasPrefix("4") }, "\(escaped)")
        // The style cascade's two fields travel together.
        var attributes = StyleAttributes(underline: true, underlineStyle: Text.LineStyle(pattern: .dash))
        attributes = StyleAttributes(underline: false).merged(over: attributes)
        #expect(attributes.underlineLine == .some(nil))
    }

    @Test("An attributed run's line style is drawn, pattern and colour")
    func attributedRun() {
        var string = AttributedString("ab")
        string.underlineStyle = Text.LineStyle(pattern: .dash, color: .rgb(0, 255, 0))
        let drawn = parameters(Text(string))
        #expect(drawn.contains("4:5") && drawn.contains("58:2::0:255:0"), "\(drawn)")
    }

    @Test("Turning an underline on through the flag keeps a line already stated")
    func flagKeepsTheLine() {
        var style = TextStyle()
        style.underline = .some(Text.LineStyle(pattern: .curly))
        style.isUnderlined = true
        #expect(style.underline == .some(Text.LineStyle(pattern: .curly)))
        style.isUnderlined = false
        #expect(style.underline == .some(nil) && style.isUnderlined == false)
        style.isUnderlined = nil
        #expect(style.underline == nil)
    }
}
