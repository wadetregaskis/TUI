// Lane MDATTRS: how Foundation's Markdown parser DECODES the attributes of
// `^[text](attributes)` for a scope that declares keys of its own (a
// String `foregroundColor` and a Bool `dim`, both Markdown-decodable): the
// grammar it accepts, which of two equal keys wins, how nesting, emphasis
// and links combine, and what throws. Parsed with
// `.inlineOnlyPreservingWhitespace`. Run on macOS 15.8.1 (decode.out):
//   xcrun swiftc -o /tmp/decode decode.swift && /tmp/decode
import Foundation
enum ColorKey: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    typealias Value = String
    static let name = "foregroundColor"
}
enum DimKey: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    typealias Value = Bool
    static let name = "dim"
}
extension AttributeScopes {
    struct ProbeAttributes: AttributeScope {
        let foregroundColor: ColorKey
        let dim: DimKey
        let foundation: FoundationAttributes
    }
}
let cases = [
    "^[x](foregroundColor: red)",
    "^[x](foregroundColor: \"red\")",
    "^[x](foregroundColor: 'red')",
    "^[x](foregroundColor: \"a (b), c\", dim: true)",
    "^[x](foregroundColor: \"a\\)b\", dim: true)",
    "^[x](foregroundColor: \"a\\\\b\")",
    "^[x](dim: true, foregroundColor: 3)",
    "^[x](dim: 1)",
    "^[x](dim: \"true\")",
    "^[x](dim: true b: 2)",
    "^[x](inflect: true, dim: true)",
    "^[x](zzz: {a: [1, 2]}, dim: true)",
    "^[a ^[b](dim: false)](dim: true)",
    "^[a ^[b](foregroundColor: blue)](dim: true, foregroundColor: red)",
    "**^[a](dim: true)**",
    "^[**a** b](dim: true)",
    "[^[a](dim: true)](https://x.y)",
    "^[[a](https://x.y)](dim: true)",
    "^[x](dim: true, dim: false)",
    "^[x](\"dim\": true)",
    "^[x](foregroundColor: #ff0000)",
    "^[x](foregroundColor: \"#ff0000\")",
    "^[x](dim: true,)",
    "^[x](foregroundColor: \"\\u0041\")",
]
for text in cases {
    do {
        let s = try AttributedString(markdown: text, including: \.probe, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        var parts: [String] = []
        for run in s.runs {
            parts.append("\(String(s[run.range].characters).debugDescription) fg=\(run.foregroundColor.map { $0.debugDescription } ?? "-") dim=\(run.dim.map(String.init) ?? "-") intent=\(run.inlinePresentationIntent.map { String($0.rawValue) } ?? "-") link=\(run.link?.absoluteString ?? "-")")
        }
        print(text, "->", parts.joined(separator: " | "))
    } catch {
        print(text, "-> THROWS", error)
    }
}
extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.ProbeAttributes, T>) -> T { self[T.self] }
}
extension AttributeScopes {
    var probe: ProbeAttributes.Type { ProbeAttributes.self }
}
