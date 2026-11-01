// Cases for the SwiftLint rules key_path_identity, function_address_identity and concurrency_escape
// (.swiftlint.yml): a line ending in `hit: <rule>` must be flagged by that rule, and every other line by none. Tools/DedupCheck/test-lint-rules.sh
// lints a copy under `Sources/TUILintCases/`. Never compiled.
struct Slot: Hashable { let keyPath: AnyKeyPath }
func f(a: AnyKeyPath, b: AnyKeyPath, kp: PartialKeyPath<Int>, c: KeyPathComparator<Int>, d: KeyPathComparator<Int>) {
    _ = a == \Int.bitWidth  // hit: key_path_identity
    _ = \Int.bitWidth == a  // hit: key_path_identity
    _ = c.keyPath == d.keyPath  // hit: key_path_identity
    var seen = Set<AnyKeyPath>()  // hit: key_path_identity
    seen.insert(a)
    var table: [PartialKeyPath<Int>: Int] = [:]  // hit: key_path_identity
    table[kp] = 1
    var hasher = Hasher(); hasher.combine(kp)  // the name says nothing: a gap the check's object scan (K2) covers
    hasher.combine(slot.keyPath)  // hit: key_path_identity
    _ = a.keyPath.hashValue  // hit: key_path_identity
    _ = AnyHashable(keyPath)  // hit: key_path_identity
    let h: @convention(c) (Int32) -> Void = { _ in }
    _ = unsafeBitCast(h, to: Int.self)  // hit: function_address_identity
    _ = unsafeBitCast(h, to: UnsafeRawPointer.self)  // hit: function_address_identity
    let x = 3
    _ = unsafeBitCast(x, to: UInt.self)  // a value, not a function: flagged by design, reviewed at the site. hit: function_address_identity
}
// Typed key paths hash and compare the same way as set elements and dictionary keys.
func g() {
    var writable = Set<WritableKeyPath<Row, String>>()  // hit: key_path_identity
    var shared: Set<ReferenceWritableKeyPath<Box, Int>> = []  // hit: key_path_identity
    var byPath: [KeyPath<Row, String>: Int] = [:]  // hit: key_path_identity
    var nested: [KeyPath<Row, [Int]>: Int] = [:]  // hit: key_path_identity
    var refs: [ReferenceWritableKeyPath<Box, Int>: Int] = [:]  // hit: key_path_identity
    var spelled = Dictionary<WritableKeyPath<Row, String>, Int>()  // hit: key_path_identity
    var any: [AnyKeyPath: Int] = [:]  // hit: key_path_identity
}
final class Unchecked: @unchecked Sendable {}  // hit: concurrency_escape
struct Spaced: @unchecked  Sendable {}  // hit: concurrency_escape
extension Boxed: @unchecked Sendable where Value: Sendable {}  // hit: concurrency_escape
enum Flags {
    nonisolated(unsafe) static var isOn = false  // hit: concurrency_escape
}
