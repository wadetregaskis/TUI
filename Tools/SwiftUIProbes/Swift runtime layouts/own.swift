import Foundation
@_silgen_name("swift_getMetadataKind") func kindOf(_: Any.Type) -> UInt

class Plain {}
final class Sub: Plain {}
class ObjCish: NSObject {}
final class ObjCSub: ObjCish {}
struct S<T> { weak var w: Plain?; unowned let o: Plain; unowned(unsafe) let u: Plain; unowned var oo: Plain?; var s: Plain; let g: T; weak var wo: ObjCish? }
class K { var a = 1; weak var w: Plain?; unowned(unsafe) var u: Plain; init(_ p: Plain) { u = p } }
class K2: K { unowned let o: Plain; init(o: Plain) { self.o = o; super.init(o) } }

func rel(_ p: UnsafeRawPointer) -> UnsafeRawPointer? { let o = p.load(as: Int32.self); return o == 0 ? nil : p + Int(o) }
func mangled(_ p: UnsafeRawPointer) -> String {
  var s = ""; var i = 0
  while true { let b = p.load(fromByteOffset: i, as: UInt8.self); if b == 0 { break }
    if b >= 1 && b <= 0x17 { s += "<sym\(b)>"; i += 5; continue }
    if b >= 0x18 && b <= 0x1f { s += "<abs\(b)>"; i += 1 + MemoryLayout<Int>.size; continue }
    s.append(Character(UnicodeScalar(b))); i += 1 }
  return s
}
func dump(_ t: Any.Type, descOffset: Int) {
  let md = unsafeBitCast(t, to: UnsafeRawPointer.self)
  let desc = md.load(fromByteOffset: descOffset, as: UnsafeRawPointer.self)
  let flags = desc.load(as: UInt32.self)
  print(t, "kind", flags & 0x1f)
  guard let fd = rel(desc + 16) else { print("no fields"); return }
  let rs = Int(fd.load(fromByteOffset: 10, as: UInt16.self)); let n = Int(fd.load(fromByteOffset: 12, as: UInt32.self))
  for i in 0..<n { let r = fd + 16 + i * rs
    let name = rel(r + 8).map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? "?"
    let m = rel(r + 4).map(mangled) ?? "-"
    print("  ", name, m) }
}
dump(S<Int>.self, descOffset: 8)
dump(K.self, descOffset: 64)
dump(K2.self, descOffset: 64)
dump(ObjCSub.self, descOffset: 64)
func chain(_ t: AnyClass) { var c: AnyClass? = t; while let x = c { print("  ", x, String(kindOf(x), radix: 16)); c = _getSuperclass(x) } }
chain(Sub.self); chain(ObjCSub.self)
