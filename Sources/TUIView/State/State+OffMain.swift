//  🖥️ TUI — A Terminal UI framework for Swift
//  State+OffMain.swift
//
//  `State` and `Binding` are `Sendable`, as SwiftUI's are, and how a `@State`
//  is read and written off the main actor with no lock on it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Dispatch)
    import Dispatch
#endif
import Synchronization
import TUICore

// MARK: - Sendable

// `State`'s conformance is in State.swift, where a checked one has to be.

/// A `Binding` crosses to another thread, as SwiftUI's does, where its value
/// can: SwiftUI's conformance exactly, `@unchecked` there too, since a
/// binding is closures that say nothing of where they may run. The lint
/// exception is that spelling: SwiftUI's own.
///
/// A `@State`'s binding may be read and written on any thread. A binding made
/// with ``init(get:set:)`` runs its closures on whichever thread uses it, so
/// it is as safe as they are; one TUI makes for something other than a
/// `@State` — `@FocusState`, `@AppStorage`, a presentation's — is for the
/// main actor.
extension Binding: @unchecked Sendable where Value: Sendable {}  // swiftlint:disable:this concurrency_escape

/// Holds nothing a thread other than the main actor's reads unsynchronised:
/// that is ``StateBacking/value``'s design. `@unchecked` because its box is
/// touched on the main actor only, which the compiler cannot see; and needed,
/// for `State`'s conformance to be SwiftUI's checked one.
extension StateBacking: @unchecked Sendable where Value: Sendable {}  // swiftlint:disable:this concurrency_escape

// MARK: - Off the main actor

/// The owner's O-25 (2026-11-21): a `@State` is read and written on any thread,
/// with nothing added to the main actor's reads and writes, which stay in
/// place, unlocked.
///
/// - **A write off the main actor** is not made in place: it is posted to the
///   main queue, which is the main actor's, and made there, in the order it was
///   posted, under the transaction it was made in — so before any frame drawn
///   after it. It takes effect at the next frame either way.
/// - **A read off the main actor** takes a copy of the value from a channel
///   the box keeps (``OffMainChannel``), behind a lock no main-actor read
///   takes. The box makes the channel on the main actor, the first time a read
///   off it asks, which waits for the main actor that once; from then on every
///   write to the box republishes its value there, and a write off the main
///   actor publishes what it wrote at once, so a read after it on the same
///   thread reads it back. Until the main actor has made it, the box's own
///   writes are not republished over it (``OffMainCopy/unmadeWrites``): a
///   loop of `append`s off the main actor once lost the writes the main actor
///   had not yet caught up with.
///
/// No lock is ever held across a `yield`, nor taken on the main actor but to
/// republish to a channel some other thread has asked for.
extension StateBacking {
    /// The value, read and written on any thread.
    var value: Value {
        get {
            guard StateIsolation.isMainActor else { return valueOffMain() }
            return box.value
        }
        set {
            guard StateIsolation.isMainActor else {
                writeOffMain(newValue)
                return
            }
            box.value = newValue
        }
    }

    /// The box moved: a route reads off the main actor take follows it.
    @inline(__always)
    func offMainRouteDidMove() {
        let bits = offMainRouteBits.load(ordering: .relaxed)
        guard bits != 0 else { return }
        OffMainPointer.object(bits, as: OffMainRoute<Value>.self).replace(with: box.openOffMainChannel())
    }

    /// The route reads off the main actor take, made now if there is none. On
    /// the main actor.
    func openOffMainRoute() -> OffMainRoute<Value> {
        let bits = offMainRouteBits.load(ordering: .relaxed)
        if bits != 0 { return OffMainPointer.object(bits, as: OffMainRoute<Value>.self) }
        let route = OffMainRoute(box.openOffMainChannel())
        offMainRouteBits.store(OffMainPointer.retainedBits(of: route), ordering: .releasing)
        return route
    }

    #if canImport(Dispatch)
        /// The last value published: the box's, or one written off the main
        /// actor since and not yet made.
        private func valueOffMain() -> Value {
            let bits = offMainRouteBits.load(ordering: .acquiring)
            if bits != 0 {
                return OffMainPointer.object(bits, as: OffMainRoute<Value>.self).value.copy()
            }
            // The first read off the main actor waits for it, once: the box
            // is the main actor's to read. Behind the writes this thread
            // posted, so what it reads back includes them.
            let backing = OffMainCell(self)
            return DispatchQueue.main.sync { backing.value.openOffMainRoute() }.value.copy()
        }

        /// Posts `newValue` to the main actor, publishing it at once to the
        /// reads off it, once there are any.
        private func writeOffMain(_ newValue: Value) {
            let bits = offMainRouteBits.load(ordering: .acquiring)
            let channel = bits == 0 ? nil : OffMainPointer.object(bits, as: OffMainRoute<Value>.self).value
            channel?.publishOffMain(newValue)
            // Made on the main actor under the transaction in force here,
            // which one made there would have been made under.
            let write = OffMainCell((backing: self, value: newValue, transaction: Transaction.ambient, channel: channel))
            DispatchQueue.main.async {
                let (backing, value, transaction, channel) = write.value
                if let transaction {
                    Transaction.$ambient.withValue(transaction) { backing.box.value = value }
                } else {
                    backing.box.value = value
                }
                channel?.offMainWriteMade()
            }
        }
    #else
        // One thread, with no queue to post to: every access is the main
        // actor's (`MainActorCheck`).
        private func valueOffMain() -> Value { box.value }
        private func writeOffMain(_ newValue: Value) { box.value = newValue }
    #endif
}

/// Whether a `@State` is being read or written on the main actor.
enum StateIsolation {
    /// ``MainActorCheck/isCurrent``, but first, off Darwin, whether this is
    /// the thread drawing a frame, a thread-local read: there a pool thread
    /// drains the main actor, and the check asks the queue, which costs more.
    @inline(__always)
    static var isMainActor: Bool {
        #if canImport(Darwin) || canImport(WASILibc)
            MainActorCheck.isCurrent
        #else
            BindingReads.isWalkingThread || MainActorCheck.isCurrent
        #endif
    }
}

/// A value a thread other than the main actor's reads, behind a lock no
/// main-actor read takes: a box's copy of its value for reads off the main
/// actor (its channel, ``StateBox/openOffMainChannel()``), which the box
/// republishes at every write once it has one; a backing's way to its box's
/// channel (its route), which the backing moves as its box changes; and a
/// write made off the main actor, on its way to it.
///
/// `@unchecked` because what it holds need not be `Sendable`: a `@State` of a
/// value that is not can only be reached off the main actor by code that
/// turned the checks off, and then gets the same lock.
final class OffMainCell<Content>: @unchecked Sendable {  // swiftlint:disable:this concurrency_escape
    private let lock = Mutex(())
    private var content: Content

    init(_ content: Content) {
        self.content = content
    }

    /// What the cell holds, copied — retained, for a reference — before the
    /// lock is let go, so nothing the main actor lets go of meanwhile can take
    /// it along.
    var value: Content {
        var value: Content?
        update { value = $0 }
        // swiftlint:disable:next force_unwrapping
        return value!
    }

    /// Replaces what the cell holds, letting go of what it held after the
    /// lock, since its release may run a deinit.
    func replace(with newContent: Content) {
        var displaced = newContent
        update { swap(&$0, &displaced) }
    }

    /// Runs `body` on what the cell holds, under its lock: a few loads and
    /// stores, calling nothing out.
    func update(_ body: (inout Content) -> Void) {
        lock.withLock { _ in body(&content) }
    }
}

/// A strong reference kept as the bits of its pointer, in an `Atomic<UInt>`,
/// `0` for none: one load. An `Atomic` of `Unmanaged<OffMainRoute<Value>>?`
/// in a generic class goes through its generic witnesses where it is not
/// specialized — every `deinit` of one — about 39 ns a load against 1.3
/// (arm64 `-O`, 2026-11-21), which cost the `stateful` Stress scenario 4.3%
/// a frame. The type is named only where the bits are not `0`, so the
/// metadata of a generic one is never asked for where there is none.
enum OffMainPointer {
    /// The bits of `object`'s pointer, retained, to be released by
    /// ``release(_:)``.
    static func retainedBits(of object: AnyObject) -> UInt {
        UInt(bitPattern: unsafe Unmanaged.passRetained(object).toOpaque())
    }

    /// The object `bits`, which are not `0`, point at, unretained: what the
    /// bits stand for keeps it.
    @inline(__always)
    static func object<T: AnyObject>(_ bits: UInt, as _: T.Type) -> T {
        // swiftlint:disable:next force_unwrapping
        unsafe Unmanaged<T>.fromOpaque(UnsafeRawPointer(bitPattern: bits)!).takeUnretainedValue()
    }

    /// Releases the object `bits`, which are not `0`, point at.
    static func release(_ bits: UInt) {
        // swiftlint:disable:next force_unwrapping
        unsafe Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: bits)!).release()
    }
}

/// A box's value as reads off the main actor see it, and how many writes made
/// off it are on their way to it.
struct OffMainCopy<Value> {
    var value: Value
    /// Writes made off the main actor, published here and not yet made on it.
    /// While there are any, the box's own writes are not published: each is
    /// older than the last written here, and will be overwritten by it, so a
    /// read-modify-write off the main actor (an `append`) builds on its own
    /// last write, not on one the main actor has only just caught up with.
    var unmadeWrites = 0
}

/// A box's copy of its value, as reads off the main actor see it.
typealias OffMainChannel<Value> = OffMainCell<OffMainCopy<Value>>

extension OffMainCell {
    /// The value, copied under the lock.
    func copy<Value>() -> Value where Content == OffMainCopy<Value> {
        var value: Value?
        update { value = $0.value }
        // swiftlint:disable:next force_unwrapping
        return value!
    }

    /// Publishes the box's `value`, written on the main actor, unless a write
    /// made off it is still on its way (``OffMainCopy/unmadeWrites``).
    func publish<Value>(_ value: Value) where Content == OffMainCopy<Value> {
        var displaced = value
        update { copy in
            if copy.unmadeWrites == 0 { swap(&copy.value, &displaced) }
        }
    }

    /// Publishes `value`, written off the main actor and posted to it.
    func publishOffMain<Value>(_ value: Value) where Content == OffMainCopy<Value> {
        var displaced = value
        update { copy in
            swap(&copy.value, &displaced)
            copy.unmadeWrites += 1
        }
    }

    /// A write ``publishOffMain(_:)`` published has been made on the main
    /// actor.
    func offMainWriteMade<Value>() where Content == OffMainCopy<Value> {
        update { $0.unmadeWrites -= 1 }
    }
}

/// A backing's way to its box's ``OffMainChannel``.
typealias OffMainRoute<Value> = OffMainCell<OffMainChannel<Value>>
