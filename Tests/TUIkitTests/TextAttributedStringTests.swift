//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextAttributedStringTests.swift
//
//  `Text(AttributedString)` and SwiftUI's attribute scope: each run of the
//  string draws with its own attributes, and those take precedence over the
//  text's modifiers — SwiftUI's rule, measured on macOS 15.8.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("Text from an AttributedString")
struct TextAttributedStringTests {

    private let red = Color.rgb(200, 20, 20)
    private let blue = Color.rgb(20, 20, 200)
    private let yellow = Color.rgb(220, 200, 20)

    private func lines(_ text: Text, width: Int = 40) -> [String] {
        renderToBuffer(text, context: makeRenderContext(width: width, height: 4)).lines
    }

    /// The on/off attributes (1 bold … 9 strikethrough) in force on the first
    /// cell of `word`.
    private func attributes(of word: String, in lines: [String]) -> Set<Int> {
        guard let state = sgrState(of: word, in: lines) else { return [] }
        let parameters = state.parameters.split(separator: ";").compactMap { Int($0) }
        var result: Set<Int> = []
        var index = 0
        while index < parameters.count {
            let parameter = parameters[index]
            if parameter == 38 || parameter == 48 {
                index += index + 1 < parameters.count && parameters[index + 1] == 2 ? 5 : 3
                continue
            }
            if (1...9).contains(parameter) { result.insert(parameter) }
            index += 1
        }
        return result
    }

    private func parameters(of word: String, in lines: [String]) -> String {
        sgrState(of: word, in: lines)?.parameters ?? ""
    }

    private func codes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    private func attributed(_ pieces: (String, (inout AttributedString) -> Void)...) -> AttributedString {
        var result = AttributedString()
        for (text, edit) in pieces {
            var piece = AttributedString(text)
            edit(&piece)
            result += piece
        }
        return result
    }

    // MARK: - The scope

    /// The key an attribute's dynamic member names.
    ///
    /// Reached through the lookup rather than spelled, because on macOS this
    /// suite sees SwiftUICore's scope of the same name too (see the note on
    /// `AttributeScopes.SwiftUIAttributes`) and the spelled type is ambiguous;
    /// the lookup is what an app's `string.foregroundColor` goes through.
    private func key<Key: AttributedStringKey>(_ path: KeyPath<AttributeDynamicLookup, Key>) -> Key.Type {
        Key.self
    }

    @Test("The scope's keys are SwiftUI's, by name")
    func keyNames() {
        // An archived attributed string names its keys; these are the names
        // SwiftUI's own scope reports (measured on macOS 15.8).
        #expect(key(\.foregroundColor).name == "SwiftUI.ForegroundColor")
        #expect(key(\.backgroundColor).name == "SwiftUI.BackgroundColor")
        #expect(key(\.font).name == "SwiftUI.Font")
        #expect(key(\.underlineStyle).name == "SwiftUI.UnderlineStyle")
        #expect(key(\.strikethroughStyle).name == "SwiftUI.StrikethroughStyle")
    }

    @Test("Attributes are set and read through dynamic lookup, as TUIkit's types")
    func dynamicLookup() {
        var string = AttributedString("x")
        string.foregroundColor = .red
        string.backgroundColor = .blue
        string.font = .headline
        string.underlineStyle = .single
        string.strikethroughStyle = .single
        let foreground: Color? = string.foregroundColor
        let background: Color? = string.backgroundColor
        let font: Font? = string.font
        #expect(foreground == .red)
        #expect(background == .blue)
        #expect(font == .headline)
        #expect(string.underlineStyle == .single)
        #expect(string.strikethroughStyle == .single)
        // …through a container, and through the scope's own property.
        let container = AttributeContainer().foregroundColor(.green)
        string.mergeAttributes(container)
        #expect(string.foregroundColor == .green)
        string.swiftUI.foregroundColor = .yellow
        #expect(string.foregroundColor == .yellow)
    }

    // MARK: - What a run draws

    @Test("A string with no attributes is a plain text")
    func plainString() {
        let text = Text(AttributedString("Hello"))
        #expect(text.content == "Hello")
        #expect(text.runs == nil)
        #expect(lines(text) == lines(Text(verbatim: "Hello")))
    }

    @Test("Each run keeps its own colours")
    func colours() {
        let text = Text(
            attributed(
                ("crimson ", { $0.foregroundColor = red }),
                ("navy ", { $0.foregroundColor = blue }),
                ("marked", { $0.backgroundColor = yellow })))
        let drawn = lines(text)
        #expect(text.content == "crimson navy marked")
        #expect(parameters(of: "crimson", in: drawn).contains(codes(red)))
        #expect(parameters(of: "navy", in: drawn).contains(codes(blue)))
        #expect(!parameters(of: "navy", in: drawn).contains(codes(red)))
        #expect(sgrState(of: "marked", in: drawn)?.renderedBackground == renderedBackground(of: yellow))
        #expect(sgrState(of: "navy", in: drawn)?.namesBackground == false)
    }

    @Test("Underline and strikethrough reach only their own runs")
    func lineStyles() {
        let text = Text(
            attributed(
                ("under ", { $0.underlineStyle = .single }),
                ("through ", { $0.strikethroughStyle = .single }),
                ("plain", { _ in })))
        let drawn = lines(text)
        #expect(attributes(of: "under", in: drawn) == [4])
        #expect(attributes(of: "through", in: drawn) == [9])
        #expect(attributes(of: "plain", in: drawn).isEmpty)
    }

    @Test("A run's font draws as its intensity")
    func fonts() {
        let text = Text(
            attributed(
                ("heading ", { $0.font = .headline }),
                ("body ", { $0.font = .body }),
                ("caption", { $0.font = .caption })))
        let drawn = lines(text)
        #expect(attributes(of: "heading", in: drawn) == [1])
        #expect(attributes(of: "body", in: drawn).isEmpty)
        #expect(attributes(of: "caption", in: drawn) == [2])
    }

    @Test("Neighbouring runs drawn alike merge into one")
    func merging() {
        // Foundation splits runs on attributes a terminal cannot draw; those
        // must not become runs that differ in nothing.
        var string = AttributedString("ab")
        string.foregroundColor = .red
        string.append(AttributedString("cd", attributes: AttributeContainer().foregroundColor(.red)))
        #expect(Text(string).runs?.count == 1)
    }

    // MARK: - Precedence

    @Test("The string's colour wins over the text's, which fills in the rest")
    func attributeColourWins() {
        let text = Text(attributed(("own ", { $0.foregroundColor = blue }), ("rest", { _ in })))
            .foregroundStyle(red)
        let drawn = lines(text)
        #expect(parameters(of: "own", in: drawn).contains(codes(blue)))
        #expect(parameters(of: "rest", in: drawn).contains(codes(red)))
    }

    @Test("A modifier combines with what the string does not state")
    func modifiersCombine() {
        let text = Text(attributed(("first ", { $0.underlineStyle = .single }), ("second", { _ in }))).italic()
        let drawn = lines(text)
        #expect(attributes(of: "first", in: drawn) == [3, 4])
        #expect(attributes(of: "second", in: drawn) == [3])
    }

    @Test("A modifier cannot take back what the string states")
    func stateWins() {
        // SwiftUI, measured: `.underline(false)` leaves an underlined run
        // underlined, and a run's font beats the text's.
        let text = Text(attributed(("kept", { $0.underlineStyle = .single; $0.font = .headline })))
            .underline(false)
            .font(.caption)
        #expect(attributes(of: "kept", in: lines(text)) == [1, 4])
    }

    @Test("Concatenation keeps each part's attributes")
    func concatenation() {
        let joined =
            Text(attributed(("alpha ", { $0.foregroundColor = red })))
            + Text(verbatim: "beta").bold()
        let drawn = lines(joined)
        #expect(joined.content == "alpha beta")
        #expect(parameters(of: "alpha", in: drawn).contains(codes(red)))
        #expect(attributes(of: "beta", in: drawn) == [1])
        #expect(!parameters(of: "beta", in: drawn).contains(codes(red)))
    }

    @Test("A live text concatenated with an attributed one stays live")
    func liveStaysLive() {
        let joined =
            Text(attributed(("Due ", { $0.underlineStyle = .single })))
            + Text(Date(timeIntervalSinceNow: 3600), style: .relative)
        #expect(joined.isLive)
    }

    @Test("It wraps as one text")
    func wraps() {
        let text = Text(attributed(("alpha beta ", { $0.underlineStyle = .single }), ("gamma delta", { _ in })))
        let drawn = lines(text, width: 10)
        #expect(drawn.count > 1)
        #expect(attributes(of: "beta", in: drawn) == [4])
        #expect(attributes(of: "delta", in: drawn).isEmpty)
    }

    // MARK: - A format style's attributed output

    /// A style whose output says how it looks: the number in red.
    private struct Highlighted: FormatStyle {
        func format(_ value: Int) -> AttributedString {
            var string = AttributedString("\(value)")
            string.foregroundColor = .rgb(200, 20, 20)
            return string
        }
    }

    @Test("Text(_:format:) draws an attributed output's attributes")
    func formattedOutput() {
        let text = Text(42, format: Highlighted())
        #expect(text.content == "42")
        #expect(text.runs?.first?.style.foregroundColor == red)
        // Foundation's own field attributes say what a run is, not how it
        // looks: a plain text, as before.
        let date = Date(timeIntervalSinceReferenceDate: 0)
        #expect(Text(date, format: .dateTime.year().attributed).runs == nil)
    }

    // MARK: - Foundation's inline intents

    #if canImport(Darwin)
        @Test("Foundation's inline intents draw as SwiftUI draws them")
        func inlineIntents() throws {
            let string = try AttributedString(
                markdown: "**strong** *em* ~~struck~~ `code`",
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let drawn = lines(Text(string))
            #expect(attributes(of: "strong", in: drawn) == [1])
            #expect(attributes(of: "em", in: drawn) == [3])
            #expect(attributes(of: "struck", in: drawn) == [9])
            // Code is monospaced, which every cell already is.
            #expect(attributes(of: "code", in: drawn).isEmpty)
        }

        @Test("A modifier cannot unbold a strongly emphasised run")
        func intentWins() throws {
            // SwiftUI, measured: `.bold(false)` leaves `**ab**` bold.
            let string = try AttributedString(markdown: "**ab**")
            #expect(attributes(of: "ab", in: lines(Text(string).bold(false))) == [1])
        }
    #endif
}
