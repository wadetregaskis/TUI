import Foundation
let r = CGRect(x: 0, y: 0, width: 1, height: 1)
var s = AttributedString("**b** _i_ `c` [l](https://x)")
let m = try? AttributedString(markdown: "**b** _i_")
let intents = m?.runs.map { $0.inlinePresentationIntent }
let l = m?.runs.map { $0.link }
let at = AffineTransform(translationByX: 1, byY: 2)
print(r, s, intents as Any, l as Any, at)
