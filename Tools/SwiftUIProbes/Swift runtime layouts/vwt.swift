// DYNVFIX probe: can an arm64 macOS process call an enum's value witnesses (getEnumTag,
// destructiveProjectEnumData, destructiveInjectEnumTag) read from its metadata, for a user enum,
// a generic user enum instantiated at run time, and the stdlib's Optional? And a typed weak load.
// Also: swift_reflectionMirror_subscript on an enum with a custom mirror (does it bypass customMirror?).
import Foundation

typealias GetEnumTag = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UInt32
typealias ProjectEnumData = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Void
typealias InjectEnumTag = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void

struct EnumWitnesses {
    let metadata: UnsafeRawPointer
    let getTag: GetEnumTag
    let project: ProjectEnumData
    let inject: InjectEnumTag
    init(_ type: Any.Type) {
        metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        let vwt = metadata.load(fromByteOffset: -MemoryLayout<Int>.size, as: UnsafeRawPointer.self)
        // 8 function pointers, size, stride, flags(4) + extraInhabitantCount(4) = 11 words, then the enum witnesses.
        let w = MemoryLayout<Int>.size
        getTag = unsafeBitCast(vwt.load(fromByteOffset: 11 * w, as: UnsafeRawPointer.self), to: GetEnumTag.self)
        project = unsafeBitCast(vwt.load(fromByteOffset: 12 * w, as: UnsafeRawPointer.self), to: ProjectEnumData.self)
        inject = unsafeBitCast(vwt.load(fromByteOffset: 13 * w, as: UnsafeRawPointer.self), to: InjectEnumTag.self)
    }
}

final class Box { var n: Int; init(_ n: Int) { self.n = n } }
enum Multi { case a(Box), b(Box), c }            // tag in the pointer's spare bits
enum Single { case some(Box), none1, none2 }      // single payload
enum Gen<T> { case x(T, Box), y(T) }              // generic, runtime-instantiated
struct Payload { var count = 0; var box = Box(0) }
enum WithStruct { case on(Payload), off }
indirect enum Ind { case on(Payload), off }

func run<E>(_ name: String, _ value: E, payloadOffsetBoxField: Int, newBox: Box) {
    var v = value
    let w = EnumWitnesses(E.self)
    withUnsafeMutablePointer(to: &v) { p in
        let raw = UnsafeMutableRawPointer(p)
        let tag = w.getTag(raw, w.metadata)
        w.project(raw, w.metadata)
        // overwrite the payload's Box field (a +1 retained store, releasing the old)
        let slot = (raw + payloadOffsetBoxField).assumingMemoryBound(to: Box.self)
        slot.pointee = newBox
        w.inject(raw, tag, w.metadata)
        let after = w.getTag(raw, w.metadata)
        print(name, "tag", tag, "after", after)
    }
    print(name, "value after:", v)
}

let which = CommandLine.arguments.dropFirst().first ?? "all"
if which == "all" || which == "multi" {
    run("multi.b", Multi.b(Box(1)), payloadOffsetBoxField: 0, newBox: Box(42))
    if case .b(let b) = Multi.b(Box(1)) { _ = b }
    var m = Multi.b(Box(1)); run("multi.b2", m, payloadOffsetBoxField: 0, newBox: Box(7)); m = .c; _ = m
}
if which == "all" || which == "single" {
    run("single", Single.some(Box(1)), payloadOffsetBoxField: 0, newBox: Box(9))
}
if which == "all" || which == "gen" {
    // Gen<Int>.x(Int, Box): payload tuple (Int, Box): Box at offset 8
    run("gen", Gen<Int>.x(3, Box(1)), payloadOffsetBoxField: 8, newBox: Box(11))
}
if which == "all" || which == "struct" {
    run("struct", WithStruct.on(Payload(count: 1, box: Box(1))), payloadOffsetBoxField: 8, newBox: Box(5))
}
if which == "all" || which == "optional" {
    let o: Optional<Payload> = Payload(count: 2, box: Box(2))
    run("optional", o, payloadOffsetBoxField: 8, newBox: Box(6))
}
if which == "all" || which == "tagonly" {
    for e in [Multi.a(Box(1)), .b(Box(2)), .c] { print("tag", EnumWitnesses(Multi.self).getTag(withUnsafePointer(to: e) { UnsafeRawPointer($0) }, EnumWitnesses(Multi.self).metadata)) }
    let inds: [Ind] = [.on(Payload()), .off]
    for e in inds { var e = e; print("ind tag", withUnsafeMutablePointer(to: &e) { EnumWitnesses(Ind.self).getTag(UnsafeRawPointer($0), EnumWitnesses(Ind.self).metadata) }) }
}

// typed weak load
struct WBox<T: AnyObject> { weak var v: T? }
struct HasWeak { var a = 1; weak var w: Box?; var b = 2 }
if which == "all" || which == "weak" {
    let live = Box(77)
    var h = HasWeak(); h.w = live
    let off = MemoryLayout<HasWeak>.offset(of: \HasWeak.w)
    print("weak offset", off as Any)
    let got = withUnsafeBytes(of: &h) { $0.baseAddress!.advanced(by: 8).load(as: WBox<Box>.self).v }
    print("weak live:", got?.n as Any)
    var h2 = HasWeak(); do { let tmp = Box(1); h2.w = tmp }
    let got2 = withUnsafeBytes(of: &h2) { $0.baseAddress!.advanced(by: 8).load(as: WBox<Box>.self).v }
    print("weak dead:", got2 as Any)
    withExtendedLifetime(live) {}
}

// The runtime's own mirror entry points, which do not consult customMirror.
@_silgen_name("swift_reflectionMirror_count")
func _rtChildCount<T>(_: T, type: Any.Type) -> Int
typealias NameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void
@_silgen_name("swift_reflectionMirror_subscript")
func _rtChild<T>(of: T, type: Any.Type, index: Int, outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
                 outFreeFunc: UnsafeMutablePointer<NameFreeFunc?>) -> Any
@_silgen_name("swift_EnumCaseName")
func _rtEnumCaseName<T>(_ value: T) -> UnsafePointer<CChar>?

enum Hidden: CustomReflectable { case on(Payload), off
    var customMirror: Mirror { Mirror(self, children: [:]) } }
protocol P {}
extension Payload: P {}
enum Exi { case on(any P), off }
if which == "all" || which == "mirror" {
    let h = Hidden.on(Payload(count: 4, box: Box(4)))
    print("Mirror children:", Mirror(reflecting: h).children.count)
    print("runtime count:", _rtChildCount(h, type: Hidden.self))
    var name: UnsafePointer<CChar>? = nil; var free: NameFreeFunc? = nil
    let child = _rtChild(of: h, type: Hidden.self, index: 0, outName: &name, outFreeFunc: &free)
    print("runtime child:", child, "name:", name.map { String(cString: $0) } as Any, "type:", type(of: child))
    free?(name)
    print("case name off:", String(cString: _rtEnumCaseName(Hidden.off)!))
    let e = Exi.on(Payload(count: 9, box: Box(9)))
    var n2: UnsafePointer<CChar>? = nil; var f2: NameFreeFunc? = nil
    let c2 = _rtChild(of: e, type: Exi.self, index: 0, outName: &n2, outFreeFunc: &f2)
    print("existential payload type(of:):", type(of: c2), "is Payload:", c2 is Payload)
    let ind = Ind.on(Payload(count: 3, box: Box(3)))
    let c3 = _rtChild(of: ind, type: Ind.self, index: 0, outName: &n2, outFreeFunc: &f2)
    print("indirect payload:", c3, type(of: c3))
}
