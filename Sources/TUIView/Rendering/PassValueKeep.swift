//  🖥️ TUI — A Terminal UI framework for Swift
//  PassValueKeep.swift
//
//  The values a pass's measure memo stored sizes for, kept alive until its
//  entries are emptied, so that no address a key read can name another value
//  meanwhile (`RenderCache.measuredValues`).
//
//  Created by Wade Tregaskis
//  License: MIT

/// Values kept alive for a pass, in a buffer per type.
///
/// Not an `[Any]`: a value of more than three words boxed into an `Any` is an
/// allocation of its own, and the measure memo stores one per measured view.
/// Boxed, that cost `app-shapes/grouped-form` +14.5% CPU a frame, 26% more
/// allocations and 41 MB more memory, and `churn` +4.9%, against nothing kept
/// (`ab_bench.py`, 2026-11-15). Kept in a buffer of its own type, a value is
/// copied into memory that is reused from pass to pass.
///
/// Nor an `[Value]` reached by a downcast, the first typed cut: ``keep(_:)``
/// runs unspecialised, inside the measure, and there naming
/// `KeptArray<Value>` to cast to and appending to an `Array<Value>` each looked
/// up generic metadata, and the append asked whether `Value` is a class
/// (bridging), on every store — 158,000 a frame on `grouped-form`, where the
/// keep was 6.4% of the frame inclusive, most of it those lookups rather than
/// the copy (Time Profiler, 2026-11-15). A buffer is asked to copy the value
/// through a method its own class overrides, which reads `Value` from the
/// buffer it is called on: no lookup, and no `Array`. The keep is 3.3% of the
/// same frame so, nearly all of it the copy's retains.
struct PassValueKeep {
    /// The buffer of each type kept so far.
    private var buffers: [ObjectIdentifier: KeptValues] = [:]

    /// The buffers holding something this pass: what ``release()`` empties.
    private var holding: [KeptValues] = []

    /// The type kept last, and its buffer: the measure memo stores runs of one
    /// type often enough, a `Text`'s, a row's, to save the table its probe.
    private var lastType: ObjectIdentifier?
    private var lastBuffer: KeptValues?

    /// Keeps `value` alive until ``release()``, unless its type holds no
    /// reference (`_isPOD`): then no address in its bytes can be freed.
    @inline(__always)
    mutating func keep<Value>(_ value: Value) {
        guard !_isPOD(Value.self) else { return }
        let type = ObjectIdentifier(Value.self)
        let buffer: KeptValues
        if type == lastType, let lastBuffer {
            buffer = lastBuffer
        } else {
            if let existing = buffers[type] {
                buffer = existing
            } else {
                buffer = unsafe KeptBuffer<Value>()
                buffers[type] = buffer
            }
            lastType = type
            lastBuffer = buffer
        }
        if unsafe buffer.held == 0 { holding.append(buffer) }
        // The buffer was made for `Value`, under its type's identifier.
        withUnsafePointer(to: value) { unsafe buffer.append(copying: UnsafeRawPointer($0)) }
    }

    /// Lets go of everything kept.
    mutating func release() {
        guard !holding.isEmpty else { return }
        for buffer in holding { buffer.release() }
        holding.removeAll(keepingCapacity: true)
    }
}

/// One type's kept values, behind a class so that the keep can hold buffers
/// of every type in one table, and copy into one without naming its type.
private class KeptValues {
    /// How many values the buffer holds. `@exclusivity(unchecked)`: a class's
    /// stored variable is otherwise checked at run time on every access, and
    /// each access here is one read or write that calls nothing while it
    /// lasts, so no two can overlap.
    @exclusivity(unchecked) final var held = 0

    /// Copies the value at `value`, of the type the buffer was made for, in.
    func append(copying value: UnsafeRawPointer) {}

    /// Lets go of the values.
    func release() {}
}

/// The kept values of one type, in memory of its own.
///
/// `@unsafe`: it holds memory of its own. Exactly the first ``held`` places
/// are initialised, ``capacity`` places are allocated, and the class alone
/// allocates, initialises, destroys and frees them; nothing outside this file
/// sees it.
@unsafe private final class KeptBuffer<Value>: KeptValues {
    /// The places a buffer starts with, and keeps after a pass that held
    /// far fewer than it has.
    private static var initialCapacity: Int { 64 }

    @exclusivity(unchecked) private var base: UnsafeMutablePointer<Value>
    @exclusivity(unchecked) private var capacity: Int

    override init() {
        unsafe capacity = Self.initialCapacity
        unsafe base = .allocate(capacity: Self.initialCapacity)
    }

    deinit {
        unsafe base.deinitialize(count: held)
        unsafe base.deallocate()
    }

    override func append(copying value: UnsafeRawPointer) {
        if unsafe held == capacity { unsafe grow() }
        unsafe (base + held).initialize(from: value.assumingMemoryBound(to: Value.self), count: 1)
        unsafe held += 1
    }

    /// Doubles the room, moving what is held.
    private func grow() {
        let larger = unsafe capacity * 2
        let moved = UnsafeMutablePointer<Value>.allocate(capacity: larger)
        unsafe moved.moveInitialize(from: base, count: held)
        unsafe base.deallocate()
        unsafe base = moved
        unsafe capacity = larger
    }

    /// Empties the buffer, keeping its room for the next pass unless it is
    /// holding four times what it held this one: the first frame stores a size
    /// for nearly every view, and a steady one a few.
    override func release() {
        unsafe base.deinitialize(count: held)
        if unsafe capacity > 4 * held + Self.initialCapacity {
            unsafe base.deallocate()
            unsafe base = .allocate(capacity: Self.initialCapacity)
            unsafe capacity = Self.initialCapacity
        }
        unsafe held = 0
    }
}
