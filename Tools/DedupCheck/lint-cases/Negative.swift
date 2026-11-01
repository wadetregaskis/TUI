// Cases neither key_path_identity nor function_address_identity may flag (.swiftlint.yml;
// Tools/DedupCheck/test-lint-rules.sh). Never compiled.
// a == \Int.bitWidth in a comment is not a match
/// `keyPath == other` in a doc comment is not a match
func g(values: [Int], kp: KeyPath<Int, Int>) {
    let s = "a == \\Int.bitWidth"
    _ = values.map { $0[keyPath: kp] }
    _ = values.sorted(using: KeyPathComparator(\Int.self))
    let x = 3; _ = x == 3
}
func h(anchor: Int?, tap: Int?) -> String {
    "\(anchor == nil ? "following" : "reading") \(tap != nil)"  // an interpolation, not a key path
}
// An optional key path checked against nil compares no address.
func i(sortKeyPath: KeyPath<Row, String>?, keyPath: AnyKeyPath?) -> Bool {
    if sortKeyPath != nil { return true }
    if keyPath == nil { return false }
    return nil != keyPath && nil == sortKeyPath
}
// Arrays of key paths, one of them to a dictionary, are keyed by nothing.
func j() {
    let columns: [KeyPath<Row, String>] = [\Row.name]
    let lookups: [KeyPath<Row, [String: Int]>] = []
    _ = (columns, lookups)
}
// Naming what the concurrency rule looks for, in a comment: @unchecked Sendable, nonisolated(unsafe).
/// And in documentation: `@unchecked Sendable`, `nonisolated(unsafe)`.
let namedInAString = "@unchecked Sendable, nonisolated(unsafe)"
final class Checked: Sendable {}
nonisolated struct Plain {}
