import Foundation
var s = AttributedString("hello")
s.link = URL(string: "https://x")
s.inlinePresentationIntent = .stronglyEmphasized
let r = s.runs.map { ($0.link, $0.inlinePresentationIntent) }
enum MyKey: AttributedStringKey { typealias Value = Int; static let name = "my" }
extension AttributeScopes { struct TUIAttrs: AttributeScope { let my: MyKey; let foundation: FoundationAttributes } ; var tui: TUIAttrs.Type { TUIAttrs.self } }
extension AttributeDynamicLookup { subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.TUIAttrs, T>) -> T { self[T.self] } }
s.my = 3
print(r, s)
