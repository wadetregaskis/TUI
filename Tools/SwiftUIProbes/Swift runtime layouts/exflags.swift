// DYNVFIX probe: an existential type's metadata flags (ExistentialTypeFlags at the word after the kind),
// and how a nil optional of an existential and of a class looks in memory.
protocol P {}
protocol CP: AnyObject {}
protocol Q {}
struct S: P, Q { var a = 1, b = 2, c = 3, d = 4 }
final class K: P, CP {}
class Base: P {}
final class Sub: Base {}

func flags(_ t: Any.Type) -> String {
    let m = unsafeBitCast(t, to: UnsafeRawPointer.self)
    let kind = m.load(as: UInt.self)
    let f = m.load(fromByteOffset: MemoryLayout<Int>.size, as: UInt32.self)
    return "\(t): kind=0x\(String(kind, radix: 16)) flags=0x\(String(f, radix: 16)) size=\(sizeOf(t))"
}
func sizeOf(_ t: Any.Type) -> Int { func s<T>(_: T.Type) -> Int { MemoryLayout<T>.size }; return _openExistential(t, do: s) }
for t: Any.Type in [Any.self, (any P).self, AnyObject.self, (any CP).self, (any Error).self, (any P & AnyObject).self, (any P & Q).self, (any Base & P).self] {
    print(flags(t))
}
func words<T>(_ v: T) -> [String] {
    withUnsafeBytes(of: v) { b in stride(from: 0, to: b.count, by: 8).map { String(b.load(fromByteOffset: $0, as: UInt.self), radix: 16) } }
}
let np: (any P)? = nil
let na: Any? = nil
let no: AnyObject? = nil
let ncp: (any CP)? = nil
let nk: K? = nil
print("nil any P?", words(np)); print("nil Any?", words(na)); print("nil AnyObject?", words(no)); print("nil any CP?", words(ncp)); print("nil K?", words(nk))
let sp: any P = S(); print("any P(S)", words(sp), "metadata of S", String(UInt(bitPattern: unsafeBitCast(S.self, to: Int.self)), radix: 16))
let sub: any P = Sub() as Base; print("any P(Sub as Base)", words(sub), "Base", String(UInt(bitPattern: unsafeBitCast(Base.self as Any.Type, to: Int.self)), radix: 16), "Sub", String(UInt(bitPattern: unsafeBitCast(Sub.self as Any.Type, to: Int.self)), radix: 16))
