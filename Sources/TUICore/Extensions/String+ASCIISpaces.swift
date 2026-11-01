//  🖥️ TUI — A Terminal UI framework for Swift
//  String+ASCIISpaces.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Shared ASCII Spaces

/// A pre-built run of ASCII spaces that the per-line padding hot paths slice
/// instead of allocating a fresh `String(repeating: " ", count:)` every call.
///
/// Buffer assembly pads almost every line, every frame, with a throwaway spaces
/// string — `String(repeating:count:)` was ~5.6% inclusive in the `fanout`
/// Time-Profiler trace, with the `_StringGuts` growth helpers it feeds another
/// ~11% combined. The padding count is always a small terminal column count, so
/// one fixed run covers it: ``asciiSpaces(_:)`` returns a borrowed `Substring`
/// prefix of this run with **zero** per-call allocation. The run is an immutable
/// `Sendable` `String` initialized once, so a plain `static let` is already
/// data-race-free (every access is a pure read of immutable storage).
private enum ASCIISpaces {
    /// The cached length. Generous relative to real terminal widths (a 1024-cell
    /// row is already far past any terminal); a pad wider than this falls back to
    /// `String(repeating:)`, which is then rare enough not to matter.
    static let count = 1024

    /// `count` ASCII spaces. Immutable after initialization.
    static let run = String.spaces(count)

    /// `run`'s index at every offset, `0...count`, computed once.
    ///
    /// `run.prefix(n)` looks free and is not: `Collection.prefix` advances an
    /// index n places, and `String`'s index advancement is a GRAPHEME walk —
    /// one break query per space, per call. Padding a line is the most common
    /// operation in the framework, so that walk showed up as
    /// `String.index(_:offsetBy:limitedBy:)` under `Collection.prefix` at
    /// 2.9% of a `deep` frame, entirely to re-derive an offset into a run of
    /// spaces that never changes. The table makes the slice O(1).
    static let indices: [String.Index] = {
        var result: [String.Index] = []
        result.reserveCapacity(count + 1)
        var index = run.startIndex
        for _ in 0..<count {
            result.append(index)
            index = run.index(after: index)
        }
        result.append(index)  // == run.endIndex
        return result
    }()
}

/// Returns `count` ASCII spaces (`U+0020`) as a borrowed `Substring`, allocating
/// nothing for the common case.
///
/// This is the in-place-friendly replacement for `String(repeating: " ", count:)`
/// on the render path: append the result onto a result string that has already
/// reserved its capacity, rather than building a temporary spaces `String` and
/// concatenating it. For `count` within the shared run's length the result is a
/// slice of a single process-wide buffer (no allocation); only an unusually wide
/// `count` (beyond a full 1024-cell row) allocates, via the `String(repeating:)`
/// fallback. A non-positive `count` yields an empty `Substring`.
///
/// - Parameter count: The number of spaces required.
/// - Returns: Exactly `max(0, count)` space characters.
package func asciiSpaces(_ count: Int) -> Substring {
    guard count > 0 else { return "" }
    if count <= ASCIISpaces.count {
        return ASCIISpaces.run[..<ASCIISpaces.indices[count]]
    }
    // Wider than a full terminal row — vanishingly rare. Build it once here; the
    // caller still appends a Substring, keeping the call site uniform.
    return Substring(String.spaces(count))
}

extension String {
    /// `count` ASCII spaces as a `String` of their own — the form a line of
    /// padding is stored or concatenated in, where ``asciiSpaces(_:)`` is for
    /// appending onto a string being built.
    ///
    /// Not `String(repeating: " ", count:)`, which appends its argument once
    /// per repetition: at a terminal row's width that is about 1.2 µs a line
    /// against 60 ns for filling the bytes, and building blank rows that way
    /// was 3.6% of a `churn` frame (`FrameBuffer(emptyWithWidth:height:)`).
    /// A single space is the literal, which is cheaper still. A non-positive
    /// `count` is the empty string.
    ///
    /// A static function, NOT an `init(spaces:)`: an unapplied `String.init`
    /// ignores argument labels, so `numbers.map(String.init)` would choose
    /// a non-generic `(Int) -> String` initialiser over the generic integer
    /// one and turn every 5 into five spaces — which it did, in three tests,
    /// when this was one.
    @usableFromInline
    package static func spaces(_ count: Int) -> String {
        switch count {
        case ...0: ""
        case 1: " "
        default:
            String(unsafeUninitializedCapacity: count) { bytes in
                bytes.initialize(repeating: UInt8(ascii: " "))
                return count
            }
        }
    }
}
