//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BodyWitnessMemo.swift
//
//  A static witness that a view of the app's own answers with its body's
//  answer, asked once per type and kept, so the question ends even where a
//  body holds its own type.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One static witness's answers, per view type, for the views that answer
/// with their `body`'s: kept for the life of the process, as a declaration
/// never changes.
///
/// A witness whose default is `Body.<the same witness>` cannot be left to the
/// type system when the framework's providers forward it — `Optional`, the
/// conditional view and the stacks answer with their content's. A view whose
/// body holds its own type (`Tree`, whose body is `if depth > 0 { Tree(…) }`)
/// would then ask itself through its `Optional` for ever: a stack overflow,
/// and with an `if`/`else` of itself in both arms, 2ⁿ questions on the way
/// there (memory: static-witness-body-recursion). So the default asks through
/// ``answer(in:for:_:)``, which ends the question where it comes back round
/// and keeps each type's answer, so the walk under a type is made once, not on
/// every `ChildView` built for it.
///
/// The question is an OR over the types a body reaches, so a type met again
/// while its own body is being asked adds nothing: answered `false` there,
/// the answer further out is exact. An answer worked out under such a cut is
/// exact for the type that was cut, and for a type it reached only if that
/// type's answer is `true` (an OR only grows) or it reached no type cut
/// further out than itself; anything else is answered but not kept, and is
/// asked again on its own next time (Tarjan's rule for a strongly connected
/// component, which every type of a cycle belongs to: kept once its root is
/// done).
///
/// A kept answer is read first from a direct-mapped table indexed by the
/// type's metadata address — a shift, a mask and one comparison — and only on
/// a miss from the dictionary behind it. It is read every time a container
/// builds a child of a composite type, on every walk, which a dictionary's
/// hashing would make a per-child cost every app pays, guides or none.
///
/// Held through a pointer kept as a constant, for the reason `PropertyPlans`
/// keeps its tables that way: a static variable is checked for exclusivity on
/// every read and write, where a load through a constant pointer is a plain
/// load. No access to the memo is held across the body's question, which
/// asks this memo again.
@MainActor
package struct BodyWitnessMemo {
    /// One entry of the direct-mapped table: a type and its kept answer.
    private struct FrontEntry {
        var type: ObjectIdentifier?
        var answer = false
    }

    /// How many entries the direct-mapped table has: a power of two.
    private static let frontCount = 512

    /// The direct-mapped table in front of ``answers``.
    private let front: UnsafeMutablePointer<FrontEntry>

    /// The answers kept, by type.
    private var answers: [ObjectIdentifier: Bool] = [:]

    /// The types whose body is being asked now, each with how many were
    /// open further out when it was opened.
    private var open: [ObjectIdentifier: Int] = [:]

    /// The outermost open type met again since the question being asked now
    /// began, as its depth in ``open`` — `Int.max` when none was.
    private var outermostMet = Int.max

    /// How many bodies have been asked, ever: for a test to read that the
    /// walk under a type is made once.
    package private(set) var bodiesAsked = 0

    private init() {
        front = .allocate(capacity: Self.frontCount)
        front.initialize(repeating: FrontEntry(), count: Self.frontCount)
    }

    /// The memo for ``View/_providesAlignmentGuide``.
    package static let alignmentGuide = permanentMemo()

    /// The memo for ``View/_statesSpacingPreference``.
    package static let spacingPreference = permanentMemo()

    /// The memo for whether a view type may state a spacing preference on
    /// its leading and trailing edges (TUIkitFoundation's
    /// `mayStateSpacing(_:along:)`).
    package static let spacingAlongHorizontal = permanentMemo()

    /// The memo for whether a view type may state a spacing preference on
    /// its top and bottom edges.
    package static let spacingAlongVertical = permanentMemo()

    /// The memo for ``View/_handsOverChildren``.
    package static let handsOverChildren = permanentMemo()

    /// The memo for whether a view type is drawn at its own size whatever it
    /// is offered (TUIkitFoundation's `drawsAtItsOwnSize(_:)`).
    package static let ownSize = permanentMemo()

    private static func permanentMemo() -> UnsafeMutablePointer<Self> {
        let pointer = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        pointer.initialize(to: Self())
        return pointer
    }

    /// Where `key` sits in the direct-mapped table: its metadata address,
    /// past the alignment bits, folded once so types allocated a page apart
    /// do not all collide.
    @inline(__always)
    private static func frontIndex(_ key: ObjectIdentifier) -> Int {
        let bits = UInt(bitPattern: key)
        return Int(truncatingIfNeeded: (bits >> 4) ^ (bits >> 13)) & (frontCount - 1)
    }

    /// `V`'s answer, which is `ask()` — its body's, or its content's — kept
    /// once worked out, and `false` where `V` is met again while its own
    /// answer is being asked.
    ///
    /// - Parameters:
    ///   - memo: The witness's memo (``alignmentGuide``).
    ///   - type: The view type asked about.
    ///   - ask: Its answer, asked once: `V.Body.<witness>` for a view of the
    ///     app's own, `false` for one drawn procedurally (``Renderable``),
    ///     whose body is not what is drawn.
    @inline(__always)
    package static func answer<V: View>(
        in memo: UnsafeMutablePointer<Self>, for type: V.Type, _ ask: () -> Bool
    ) -> Bool {
        let key = ObjectIdentifier(type)
        let entry = memo.pointee.front + frontIndex(key)
        if entry.pointee.type == key { return entry.pointee.answer }
        return workedOut(in: memo, for: type, key: key, ask)
    }

    /// ``answer(in:for:_:)`` past a miss in the direct-mapped table.
    @inline(never)
    private static func workedOut<V: View>(
        in memo: UnsafeMutablePointer<Self>, for type: V.Type, key: ObjectIdentifier,
        _ ask: () -> Bool
    ) -> Bool {
        if let known = memo.pointee.answers[key] {
            memo.pointee.keep(known, for: key)
            return known
        }
        if let depth = memo.pointee.open[key] {
            memo.pointee.outermostMet = min(memo.pointee.outermostMet, depth)
            return false
        }
        let depth = memo.pointee.open.count
        memo.pointee.open[key] = depth
        let metFurtherOut = memo.pointee.outermostMet
        memo.pointee.outermostMet = Int.max
        memo.pointee.bodiesAsked += 1

        let answer = ask()

        memo.pointee.open[key] = nil
        let met = memo.pointee.outermostMet
        if answer || met >= depth { memo.pointee.keep(answer, for: key) }
        // What this question met further out than `V` is still open, so the
        // question that opened it must not keep a `false` worked out under it.
        memo.pointee.outermostMet = min(metFurtherOut, met < depth ? met : Int.max)
        return answer
    }

    /// Keeps `answer` as `key`'s, in the dictionary and the direct-mapped
    /// table, where it takes the entry of whichever type held it.
    private mutating func keep(_ answer: Bool, for key: ObjectIdentifier) {
        answers[key] = answer
        front[Self.frontIndex(key)] = FrontEntry(type: key, answer: answer)
    }
}
