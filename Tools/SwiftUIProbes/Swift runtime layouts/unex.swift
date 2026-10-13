import Foundation

protocol P: AnyObject {}
final class Native: P { deinit { print("native deinit") } }
final class ObjC: NSObject, P { deinit { print("objc deinit") } }

struct Holder {
    unowned let x: any P
    let marker: Int = 0x1234
}
struct HolderAny {
    unowned let x: AnyObject
}

func words<T>(_ v: T) -> [String] {
    withUnsafeBytes(of: v) { raw in
        stride(from: 0, to: raw.count, by: 8).map { String(raw.load(fromByteOffset: $0, as: UInt.self), radix: 16) }
    }
}
func addr(_ o: AnyObject) -> String { String(UInt(bitPattern: Unmanaged.passUnretained(o).toOpaque()), radix: 16) }

do {
    let n = Native()
    let h = Holder(x: n)
    print("native", addr(n), words(h))
    withExtendedLifetime(n) {}
    let ha = HolderAny(x: n)
    print("native any", addr(n), words(ha))
}
var kept: Holder?
do {
    let o = ObjC()
    let h = Holder(x: o)
    kept = h
    print("objc", addr(o), words(h))
    withExtendedLifetime(o) {}
}
print("objc after dealloc", words(kept!))
let s = NSNumber(value: 3) as AnyObject
let hs = HolderAny(x: s)
print("tagged", addr(s), words(hs))
