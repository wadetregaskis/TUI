// B86's open item: what Foundation's Markdown parser does with Apple's
// `^[text](attributes)` when the attributes do not parse, and how it finds the
// `)` that ends them. Each case is parsed with `.inlineOnlyPreservingWhitespace`
// and its characters printed. Run on macOS 15.8 (attrs.out).
import Foundation
let cases = [
    "a ^[x](a: (1)) b",
    "a ^[x](a: (1) b",
    "a ^[x](a: 1)) b",
    "a ^[x](a: \"(\") b",
    "a ^[x](a: \")\") b",
    "a ^[x](a: \\)) b",
    "a ^[x](a:\n1) b",
    "a ^[x\n](a: 1) b",
    "a ^[x](<a: 1>) b",
    "a ^[[y]](a: 1) b",
    "a ^[x](a: 1 \"t\") b",

    "a ^[x](inflect: true) b",
    "a ^[x](garbage) b",
    "a ^[x]() b",
    "a ^[x](a:) b",
    "a ^[x]({a: 1}) b",
    "a ^[x](a: 1,) b",
    "a ^[x](a 1) b",
    "a ^[x](a: 1 b: 2) b",
    "a ^[x](\"a\": 1) b",
    "a ^[x](a: [1, 2]) b",
    "a ^[x](a: {b: 1}) b",
    "a ^[x](a: 'q') b",
    "a ^[x](a: undefined) b",
    "a ^[x](a: 1)(b: 2) b",
    "a ^[x](a: 1 b",
    "a ^[x] (a: 1) b",
    "a ^[x](a: \"unterminated) b",
    "a ^[x](1) b",
    "a ^[x](a: 1}) b",
    "a ^[x](/* c */ a: 1) b",
    "a ^[x](a: NaN) b",
    "a ^[x](a: Infinity) b",
    "a ^[x](a: 0x1F) b",
    "a ^[x](a: .5) b",
    "a ^[x](a: +1) b",
    "a ^[x](a: 1e3) b",
    "a ^[x](a: True) b",
    "a ^[x](a: null) b",
    "a ^[x](a-b: 1) b",
    "a ^[x]($a: 1) b",
]
for text in cases {
    do {
        let s = try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        print(text.padding(toLength: 34, withPad: " ", startingAt: 0), "->", String(s.characters).debugDescription)
    } catch {
        print(text.padding(toLength: 34, withPad: " ", startingAt: 0), "-> THROWS", error)
    }
}
