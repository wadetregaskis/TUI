//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueHashPlans.swift
//
//  The value-hash plans a render cache has built, found by type on every
//  measured view, and what runs them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Every ``ValueHashPlan`` a table has built, keyed by type.
///
/// Looked up once per measured view, so it is shaped for that: open addressing
/// on the metadata address, linear probing, a power-of-two table kept at most a
/// quarter full, and inserts only. A slot holds its plan's ``Entry`` — its
/// shape, its size, and where its runs and steps lie in two lists every plan
/// shares — so a lookup is one load of the slot, and the entry it returns is a
/// value: it stays good while the table grows under a build, and so do the
/// places it names, which only ever have more appended after them. Built on
/// first sight of a type and kept for the life of the table: a plan is a fact
/// about the type, the same in every pass, for every value and under every
/// cache.
///
/// So a table is handed to a ``RenderCache`` by whoever makes the cache, and
/// kept by them — `TUIContext` one per context, `Stress` one for every cache a
/// `--cold` run makes — rather than one per process: nothing here is shared
/// state. First sight of a type builds its plan, a few microseconds.
///
/// Arrays, not memory of its own: nothing here is unsafe to hold, and the
/// class needs no `@safe` (strict memory safety). The lists are stored
/// variables marked `@exclusivity(unchecked)`, because Swift otherwise checks
/// each access to a class's stored variable for exclusivity at run time, and
/// the hash reads them several times per value. Every access is a single read
/// or write that calls nothing while it lasts — a step reads its list again
/// for each step, after the last one may have planned a new type and grown
/// it — so no two can overlap. What the hash costs for the bounds checks the
/// arrays bring is in `Documentation/Historical/Swift language and
/// platforms/Strict memory safety.md`.
///
/// Nothing here is isolated to the main actor, though every caller is on it:
/// the plans are only ever run from inside a measure, synchronously. That is
/// not a nicety. A `@MainActor` function's closures are isolated too, and
/// Swift 6 checks the executor on entry to one handed to the standard
/// library's `withUnsafeBytes` or `_openExistential` (SE-0423) — and a hash
/// that runs steps passes several: measured with the plans wired in, the
/// check's leaves were more than half of `viewValueHash`'s inclusive time on
/// `fanout`. The one thing that needs the main actor, the stack guard's
/// floor, is read at the entry (``armStackCheck()``).
package final class ValueHashPlans {
    /// A plan as the hash runs it: what ``Slot`` keeps, and a lookup returns.
    struct Entry {
        /// Where the plan's runs lie in ``runs``.
        var runs: Range<Int32>
        /// Where the plan's steps lie in ``steps``.
        var steps: Range<Int32>
        /// `MemoryLayout.size` of the type: a type that does not fit in 31
        /// bits bypasses.
        var size: Int32
        var shape: ValueHashPlan.Shape
    }

    private struct Slot {
        /// The metadata address of the planned type; 0 for an empty slot.
        var key: UInt
        var entry: Entry
    }

    private struct Table {
        var slots: ContiguousArray<Slot>
        /// Capacity − 1.
        var mask: Int
        /// 64 − log2(capacity): what a Fibonacci hash is shifted right by.
        var shift: UInt64
        var count: Int
    }

    /// What running a plan keeps between one entry and the steps below it.
    private struct Running {
        /// The stack address below which a step gives up rather than open
        /// another existential: ``StackGuard``'s floor for the thread the
        /// last entry ran on, set by ``armStackCheck()``. 0 until then —
        /// no check — which only a test calling the steps directly sees.
        var stackFloor: UInt = 0
        /// Whether a step gave up at ``stackFloor`` since this was last taken
        /// (``takeStackRanShort()``).
        var stackRanShort = false
    }

    /// `@exclusivity(unchecked)`, as are the lists: see the type.
    @exclusivity(unchecked) private var table: Table
    /// Every plan's runs, each plan's together, in offset order. Appended to
    /// only, so a place an ``Entry`` names never moves.
    @exclusivity(unchecked) private var runs: ContiguousArray<ValueHashPlan.Run> = []
    /// Every plan's steps, as ``runs`` is.
    @exclusivity(unchecked) private var steps: ContiguousArray<ValueHashPlan.Step> = []
    @exclusivity(unchecked) private var running = Running()
    /// Why each type that bypasses does, by type: read by a test and the
    /// census only.
    private var bypassReasons: [ObjectIdentifier: String] = [:]

    private let listFields: ValueHashPlanBuilder.FieldLister
    private let openers: [any ValueHashOpener.Type]

    /// Every ``ValueComparison`` made, by type: `nil` for a type that has none.
    /// A fact about the type, as a plan is.
    private var comparisons: [ObjectIdentifier: ValueComparison?] = [:]

    #if TUI_VALUE_HASH_CENSUS
    /// What the hash did with these plans — see ``ValueHashCensus``.
    package var census = ValueHashCensus()
    #endif

    /// A table to start with: enough for the few hundred types a large app's
    /// frames measure before it first grows.
    private static let initialCapacity = 256

    /// An empty table, which opens an existential of a static type it has an
    /// `opener` for directly — see ``ValueHashOpener``.
    package convenience init(openers: [any ValueHashOpener.Type] = []) {
        self.init(listFields: { RuntimeFields.fields(of: $0) }, openers: openers)
    }

    /// An empty table that lists a type's fields with `listFields`: a test's,
    /// to see a type whose metadata was stripped bypass.
    init(listFields: @escaping ValueHashPlanBuilder.FieldLister, openers: [any ValueHashOpener.Type] = []) {
        self.listFields = listFields
        self.openers = openers
        unsafe table = Self.emptyTable(capacity: Self.initialCapacity)
    }

    /// How many types have a plan — what a test counts.
    package var count: Int { unsafe table.count }

    /// `type`'s plan, as a test or the census reads it; built the first time
    /// any lookup asks for it.
    package func plan(for type: Any.Type) -> ValueHashPlan {
        let entry = entry(for: type)
        let runs = unsafe Array(runs[Int(entry.runs.lowerBound)..<Int(entry.runs.upperBound)])
        let steps = unsafe Array(steps[Int(entry.steps.lowerBound)..<Int(entry.steps.upperBound)])
        return ValueHashPlan(
            shape: entry.shape, size: Int(entry.size), runs: runs, steps: steps,
            bypassReason: bypassReasons[ObjectIdentifier(type)])
    }

    /// `type`'s plan as the hash runs it, built the first time it is asked for.
    @inline(__always)
    func entry(for type: Any.Type) -> Entry {
        let key = UInt(bitPattern: ObjectIdentifier(type))
        var index = unsafe Int(truncatingIfNeeded: (UInt64(key) &* 0x9E37_79B9_7F4A_7C15) &>> table.shift)
        while true {
            let slot = unsafe table.slots[index]
            if slot.key == key { return slot.entry }
            if slot.key == 0 { return insertPlan(for: type, key: key) }
            index = unsafe (index &+ 1) & table.mask
        }
    }

    /// Builds `type`'s plan and files it. Out of line: once per type per table.
    @inline(never)
    private func insertPlan(for type: Any.Type, key: UInt) -> Entry {
        if unsafe (table.count + 1) * 4 > table.mask + 1 { grow() }
        let builder = unsafe ValueHashPlanBuilder(listFields: listFields, openers: openers)
        let entry = unsafe file(type, builder.items(for: type))
        var index = unsafe Int(truncatingIfNeeded: (UInt64(key) &* 0x9E37_79B9_7F4A_7C15) &>> table.shift)
        while unsafe table.slots[index].key != 0 { index = unsafe (index &+ 1) & table.mask }
        unsafe table.slots[index] = Slot(key: key, entry: entry)
        unsafe table.count += 1
        return entry
    }

    /// Doubles the table and refiles every plan in it.
    private func grow() {
        let old = unsafe table
        var grown = Self.emptyTable(capacity: (old.mask + 1) * 2)
        for slot in old.slots where slot.key != 0 {
            var target = Int(truncatingIfNeeded: (UInt64(slot.key) &* 0x9E37_79B9_7F4A_7C15) &>> grown.shift)
            while grown.slots[target].key != 0 { target = (target &+ 1) & grown.mask }
            grown.slots[target] = slot
        }
        grown.count = old.count
        unsafe table = grown
    }

    private static func emptyTable(capacity: Int) -> Table {
        let empty = Slot(key: 0, entry: Entry(runs: 0..<0, steps: 0..<0, size: 0, shape: .bypass))
        return Table(
            slots: ContiguousArray(repeating: empty, count: capacity), mask: capacity - 1,
            shift: UInt64(64 - capacity.trailingZeroBitCount), count: 0)
    }

    /// Files `type`'s plan from the builder's parts — adjacent runs merged,
    /// the shape decided, both lists appended to the table's — and returns
    /// its entry.
    private func file(
        _ type: Any.Type, _ built: Result<[ValueHashPlanBuilder.Item], ValueHashPlanBuilder.Bypass>
    ) -> Entry {
        let size = unsafe ValueHashPlanBuilder.layout(of: type).size
        var planRuns: [ValueHashPlan.Run] = []
        var planSteps: [ValueHashPlan.Step] = []
        var shape = ValueHashPlan.Shape.bypass
        switch unsafe built {
        case .failure(let bypass):
            bypassReasons[ObjectIdentifier(type)] = bypass.reason
        case .success(let items):
            for unsafe item in unsafe items {
                switch unsafe item {
                case .bytes(let offset, let count, _) where count > 0:
                    if let last = planRuns.last, last.offset + last.count == offset {
                        planRuns[planRuns.count - 1] = .init(offset: last.offset, count: last.count + count)
                    } else {
                        planRuns.append(.init(offset: offset, count: count))
                    }
                case .bytes:
                    break
                case .step(let step):
                    planSteps.append(step)
                case .compared:
                    // Only a comparison's walk makes these (`comparing`).
                    break
                }
            }
            if !planSteps.isEmpty {
                shape = .steps
            } else if size == 0 || planRuns == [.init(offset: 0, count: size)] {
                shape = .dense
            } else {
                shape = .runs
            }
        }
        // A list past 31 bits of places, or a type past 31 bits of size,
        // cannot be named by an entry: the type bypasses rather than trap.
        let limit = Int(Int32.max)
        guard size <= limit, unsafe runs.count + planRuns.count <= limit, unsafe steps.count + planSteps.count <= limit
        else {
            bypassReasons[ObjectIdentifier(type)] = "\(type): too large for a plan table to file"
            return Entry(runs: 0..<0, steps: 0..<0, size: 0, shape: .bypass)
        }
        let firstRun = unsafe Int32(runs.count)
        let firstStep = unsafe Int32(steps.count)
        unsafe runs.append(contentsOf: planRuns)
        unsafe steps.append(contentsOf: planSteps)
        return Entry(
            runs: firstRun..<(firstRun + Int32(planRuns.count)), steps: firstStep..<(firstStep + Int32(planSteps.count)),
            size: Int32(size), shape: shape)
    }
}

// MARK: - Comparisons

extension ValueHashPlans {
    /// How two values of `type` compare, made the first time it is asked for by
    /// the walk that makes `type`'s plan; `nil` when they cannot be.
    package func comparison(for type: Any.Type) -> ValueComparison? {
        let id = ObjectIdentifier(type)
        if let known = comparisons[id] { return known }
        let walk = unsafe ValueHashPlanBuilder(listFields: listFields, comparing: true)
        let made: ValueComparison? =
            switch unsafe walk.items(for: type) {
            case .success(let items): unsafe ValueComparison(items)
            case .failure: nil
            }
        comparisons[id] = .some(made)
        return made
    }
}

// MARK: - Running a plan

extension ValueHashPlans {
    /// The value hash of the value of type `V` at `value`, by its plan, or
    /// `nil` when its type bypasses.
    ///
    /// On the main actor for the stack guard alone, and with no closure of
    /// its own, so nothing here checks the executor (see the type).
    @MainActor
    package func valueHash<V>(at value: UnsafePointer<V>) -> Int? {
        let entry = entry(for: V.self)
        if entry.shape == .dense {
            return unsafe hashOfRawBytes(UnsafeRawBufferPointer(start: value, count: MemoryLayout<V>.size))
        }
        armStackCheck()
        return unsafe hashByPlan(UnsafeRawPointer(value), entry)
    }

    /// Readies the check ``mixOpened(_:into:plans:)`` makes before it opens
    /// an existential, for the thread this runs on: every entry that runs a
    /// plan with steps calls this first, on the main actor, where the stack
    /// guard's state lives.
    ///
    /// The steps below compare the stack pointer with the floor read here,
    /// off the main actor — sound because an entry and every step under it
    /// run synchronously, on one thread, the one this found the floor of.
    /// `UInt.max` when there is no headroom even here, so every opening
    /// gives up; 0 when the guard is off, so none does — its answers exactly.
    @MainActor @inline(__always)
    func armStackCheck() {
        unsafe running.stackFloor = StackGuard.uncountedFloor()
    }

    /// Whether a step may open another existential: the stack pointer is
    /// above the floor the entry armed. See ``armStackCheck()``.
    @inline(__always)
    var hasStackHeadroom: Bool {
        unsafe StackGuard.currentStackPointer() > running.stackFloor
    }

    /// Notes that a step gave up, the stack having run short. Off the path of
    /// every step that does not.
    func noteStackRanShort() {
        unsafe running.stackRanShort = true
    }

    /// Whether a step has given up since this was last asked: whether a `nil`
    /// from a hash cost a whole stack of steps, rather than none, as it does for
    /// a value whose type cannot be hashed.
    @MainActor
    func takeStackRanShort() -> Bool {
        defer { unsafe running.stackRanShort = false }
        return unsafe running.stackRanShort
    }

    /// The hash of a value whose plan is not dense: its runs, then its steps,
    /// seeded and finalised as the dense hash is. Out of line, off the dense
    /// path. The caller has armed the stack check.
    @inline(never)
    func hashByPlan(_ base: UnsafeRawPointer, _ entry: Entry) -> Int? {
        var hash = hashFoldSeed
        guard unsafe mix(at: base, entry: entry, into: &hash) else { return nil }
        return finalizeHashWord(hash)
    }

    /// Mixes the value of `type` at `base` into `hash`, by `type`'s plan;
    /// `false` when it bypasses.
    func mix(at base: UnsafeRawPointer, type: Any.Type, into hash: inout UInt64) -> Bool {
        unsafe mix(at: base, entry: entry(for: type), into: &hash)
    }

    /// For an enum's ``_ValueHashing`` conformance: mixes the case it
    /// switched to, then that case's payload by the payload's plan.
    ///
    /// `caseIndex` is the case's own number, distinct for every case of the
    /// type, so two cases never mix the same words whatever their payloads;
    /// pass `()` for a case without one.
    package func mixCase<Payload>(_ caseIndex: Int, _ payload: Payload, into hash: inout UInt64) -> Bool {
        hash = mixHashWord(hash, UInt64(bitPattern: Int64(caseIndex)))
        return mixValue(payload, into: &hash)
    }

    /// Mixes `value` into `hash` by its type's plan — for a step that has
    /// opened or switched its way to a payload of its own, in a local.
    package func mixValue<Value>(_ value: Value, into hash: inout UInt64) -> Bool {
        let entry = entry(for: Value.self)
        guard entry.size > 0 else { return true }
        return withUnsafeBytes(of: value) { bytes in
            unsafe mix(at: bytes.baseAddress.unsafelyUnwrapped, entry: entry, into: &hash)
        }
    }

    /// Runs the plan `entry` over the value at `base`.
    ///
    /// Each step is read from ``steps`` afresh, by its place: the step before
    /// it may have planned a new type, which appends to the list and may move
    /// it.
    private func mix(at base: UnsafeRawPointer, entry: Entry, into hash: inout UInt64) -> Bool {
        switch entry.shape {
        case .dense:
            unsafe mixDefinedRun(base, from: 0, count: Int(entry.size), into: &hash)
            return true
        case .bypass:
            #if TUI_VALUE_HASH_CENSUS
            census.noteStepBypass("a part that bypasses")
            #endif
            return false
        case .runs, .steps:
            for place in entry.runs {
                let run = unsafe runs[Int(place)]
                unsafe mixDefinedRun(base, from: run.offset, count: run.count, into: &hash)
            }
            for place in entry.steps {
                let step = unsafe steps[Int(place)]
                let at = unsafe base + step.offset
                switch step.action {
                case .typed(let type):
                    guard unsafe type._mixValueHash(at: at, into: &hash, plans: self) else { return false }
                case .existential(let field):
                    guard unsafe field.mix(at: at, into: &hash, plans: self) else { return false }
                }
            }
            return true
        }
    }
}

/// Mixes the `count` bytes at `base + start` into `hash`, loading no byte
/// outside them.
///
/// Every byte is covered, so equal bytes mix equal words and different bytes
/// different ones for a given `count`: whole words, the last of them
/// overlapping the one before when the run is not a whole number of words;
/// under a word, two overlapping halves (or quarters, or the one byte).
@inline(__always)
func mixDefinedRun(_ base: UnsafeRawPointer, from start: Int, count: Int, into hash: inout UInt64) {
    let end = start + count
    if count >= 8 {
        var offset = start
        while offset + 8 <= end {
            hash = unsafe mixHashWord(hash, base.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            offset += 8
        }
        if offset < end {
            hash = unsafe mixHashWord(hash, base.loadUnaligned(fromByteOffset: end - 8, as: UInt64.self))
        }
    } else if count >= 4 {
        let low = unsafe base.loadUnaligned(fromByteOffset: start, as: UInt32.self)
        let high = unsafe base.loadUnaligned(fromByteOffset: end - 4, as: UInt32.self)
        hash = mixHashWord(hash, UInt64(low) | UInt64(high) &<< 32)
    } else if count >= 2 {
        let low = unsafe base.loadUnaligned(fromByteOffset: start, as: UInt16.self)
        let high = unsafe base.loadUnaligned(fromByteOffset: end - 2, as: UInt16.self)
        hash = mixHashWord(hash, UInt64(low) | UInt64(high) &<< 16)
    } else if count == 1 {
        hash = unsafe mixHashWord(hash, UInt64(base.load(fromByteOffset: start, as: UInt8.self)))
    }
}
