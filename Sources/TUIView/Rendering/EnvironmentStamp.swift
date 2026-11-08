//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentStamp.swift
//
//  What an environment looks like to a render below it, kept so that a later
//  environment can be compared with it key by key (Option C, C2a).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - The stamp

/// An environment, recorded so a later one can be compared with it: whether a
/// render below either would read anything different.
///
/// A memoized row kept below a parent's write is served only if the
/// environment it would be drawn under now equals the one its buffer was
/// drawn under (Option C). Comparing the environments, not a digest of them,
/// is exact — a collision would serve another environment's pixels — and
/// costs less on large values, whose `==` short-circuits on shared storage.
///
/// Each stored key gives a token, by the first of these that applies:
///
/// 1. a key declared ``_RenderNeutralEnvironmentKey``: skipped;
/// 2. an `Optional`: unwrapped, an explicit `nil` kept as such — a key set
///    on one side only is unequal, since the side without it reads the
///    key's default, which need not be `nil`;
/// 3. a value that says what a render depends on
///    (``_EnvironmentRenderComparing``): its projection, or uncomparable;
/// 4. a class: by identity — weakly for a Swift class, so a freed address
///    can never come back for another object and nothing is kept alive;
///    strongly for an Objective-C one, some of which refuse weak references;
/// 5. an `Equatable` value: itself, compared by its own `==`;
/// 6. anything else (a closure, a `Binding`, a style that is not
///    `Equatable`): uncomparable, and so is the whole environment — there is
///    no stamp, and what is drawn under it cannot be re-checked.
///
/// How each key and each value type is classified is worked out once per
/// type (``EnvironmentStamps``). A stamp refers to at most one other, a flat one
/// (`EnvironmentStamp+Derived.swift`), so a table of them can never keep a chain
/// alive.
package final class EnvironmentStamp {
    /// What one key holds, as compared.
    package enum Token {
        /// Set, to `nil`.
        case explicitNil
        /// A value compared by `equal`, the `==` of its type.
        case value(Any, equal: (Any, Any) -> Bool)
        /// A Swift object, by identity, held weakly: equal only while both
        /// are alive and are the same object.
        case object(WeakObject, ObjectIdentifier)
        /// An Objective-C object, by identity, held strongly.
        case retained(AnyObject)
    }

    /// One key and what it holds.
    package struct Entry {
        package let key: ObjectIdentifier
        package let token: Token
    }

    /// The keys, sorted, each with its token. For a stamp on a ``base``, worked
    /// out when first asked: nothing asks when stamps are compared by identity.
    package var entries: [Entry] {
        if let flat { return flat }
        let made = unsafe Self.merged(base.unsafelyUnwrapped, changes)
        flat = made
        return made
    }
    private var flat: [Entry]?

    /// The flat stamp this one is made on, and what differs from it, in key
    /// order: see `EnvironmentStamp+Derived.swift`. `nil` and empty for a flat
    /// stamp.
    let base: EnvironmentStamp?
    let changes: [Change]

    /// A hash of the keys and of each token's cheap part — its kind, an
    /// object's identity, a value's type, a hashable value's hash, a
    /// collection's count — which two equal flat stamps share: where a stamp is
    /// looked for among those already made (``EnvironmentStamps/intern(_:)``).
    /// 0 for a stamp on a ``base``, which is looked for by its changes.
    package let shallowHash: Int

    init(entries: [Entry], shallowHash: Int) {
        flat = entries
        base = nil
        changes = []
        self.shallowHash = shallowHash
    }

    init(base: EnvironmentStamp, changes: [Change]) {
        self.base = base
        self.changes = changes
        shallowHash = 0
    }

    /// Whether a render below `self` and below `other` would read the same
    /// values: the same keys, each with an equal token. One walk of both
    /// sorted lists.
    package func isEquivalent(to other: EnvironmentStamp) -> Bool {
        if self === other { return true }
        // Two on one anchor are the same only if their changes are; the walk below
        // answers that too, a flat stamp's worth of work later.
        if let base, base === other.base { return other.holds(changes, on: base) }
        guard entries.count == other.entries.count,
            base != nil || other.base != nil || shallowHash == other.shallowHash
        else { return false }
        for (mine, theirs) in zip(entries, other.entries) {
            guard mine.key == theirs.key, Self.equal(mine.token, theirs.token) else { return false }
        }
        return true
    }

    /// The first key at which `self` and `other` differ, for a diagnostic:
    /// `nil` when they are equivalent.
    package func firstDifference(from other: EnvironmentStamp) -> ObjectIdentifier? {
        var mine = entries.makeIterator()
        var theirs = other.entries.makeIterator()
        while true {
            switch (mine.next(), theirs.next()) {
            case (nil, nil):
                return nil
            case (let lhs?, nil):
                return lhs.key
            case (nil, let rhs?):
                return rhs.key
            case (let lhs?, let rhs?):
                if lhs.key != rhs.key { return min(lhs.key, rhs.key) }
                if !Self.equal(lhs.token, rhs.token) { return lhs.key }
            }
        }
    }

    static func equal(_ lhs: Token, _ rhs: Token) -> Bool {
        switch (lhs, rhs) {
        case (.explicitNil, .explicitNil):
            return true
        case (.value(let left, let equal), .value(let right, _)):
            return equal(left, right)
        case (.object(let left, let leftID), .object(let right, let rightID)):
            // Both alive: a dead reference is unequal, whatever was there.
            guard leftID == rightID, left.object != nil, right.object != nil else { return false }
            return true
        case (.retained(let left), .retained(let right)):
            return left === right
        default:
            return false
        }
    }
}

/// An object held weakly, for a stamp's token.
package final class WeakObject {
    package weak let object: AnyObject?

    init(_ object: AnyObject) {
        self.object = object
    }
}

// MARK: - Making and interning stamps

/// The stamps a render cache has made: how each key and each value type is
/// classified, the stamps made this pass by environment storage, and every
/// live stamp by its shallow hash, so a stamp equal to one already made is
/// that one (`===`).
///
/// Interning is what makes a stamp last past its pass: the run loop installs
/// a new volatile-read tracker at the root every frame, so every environment
/// storage is new every frame, and a stamp of last frame's environment and
/// one of this frame's would otherwise be different objects for equal
/// environments. The tracker is a neutral key, so the two are equal, and this
/// frame's is last frame's.
///
/// Main-actor only, as the cache's tables are.
package final class EnvironmentStamps {
    /// How many stamps of one shallow hash are kept: past it, a dead one goes
    /// first, then the least recently used, and the overflow is counted.
    package static let bucketCapacity = 32

    /// What has been counted, for the census and the tests.
    package struct Counts: Equatable {
        /// Stamps built from an environment: one per distinct storage per pass.
        package var built = 0
        /// Asks answered from this pass's memo, by storage.
        package var memoHits = 0
        /// Stamps made from what differs from the anchor, rather than built.
        package var derived = 0
        /// Stamps that turned out equal to one already made.
        package var internHits = 0
        /// Comparisons made while interning.
        package var mergeWalks = 0
        /// Stamps pushed out of a full bucket while alive.
        package var overflows = 0
        /// Environments that could not be stamped.
        package var uncomparable = 0
    }

    package internal(set) var counts = Counts()

    /// The keys that made an environment uncomparable, and how often: what a
    /// diagnostic names (``debugName(of:)``).
    package internal(set) var uncomparableKeys: [ObjectIdentifier: Int] = [:]

    /// When on (the census), every key's distinct cheap hashes as stamps are
    /// built: a key with many is one whose value moves from frame to frame,
    /// which keeps every environment holding it from interning, and so every
    /// row drawn under it from being re-checked.
    package var tracksVariety = false
    package private(set) var variety: [ObjectIdentifier: Set<Int>] = [:]

    /// How each key type stored is treated, by the key's identity: skipped,
    /// projected, or its value compared by the value's own rule.
    private var keyRules: [ObjectIdentifier: KeyRule] = [:]

    /// How each value type stored is compared, by the type's identity.
    private var valueRules: [ObjectIdentifier: ValueRule] = [:]

    /// How many of this pass's environments are kept. Each is a dictionary of a
    /// few KB that would otherwise be freed as the walk leaves it, and a page asks
    /// about hundreds: all of them, kept to the pass's end, were 10 MB of
    /// `session/notes`'s footprint, with nothing live to show for it. One let go
    /// costs another walk of its keys if it is asked about again, and a stamp's
    /// interning makes that the same stamp.
    private static let passEnvironmentLimit = 32

    /// This pass's stamps by environment storage, and the environments
    /// themselves, kept so that no storage word in the table is reused by another
    /// environment: one let go leaves the table with it.
    private var passStamps: [UInt: EnvironmentStamp?] = [:]
    private var passEnvironments: [EnvironmentValues] = []
    /// Where the next of ``passEnvironments`` goes, once they have come to the limit.
    private var nextPassEnvironment = 0
    /// The last of ``passStamps`` asked for. Within the pass only, as the
    /// table is: its environment is kept alive by ``passEnvironments``.
    private var lastWord: UInt?
    private var lastStamp: EnvironmentStamp?

    /// Every live stamp by shallow hash, most recently used first.
    private var buckets: [Int: [WeakStamp]] = [:]

    /// This pass's first stamp and what it holds by key, and every stamp made on
    /// an anchor by the hash of its changes: `EnvironmentStamp+Derived.swift`.
    var anchor: EnvironmentStamp?
    var anchorSlots: [ObjectIdentifier: AnchorSlot] = [:]
    var anchorComparedKeys = 0
    var derivedBuckets: [Int: [WeakStamp]] = [:]
    var shortcuts: [ObjectIdentifier: AnchorSlot.Compare] = [:]
    var changeScratch: [EnvironmentStamp.Change] = []
    var tokenWasUncomparable = false

    package init() {}

    /// Forgets this pass's memo, and the stamps that have died since. Called
    /// from the cache's `beginRenderPass()`.
    package func beginPass() {
        endPass()
        for (hash, bucket) in buckets {
            let alive = bucket.filter { $0.stamp != nil }
            if alive.isEmpty {
                buckets[hash] = nil
            } else if alive.count != bucket.count {
                buckets[hash] = alive
            }
        }
        for (hash, bucket) in derivedBuckets where bucket.contains(where: { $0.stamp == nil }) {
            let alive = bucket.filter { $0.stamp != nil }
            derivedBuckets[hash] = alive.isEmpty ? nil : alive
        }
    }

    /// Forgets this pass's memo and lets go of the environments it kept.
    /// Called when the pass ends (the cache's `removeInactive()`) and when the
    /// cache is emptied (`reset()`), not only when the next pass begins: an
    /// environment holds the render cache and the state storage, and the cache
    /// holds this, so the environments kept here were a cycle with the cache
    /// until a next pass came — and a one-off render has none. Every snapshot
    /// stayed alive, whole, for the life of the process.
    package func endPass() {
        passStamps.removeAll(keepingCapacity: true)
        passEnvironments.removeAll(keepingCapacity: true)
        nextPassEnvironment = 0
        lastWord = nil
        lastStamp = nil
        anchor = nil
        anchorSlots.removeAll(keepingCapacity: true)
    }

    /// The stamp of `environment`, or `nil` when something in it cannot be
    /// compared. Once per storage per pass; interned, so equal environments
    /// give the same stamp across passes.
    package func stamp(of environment: EnvironmentValues) -> EnvironmentStamp? {
        let word = environment.storageWord
        // The last asked first: the rows of one list are stored one after
        // another under one environment, and a dictionary lookup per store
        // was most of what stamping cost a store.
        if word == lastWord {
            counts.memoHits += 1
            return lastStamp
        }
        if let known = passStamps[word] {
            lastWord = word
            lastStamp = known
            counts.memoHits += 1
            return known
        }
        let made: EnvironmentStamp?
        switch derive(environment) {
        case .stamp(let derived):
            made = derived
        case .uncomparable:
            counts.uncomparable += 1
            made = nil
        case .flat:
            made = build(environment).map(intern)
            if let made, anchor == nil { setAnchor(environment, made) }
        }
        keepForThePass(environment, word: word, stamp: made)
        lastWord = word
        lastStamp = made
        return made
    }

    private func keepForThePass(_ environment: EnvironmentValues, word: UInt, stamp: EnvironmentStamp?) {
        if passEnvironments.count < Self.passEnvironmentLimit {
            passEnvironments.append(environment)
        } else {
            passStamps.removeValue(forKey: passEnvironments[nextPassEnvironment].storageWord)
            passEnvironments[nextPassEnvironment] = environment
            nextPassEnvironment = (nextPassEnvironment + 1) % Self.passEnvironmentLimit
        }
        passStamps[word] = stamp
    }

    /// The stamp made from `environment`, not interned.
    package func build(_ environment: EnvironmentValues) -> EnvironmentStamp? {
        counts.built += 1
        let stored = environment.storedValues
        var hashed: [(entry: EnvironmentStamp.Entry, hash: Int)] = []
        hashed.reserveCapacity(stored.count)
        var comparable = true
        for (key, raw) in stored {
            let value: Any
            switch keyRule(key) {
            case .neutral:
                continue
            case .projecting(let project):
                guard let projection = project(raw) else {
                    comparable = false
                    uncomparableKeys[key, default: 0] += 1
                    continue
                }
                value = projection
            case .plain:
                value = raw
            }
            // Each token's cheap part is hashed on its own and folded in after
            // the sort: a dictionary's iteration order is its own, and two
            // equal environments need not share it.
            var hasher = Hasher()
            hasher.combine(key)
            guard let token = token(for: value, hasher: &hasher) else {
                // Every such key is counted, not only the first: the census
                // that reads these is a list of what to make comparable.
                comparable = false
                uncomparableKeys[key, default: 0] += 1
                continue
            }
            let entryHash = hasher.finalize()
            if tracksVariety { variety[key, default: []].insert(entryHash) }
            if comparable { hashed.append((EnvironmentStamp.Entry(key: key, token: token), entryHash)) }
        }
        guard comparable else {
            counts.uncomparable += 1
            return nil
        }
        hashed.sort { $0.entry.key < $1.entry.key }
        var hasher = Hasher()
        for item in hashed { hasher.combine(item.hash) }
        return EnvironmentStamp(entries: hashed.map(\.entry), shallowHash: hasher.finalize())
    }

    /// `stamp`, or the live stamp equal to it already made.
    package func intern(_ stamp: EnvironmentStamp) -> EnvironmentStamp {
        var bucket = buckets[stamp.shallowHash] ?? []
        // A stamp on an anchor has none to be looked for by, and is one already.
        guard stamp.base == nil else { return stamp }
        for (index, candidate) in bucket.enumerated() {
            guard let existing = candidate.stamp else { continue }
            counts.mergeWalks += 1
            if existing.isEquivalent(to: stamp) {
                counts.internHits += 1
                if index != 0 {
                    bucket.remove(at: index)
                    bucket.insert(candidate, at: 0)
                    buckets[stamp.shallowHash] = bucket
                }
                return existing
            }
        }
        bucket.insert(WeakStamp(stamp), at: 0)
        if bucket.count > Self.bucketCapacity {
            if let dead = bucket.lastIndex(where: { $0.stamp == nil }) {
                bucket.remove(at: dead)
            } else {
                bucket.removeLast()
                counts.overflows += 1
            }
        }
        buckets[stamp.shallowHash] = bucket
        return stamp
    }

    /// How many stamps are live in the intern table.
    package var liveStampCount: Int {
        buckets.values.reduce(0) { total, bucket in total + bucket.count(where: { $0.stamp != nil }) }
    }

    /// A stored key's name, for a diagnostic: the key's type, recovered from
    /// its identity — an `ObjectIdentifier` of a type is that type's metadata
    /// pointer, which is what a metatype is. Done at report time only; nothing
    /// is recorded on the write path.
    package static func debugName(of key: ObjectIdentifier) -> String {
        unsafe String(reflecting: unsafeBitCast(key, to: Any.Type.self))
    }

    // MARK: Classification

    func keyRule(_ key: ObjectIdentifier) -> KeyRule {
        if let known = keyRules[key] { return known }
        let type = unsafe unsafeBitCast(key, to: Any.Type.self)
        let rule: KeyRule
        if type is _RenderNeutralEnvironmentKey.Type {
            rule = .neutral
        } else if let projecting = type as? _RenderProjectingEnvironmentKey.Type {
            rule = .projecting(projecting.renderProjection(of:))
        } else {
            rule = .plain
        }
        keyRules[key] = rule
        return rule
    }

    /// The token for `value`, folding its cheap part into `hasher`, or `nil`
    /// when it cannot be compared.
    func token(for value: Any, hasher: inout Hasher) -> EnvironmentStamp.Token? {
        let rule = rule(for: value)
        hasher.combine(rule.kind)
        switch rule {
        case .optional:
            guard let wrapped = (value as? any _OptionalForStamp)?.wrappedForStamp else {
                return .explicitNil
            }
            return token(for: wrapped, hasher: &hasher)
        case .projection:
            guard let projection = (value as? any _EnvironmentRenderComparing)?.renderProjection else { return nil }
            return token(for: projection, hasher: &hasher)
        case .object:
            let object = value as AnyObject
            let id = ObjectIdentifier(object)
            hasher.combine(id)
            return .object(WeakObject(object), id)
        case .retained:
            let object = value as AnyObject
            hasher.combine(ObjectIdentifier(object))
            return .retained(object)
        case .value(let equal, let cheapHash):
            hasher.combine(ObjectIdentifier(type(of: value)))
            cheapHash?(value, &hasher)
            return .value(value, equal: equal)
        case .uncomparable:
            return nil
        }
    }

    private func rule(for value: Any) -> ValueRule {
        let type = ObjectIdentifier(Swift.type(of: value))
        if let known = valueRules[type] { return known }
        let made = ValueRule.classify(value)
        valueRules[type] = made
        return made
    }
}

/// How a stored key is treated: decided once per key type.
enum KeyRule {
    /// Declared ``_RenderNeutralEnvironmentKey``: skipped.
    case neutral
    /// Declared ``_RenderProjectingEnvironmentKey``: its value compared by
    /// its projection.
    case projecting((Any) -> (any Equatable)?)
    /// Its value compared by the value's own rule.
    case plain
}

/// A stamp held weakly by the intern table.
struct WeakStamp {
    weak var stamp: EnvironmentStamp?

    init(_ stamp: EnvironmentStamp) {
        self.stamp = stamp
    }
}

// MARK: - Value rules

/// How values of one type are compared: worked out once per type.
private enum ValueRule {
    case optional
    case projection
    case object
    case retained
    /// `equal` is the type's `==`; `cheapHash` hashes what two equal values
    /// share cheaply — the value itself when it is `Hashable`, a count when it
    /// is a `Collection` — or nothing.
    case value(equal: (Any, Any) -> Bool, cheapHash: ((Any, inout Hasher) -> Void)?)
    case uncomparable

    /// The rule's kind, hashed into a stamp's shallow hash.
    var kind: UInt8 {
        switch self {
        case .optional: 0
        case .projection: 1
        case .object: 2
        case .retained: 3
        case .value: 4
        case .uncomparable: 5
        }
    }

    static func classify(_ value: Any) -> Self {
        if value is any _OptionalForStamp { return .optional }
        if value is any _EnvironmentRenderComparing { return .projection }
        // `type(of:) is AnyClass`, never `as? AnyObject`: on Darwin every
        // value casts to `AnyObject` (it is boxed), so the cast says nothing.
        if type(of: value) is AnyClass {
            #if canImport(ObjectiveC)
                if value is NSObject { return .retained }
            #endif
            return .object
        }
        if let equatable = value as? any Equatable {
            return .value(equal: equality(of: equatable), cheapHash: cheapHash(of: value))
        }
        return .uncomparable
    }

    private static func equality(of value: any Equatable) -> (Any, Any) -> Bool {
        func make<E: Equatable>(_: E) -> (Any, Any) -> Bool {
            { lhs, rhs in
                guard let left = lhs as? E, let right = rhs as? E else { return false }
                return left == right
            }
        }
        return make(value)
    }

    private static func cheapHash(of value: Any) -> ((Any, inout Hasher) -> Void)? {
        if let hashable = value as? any Hashable {
            func make<H: Hashable>(_: H) -> (Any, inout Hasher) -> Void {
                { value, hasher in (value as? H).map { hasher.combine($0) } }
            }
            return make(hashable)
        }
        if let collection = value as? any Collection {
            func make<C: Collection>(_: C) -> (Any, inout Hasher) -> Void {
                { value, hasher in (value as? C).map { hasher.combine($0.count) } }
            }
            return make(collection)
        }
        return nil
    }
}

// MARK: - Optional

/// An `Optional`, unwrapped without knowing its type statically.
private protocol _OptionalForStamp {
    var wrappedForStamp: Any? { get }
}

extension Optional: _OptionalForStamp {
    fileprivate var wrappedForStamp: Any? {
        switch self {
        case .some(let wrapped): wrapped
        case .none: nil
        }
    }
}
