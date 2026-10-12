//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputByteBuffer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

// MARK: - The bytes read from the terminal and not yet parsed

/// The bytes ``Terminal`` has read from standard input and not yet parsed: one
/// contiguous array whose live bytes are `storage[head..<tail]`.
///
/// TUIkit's own rather than swift-collections' `UniqueDeque`, which held them
/// until 2026-10. Linking DequeModule linked `libswiftCompatibilitySpan.dylib`,
/// a library macOS has only from 26, so a TUIkit program copied out of `.build`
/// stopped at launch on macOS 14 and 15 (`Tools/check-span-compatibility.sh`
/// says how, and CI runs it so that it stays gone). For the same reason
/// nothing here uses `Span`, `OutputSpan` or their kin: `read()` gets an
/// `UnsafeMutableBufferPointer`.
///
/// What the parser asks of it, and what each costs:
/// - A byte by its distance from the front: O(1).
/// - Removing bytes from the front: O(1). Only `head` moves; an emptied buffer
///   starts again at index 0.
/// - Putting bytes back at the front, as the parser does with an `ESC` it took
///   off and has to return: O(1) when at least that many bytes were removed in
///   front of the live ones, as they were when the parser took the `ESC` off a
///   moment before; otherwise the live bytes move up to make room. That is the
///   case for a deferred `ESC` (or `ESC ESC`) whose sequence turned up in a
///   later read: the buffer emptied in between, so the read's bytes start at
///   index 0 and move up, at most one read's worth, once per such split.
/// - A `read()` straight into free storage at the back, with no copy in
///   between: ``append(upTo:from:)``.
///
/// Appending first makes room at the back. When the live bytes and the request
/// fit in the storage it has, and the bytes already removed in front of the
/// live ones are at least as many as the live ones, the live bytes slide down
/// to index 0; otherwise the storage grows by half, or to what is needed if
/// that is more. A slide moves no more bytes than were removed since the
/// buffer last slid or grew, and growth is geometric, so the copying appends
/// cause is amortised O(1) per byte appended or removed, whatever the order of
/// the calls. ``bytesMoved`` counts it, for the tests that check that.
///
/// Nothing shrinks the storage but ``reallocate(capacity:)``, which
/// ``Terminal/consume(_:)`` calls once a large paste has gone.
struct InputByteBuffer {
    /// Every byte is initialised: storage is allocated zero-filled, never
    /// claimed initialised before it is written.
    private var storage: [UInt8]

    /// Index of the first live byte.
    private var head = 0

    /// Index one past the last live byte.
    private var tail = 0

    /// How many bytes slides, growth and ``reallocate(capacity:)`` have copied
    /// since the buffer was made.
    ///
    /// An oracle for the tests that check the copying stays linear in the
    /// bytes read (a count, not a time, so it cannot flake); nothing else
    /// reads it.
    private(set) var bytesMoved = 0

    /// A buffer with room for `minimumCapacity` bytes, at least one.
    init(minimumCapacity: Int) {
        storage = [UInt8](repeating: 0, count: max(1, minimumCapacity))
    }

    /// How many bytes the buffer holds.
    var count: Int { tail - head }

    /// Whether the buffer holds no bytes.
    var isEmpty: Bool { tail == head }

    /// How many bytes the storage has room for, live or free.
    var capacity: Int { storage.count }

    /// The byte `offset` places from the front.
    subscript(offset: Int) -> UInt8 {
        // One unsigned compare is both bounds: a negative offset is a huge
        // unsigned one.
        precondition(UInt(bitPattern: offset) < UInt(bitPattern: count), "InputByteBuffer: offset out of range")
        return storage[head &+ offset]
    }

    /// The offset from the front of the first `byte` at an offset in `range`,
    /// or `nil` when there is none.
    ///
    /// `memchr`, so that a long search runs at the C library's speed in a
    /// debug build too: what a bracketed paste's end-marker scan finds each
    /// `ESC` with (``Terminal``'s `tryExtractPaste()`).
    func firstIndex(of byte: UInt8, in range: Range<Int>) -> Int? {
        precondition(range.lowerBound >= 0 && range.upperBound <= count, "InputByteBuffer: a search outside the buffer")
        guard !range.isEmpty else { return nil }
        let start = head
        return storage.withUnsafeBufferPointer { buffer in
            // swiftlint:disable:next force_unwrapping
            let front = UnsafeRawPointer(buffer.baseAddress!) + start
            guard let found = memchr(front + range.lowerBound, Int32(byte), range.count) else { return nil }
            return front.distance(to: UnsafeRawPointer(found))
        }
    }

    /// Calls `body` with the first `count` bytes where they lie, copying
    /// nothing.
    ///
    /// How a bracketed paste becomes its string: the decoder reads the
    /// buffer's storage, so the string is the one copy of the paste made on
    /// its way to the app.
    func withUnsafeBufferPointer<Result>(
        prefix count: Int, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result {
        precondition(count >= 0 && count <= self.count, "InputByteBuffer: a prefix longer than the buffer")
        let start = head
        return try storage.withUnsafeBufferPointer { try body(UnsafeBufferPointer(rebasing: $0[start..<(start + count)])) }
    }

    /// Removes and returns the first byte, or `nil` when the buffer is empty.
    mutating func popFirst() -> UInt8? {
        guard head < tail else { return nil }
        let byte = storage[head]
        removeFirst(1)
        return byte
    }

    /// Removes `n` bytes from the front.
    mutating func removeFirst(_ n: Int) {
        precondition(n >= 0 && n <= count, "InputByteBuffer: removing more bytes than it holds")
        head += n
        if head == tail {
            head = 0
            tail = 0
        }
    }

    /// Puts `byte` back at the front.
    mutating func prepend(_ byte: UInt8) {
        makeRoomInFront(1)
        head -= 1
        storage[head] = byte
    }

    /// Puts `bytes` back at the front, in their order.
    mutating func prepend(contentsOf bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        makeRoomInFront(bytes.count)
        head -= bytes.count
        let start = head
        storage.withUnsafeMutableBufferPointer { destination in
            bytes.withUnsafeBufferPointer { source in
                // swiftlint:disable:next force_unwrapping
                (destination.baseAddress! + start).update(from: source.baseAddress!, count: source.count)
            }
        }
    }

    /// Adds `bytes` at the back, in their order.
    mutating func append(contentsOf bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        makeRoomAtBack(bytes.count)
        let start = tail
        storage.withUnsafeMutableBufferPointer { destination in
            bytes.withUnsafeBufferPointer { source in
                // swiftlint:disable:next force_unwrapping
                (destination.baseAddress! + start).update(from: source.baseAddress!, count: source.count)
            }
        }
        tail += bytes.count
    }

    /// Hands `read` free storage at the back, exactly `maximum` bytes of it,
    /// and keeps as many bytes as `read` says it wrote there.
    ///
    /// How ``Terminal/appendDrain()`` reads standard input into the buffer
    /// with no copy in between: `read` is the `read()` call.
    ///
    /// - Parameters:
    ///   - maximum: How many bytes `read` may write.
    ///   - read: Writes up to `maximum` bytes at the start of the buffer it is
    ///     given and returns how many it wrote. A negative result — a `read()`
    ///     that failed — adds nothing.
    /// - Returns: How many bytes were added.
    @discardableResult
    mutating func append(upTo maximum: Int, from read: (UnsafeMutableBufferPointer<UInt8>) -> Int) -> Int {
        precondition(maximum >= 0, "InputByteBuffer: a negative read")
        makeRoomAtBack(maximum)
        let start = tail
        let written = storage.withUnsafeMutableBufferPointer { buffer in
            read(UnsafeMutableBufferPointer(rebasing: buffer[start..<(start + maximum)]))
        }
        precondition(written <= maximum, "InputByteBuffer: a read wrote past the room it was given")
        let added = max(written, 0)
        tail += added
        return added
    }

    /// Moves the live bytes into new storage of `capacity` bytes, or of
    /// ``count`` if that is more.
    mutating func reallocate(capacity: Int) {
        rebuild(capacity: max(capacity, count, 1), liveAt: 0)
    }

    // MARK: Making room

    /// Makes `needed` bytes free after `tail`: a slide when it pays for
    /// itself, growth otherwise (see the type's discussion).
    private mutating func makeRoomAtBack(_ needed: Int) {
        guard tail + needed > storage.count else { return }
        let live = count
        if live + needed <= storage.count && head >= live {
            moveLive(to: 0)
        } else {
            rebuild(capacity: Self.grownCapacity(from: storage.count, toHold: live + needed), liveAt: 0)
        }
    }

    /// Makes `needed` bytes free before `head`, moving the live bytes up, into
    /// grown storage if they no longer fit.
    private mutating func makeRoomInFront(_ needed: Int) {
        guard head < needed else { return }
        let live = count
        if needed + live <= storage.count {
            moveLive(to: needed)
        } else {
            rebuild(capacity: Self.grownCapacity(from: storage.count, toHold: needed + live), liveAt: needed)
        }
    }

    /// The capacity to grow `capacity` to for `required` bytes: half as much
    /// again, or `required` if that is more.
    ///
    /// Half as much again stops at `Int.max` rather than overflowing. Only a
    /// 32-bit `Int` gets there (WebAssembly's): a paste has no size limit, and
    /// past about 1.4 GiB the half added would take it over, which traps.
    /// Stopping there leaves the allocation to say whether the memory exists.
    static func grownCapacity(from capacity: Int, toHold required: Int) -> Int {
        max(required, capacity + min(capacity / 2, Int.max - capacity))
    }

    /// Moves the live bytes, within the storage, to start at `offset`.
    private mutating func moveLive(to offset: Int) {
        let (from, live) = (head, count)
        storage.withUnsafeMutableBufferPointer { buffer in
            // swiftlint:disable:next force_unwrapping
            let base = buffer.baseAddress!
            // A `memmove`: the two ranges may overlap, which `update(from:count:)`
            // allows (it copies front to back or back to front as they need).
            (base + offset).update(from: base + from, count: live)
        }
        head = offset
        tail = offset + live
        bytesMoved += live
    }

    /// Replaces the storage with `capacity` zeroed bytes, the live bytes
    /// copied in at `offset`.
    private mutating func rebuild(capacity: Int, liveAt offset: Int) {
        let (from, live) = (head, count)
        var fresh = [UInt8](repeating: 0, count: capacity)
        if live > 0 {
            fresh.withUnsafeMutableBufferPointer { destination in
                storage.withUnsafeBufferPointer { source in
                    // swiftlint:disable:next force_unwrapping
                    (destination.baseAddress! + offset).update(from: source.baseAddress! + from, count: live)
                }
            }
        }
        storage = fresh
        head = offset
        tail = offset + live
        bytesMoved += live
    }
}
