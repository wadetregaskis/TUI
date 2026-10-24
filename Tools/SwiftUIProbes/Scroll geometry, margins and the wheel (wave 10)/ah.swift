struct IDType: Equatable {
    let type: any (Hashable & Sendable).Type
    static func == (l: IDType, r: IDType) -> Bool { ObjectIdentifier(l.type) == ObjectIdentifier(r.type) }
}
func cast<T: Hashable & Sendable>(_ t: T.Type, _ v: AnyHashable) -> (any Hashable & Sendable)? { v.base as? T }
struct P {
    var idType: IDType?
    init(idType: (some Hashable & Sendable).Type = Never.self) {
        self.idType = idType == Never.self ? nil : IDType(type: idType)
    }
    init(id: some Hashable & Sendable) { idType = IDType(type: type(of: id)) }
}
let p = P(idType: Int.self)
if let t = p.idType { print(cast(t.type, AnyHashable(5)) as Any, cast(t.type, AnyHashable("x")) as Any) }
print(P().idType == nil, P(id: "s").idType!.type)
