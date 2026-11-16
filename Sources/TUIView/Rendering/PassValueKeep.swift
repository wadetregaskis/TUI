//  🖥️ TUI — A Terminal UI framework for Swift
//  PassValueKeep.swift
//
//  The values a pass's measure memo stored sizes for, kept alive until its
//  entries are emptied, so that no address a key read can name another value
//  meanwhile (`RenderCache.measuredValues`).
//
//  Created by Wade Tregaskis
//  License: MIT

/// Values kept alive for a pass, in an array per type.
///
/// Not an `[Any]`: a value of more than three words boxed into an `Any` is an
/// allocation of its own, and the measure memo stores one per measured view.
/// Boxed, that cost `app-shapes/grouped-form` +14.5% CPU a frame, 26% more
/// allocations and 41 MB more memory, and `churn` +4.9%, against nothing kept
/// (`ab_bench.py`, 2026-11-15). Kept in an array of its own type, a value is
/// copied into a buffer that is reused from pass to pass.
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
        } else if let existing = buffers[type] {
            buffer = existing
        } else {
            buffer = KeptArray<Value>()
            buffers[type] = buffer
        }
        lastType = type
        lastBuffer = buffer
        // The buffer was made for `Value`, under its type's identifier.
        let typed = unsafe unsafeDowncast(buffer, to: KeptArray<Value>.self)
        if typed.values.isEmpty { holding.append(buffer) }
        typed.values.append(value)
    }

    /// Lets go of everything kept.
    mutating func release() {
        guard !holding.isEmpty else { return }
        for buffer in holding { buffer.release() }
        holding.removeAll(keepingCapacity: true)
    }
}

/// One type's kept values, behind a class so that the keep can hold buffers
/// of every type in one table.
private class KeptValues {
    /// Lets go of the values.
    func release() {}
}

/// The kept values of one type.
private final class KeptArray<Value>: KeptValues {
    var values: [Value] = []

    /// Empties the buffer, keeping its room for the next pass unless it is
    /// holding four times what it held this one: the first frame stores a size
    /// for nearly every view, and a steady one a few.
    override func release() {
        values.removeAll(keepingCapacity: values.capacity <= 4 * values.count + 64)
    }
}
