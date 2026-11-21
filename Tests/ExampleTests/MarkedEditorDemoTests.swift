//  🖥️ TUI — A Terminal UI framework for Swift
//  MarkedEditorDemoTests.swift
//
//  The Text Input page's marked, highlighted editor: the app's check for
//  brackets that do not match, and the section on the page.
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Example's marked editor")
struct MarkedEditorDemoTests {
    /// The characters `unmatchedBrackets` finds in `text`, as offsets.
    static func found(in text: String) -> [Int] {
        MarkedEditorDemo.unmatchedBrackets(in: text).map { text.distance(from: text.startIndex, to: $0.lowerBound) }
    }

    @Test("The sample has one bracket too many: the second of `]]`")
    func sample() throws {
        let sample = MarkedEditorDemo.sample
        let ranges = MarkedEditorDemo.unmatchedBrackets(in: sample)
        let extra = try #require(sample.range(of: "]]"))
        #expect(ranges == [sample.index(after: extra.lowerBound)..<extra.upperBound])
    }

    @Test("Closers that close nothing or the other kind, and openers left open, are found; brackets in strings are not")
    func brackets() {
        #expect(Self.found(in: "{[]}").isEmpty)
        #expect(Self.found(in: "]") == [0])
        #expect(Self.found(in: "[}") == [0, 1], "the closer of the wrong kind, and the opener it leaves open")
        #expect(Self.found(in: #"{"a": "]\"}"}"#).isEmpty, "inside a string, past an escaped quote")
        #expect(Self.found(in: "\"open\n]") == [6], "a string ends at its line's end")
    }

    @Test("The Text Input page has the section, which counts the sample's one problem")
    func section() {
        let app = TestApp(width: 100, height: 300) { TextInputPage() }
        #expect(app.screen.contains(L("page.textInput.marksSection")), "\(app.screen)")
        let count = L("page.textInput.marksCount %@").replacingOccurrences(of: "%@", with: "1")
        #expect(app.screen.contains(count), "\(app.screen)")
        #expect(app.screen.contains(#""languages": ["en", "de""#), "\(app.screen)")
    }
}

#endif
