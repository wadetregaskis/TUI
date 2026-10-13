import Foundation

protocol P: AnyObject {}
class C: P { let n: Int; init(_ n: Int) { self.n = n } }
final class D: C {}
class O: NSObject, P {}

protocol HeldReference { static func load(at address: UnsafeRawPointer) -> AnyObject? }
enum WeakField<T: AnyObject>: HeldReference {
    struct Box { weak var value: T? }
    static func load(at address: UnsafeRawPointer) -> AnyObject? { address.assumingMemoryBound(to: Box.self).pointee.value }
}
enum UnownedField<T: AnyObject>: HeldReference {
    struct Box { unowned let value: T }
    static func load(at address: UnsafeRawPointer) -> AnyObject? { address.assumingMemoryBound(to: Box.self).pointee.value }
}
enum OptionalUnownedField<T: AnyObject>: HeldReference {
    struct Box { unowned var value: T? }
    static func load(at address: UnsafeRawPointer) -> AnyObject? { address.assumingMemoryBound(to: Box.self).pointee.value }
}
func weakLoader<T: AnyObject>(_: T.Type) -> any HeldReference.Type { WeakField<T>.self }
func unownedLoader<T: AnyObject>(_: T.Type) -> any HeldReference.Type { UnownedField<T>.self }

struct S {
    var pad = 7
    weak var wc: C?
    weak var we: (any P)?
    unowned let uc: C
    unowned var uco: C?
    unowned let ue: any P
    weak var wo: O?
    unowned let ueo: any P
}

func offset(_ name: String) -> Int {
    // MemoryLayout offsets
    switch name {
    case "wc": return 8
    case "we": return 16
    case "uco": return 40
    case "wo": return 64
    default: return -1
    }
}

let c = D(1)
let o = O()
var s = S(wc: c, we: c, uc: c, uco: c, ue: c, wo: o, ueo: o)
withUnsafePointer(to: &s) { p in
    let base = UnsafeRawPointer(p)
    print("wc", WeakField<C>.load(at: base + offset("wc")) === c)
    print("wc as AnyObject", WeakField<AnyObject>.load(at: base + offset("wc")) === c)
    print("uco as AnyObject", OptionalUnownedField<AnyObject>.load(at: base + offset("uco")) === c)
    print("we as AnyObject", WeakField<AnyObject>.load(at: base + offset("we")) === c)
    print("uco", OptionalUnownedField<C>.load(at: base + offset("uco")) === c)
    print("wo", WeakField<O>.load(at: base + offset("wo")) === o)
    print("wo as AnyObject", WeakField<AnyObject>.load(at: base + offset("wo")) === o)
}
// unowned offsets via mirror-free: compute from known layout: print all words
withUnsafeBytes(of: s) { raw in
    print("size", raw.count, stride(from: 0, to: raw.count, by: 8).map { String(raw.load(fromByteOffset: $0, as: UInt.self), radix: 16) })
}
print("c", String(UInt(bitPattern: Unmanaged.passUnretained(c).toOpaque()), radix: 16), "o", String(UInt(bitPattern: Unmanaged.passUnretained(o).toOpaque()), radix: 16))
// dead weak
var s2: S
do {
    let c2 = C(2)
    s2 = S(wc: c2, we: c2, uc: c, uco: c, ue: c, wo: nil, ueo: c)
}
withUnsafePointer(to: &s2) { p in
    let base = UnsafeRawPointer(p)
    print("dead wc nil", WeakField<C>.load(at: base + offset("wc")) == nil)
    print("dead we nil", WeakField<AnyObject>.load(at: base + offset("we")) == nil)
    print("nil wo", WeakField<O>.load(at: base + offset("wo")) == nil)
}
// unowned non-optional: offsets by scanning words for c's address
withUnsafePointer(to: &s) { p in
    let base = UnsafeRawPointer(p)
    let target = UInt(bitPattern: Unmanaged.passUnretained(c).toOpaque())
    for off in stride(from: 0, to: MemoryLayout<S>.size, by: 8) where base.load(fromByteOffset: off, as: UInt.self) == target {
        print("word at", off, "C native load", UnownedField<C>.load(at: base + off) === c, "AnyObject load", UnownedField<AnyObject>.load(at: base + off) === c)
    }
}
