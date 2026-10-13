// DYNVFIX probe: is swift_projectBox reserved (warning)? Does it give an indirect case's payload address?
@_silgen_name("swift_projectBox")
func _projectBox(_ box: UnsafeRawPointer) -> UnsafeMutableRawPointer

final class Box { var n = 1 }
struct Payload { var count = 0; var box = Box() }
indirect enum Ind { case on(Payload), off }
typealias ProjectEnumData = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Void
typealias InjectEnumTag = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void
var e = Ind.on(Payload(count: 5))
let m = unsafeBitCast(Ind.self, to: UnsafeRawPointer.self)
let vwt = m.load(fromByteOffset: -8, as: UnsafeRawPointer.self)
let project = unsafeBitCast(vwt.load(fromByteOffset: 96, as: UnsafeRawPointer.self), to: ProjectEnumData.self)
let inject = unsafeBitCast(vwt.load(fromByteOffset: 104, as: UnsafeRawPointer.self), to: InjectEnumTag.self)
withUnsafeMutablePointer(to: &e) { p in
    let raw = UnsafeMutableRawPointer(p)
    project(raw, m)
    let box = raw.load(as: UnsafeRawPointer.self)
    let payload = _projectBox(box).assumingMemoryBound(to: Payload.self)
    print("payload count:", payload.pointee.count, "box offset:", UnsafeRawPointer(payload) - box)
    inject(raw, 0, m)
}
if case .on(let p) = e { print("after:", p.count) }
