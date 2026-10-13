//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicTypes.swift
//
//  The dynamic type of what an existential field holds, read where the
//  field lies, without copying it out: for the property walk, which plans
//  what such a field holds by that type, and for the probe that decides,
//  before any copy of a view is made, whether the walk has anything to do.
//
//  Two runtime layouts are read here, both part of Swift's stable ABI
//  (swift/ABI/Metadata.h, swift/ABI/MetadataValues.h):
//
//  - An existential type's metadata: its kind, then a 32-bit flags word. Bit
//    31 is set when the existential is NOT class-constrained; bits 24-29 name
//    a special protocol (`Error`). A class-constrained one (`AnyObject`,
//    `any P` where `P: AnyObject`) is an object reference followed by its
//    witness tables; any other ordinary one (`Any`, `any P`) is a buffer of
//    three words, then the metadata of the type it holds, then its witness
//    tables. Measured on macOS arm64 for `Any`, `any P`, `AnyObject`, a
//    class-constrained protocol, a composition with a superclass and
//    `any Error` (session notes `DYNVFIX/probe/exflags/exflags.swift`).
//  - A value of a class held in that buffer is its reference, in the buffer's
//    first word, and the metadata names the type it was erased from, which
//    may be a superclass of its class: the class is the object's.
//
//  A `nil` optional of an existential or of a class is all zeros (measured,
//  the same probe): the metadata word, or the reference, is null.
//
//  Created by Wade Tregaskis
//  License: MIT

/// How values of an existential type are laid out, as far as reading their
/// dynamic type where they lie goes.
enum ExistentialLayout {
    /// A buffer of three words, then the held type's metadata: `Any`, `any P`.
    case opaque
    /// An object reference: `AnyObject`, a class-constrained `any P`.
    case object
    /// Another — `any Error`'s box, a constrained existential's shape: read
    /// by copying the value out.
    case other

    /// The layout of values of `type`, an existential type.
    init(_ type: Any.Type) {
        guard RuntimeFields.Kind(of: type) == .existential else {
            self = .other
            return
        }
        // A metatype's address is data, which `-deduplicate` never moves; read, not compared.
        // swiftlint:disable:next function_address_identity
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        let flags = metadata.load(fromByteOffset: MemoryLayout<Int>.size, as: UInt32.self)
        if flags & 0x3F00_0000 != 0 {
            self = .other
        } else if flags & 0x8000_0000 != 0 {
            self = .opaque
        } else {
            self = .object
        }
    }
}

/// What reading a value's dynamic type where it lies found.
enum DynamicTypeRead {
    /// No value: a `nil` optional.
    case empty
    /// A value of this type.
    case type(Any.Type)
    /// A value whose type is read only by copying it out: an existential
    /// held in an existential, which generic code can make.
    case unknown
}

/// Reading a value's dynamic type where it lies.
enum DynamicTypes {
    /// The dynamic type of what the existential laid out as `layout` at
    /// `address` holds — or, for an optional of it, `.empty` when it is `nil`.
    static func existential(at address: UnsafeRawPointer, _ layout: ExistentialLayout) -> DynamicTypeRead {
        switch layout {
        case .object:
            return object(at: address)
        case .other:
            return .unknown
        case .opaque:
            guard let metadata = address.load(
                fromByteOffset: 3 * MemoryLayout<UnsafeRawPointer>.size, as: UnsafeRawPointer?.self)
            else { return .empty }
            let type = unsafeBitCast(metadata, to: Any.Type.self)
            let kind = RuntimeFields.Kind(of: type)
            // The metadata names the type the value was erased from; an
            // object's class may be a subclass of it.
            if kind.isClass { return object(at: address) }
            if kind == .existential || kind == .extendedExistential { return .unknown }
            return .type(type)
        }
    }

    /// The class of the object an `unowned` reference at `address` holds,
    /// read where the reference lies — or `.empty` for a `nil` optional of
    /// one, and for one only the runtime reads. A reference to a native
    /// Swift object is the object's address, whose memory the unowned count
    /// keeps while the field holds it, alive or not. Where Objective-C
    /// interoperates, a class-bound existential can hold an object whose
    /// class has an Objective-C ancestor; held `unowned`, that reference is
    /// the address of a cell the runtime allocates for an Objective-C weak
    /// reference, marked by its lowest bit, which a native object's aligned
    /// address leaves clear (measured on macOS 15 arm64, alive and gone, and
    /// for a tagged pointer: session notes `DYNVFIX/probe/unex`). Elsewhere
    /// every object is a native one.
    static func unownedObject(at address: UnsafeRawPointer) -> DynamicTypeRead {
        #if _runtime(_ObjC)
            if address.load(as: UInt.self) & 1 != 0 { return .empty }
        #endif
        return object(at: address)
    }

    /// The class of the object whose reference lies at `address`, held
    /// strongly — or `.empty` for a `nil` optional of one.
    static func object(at address: UnsafeRawPointer) -> DynamicTypeRead {
        guard let reference = address.load(as: UnsafeRawPointer?.self) else { return .empty }
        let objectType: Any.Type = Unmanaged<AnyObject>.fromOpaque(reference)._withUnsafeGuaranteedRef {
            type(of: $0)
        }
        return .type(objectType)
    }
}

/// Loading the object a field held `weak` or `unowned` holds, where the
/// field lies, as Swift loads one: as a reference to `AnyObject` held the same
/// way, whatever the field's declared class or class-bound existential. Each
/// way of holding one reference has one layout, the runtime telling a native
/// object from an Objective-C one by the reference itself — measured on macOS
/// arm64 for a native class, a class with an Objective-C ancestor and a
/// class-bound existential, each held `weak` and `unowned`, alive and gone
/// (session notes `DYNVFIX/probe/typedref`). Where Objective-C does not
/// interoperate, every reference is a native one.
///
/// No copy of the struct or object holding the field is made, as a load
/// through the runtime's reflection makes one.
enum HeldReferences {
    private struct Weak {
        weak var object: AnyObject?
    }

    private struct Unowned {
        unowned let object: AnyObject
    }

    private struct OptionalUnowned {
        unowned var object: AnyObject?
    }

    private struct UnownedUnsafe {
        unowned(unsafe) let object: AnyObject
    }

    private struct OptionalUnownedUnsafe {
        unowned(unsafe) var object: AnyObject?
    }

    /// The object the field at `address`, held as `ownership` says and an
    /// optional if `isOptional`, holds: `nil` for a `weak` one whose object
    /// has gone, or an optional one that holds none. One held `unowned`
    /// whose object has gone traps, as reading it in Swift does.
    static func load(at address: UnsafeRawPointer, _ ownership: FieldDescriptors.Ownership, isOptional: Bool)
        -> AnyObject?
    {
        switch (ownership, isOptional) {
        case (.strong, _):
            address.assumingMemoryBound(to: AnyObject?.self).pointee
        case (.weak, _):
            address.assumingMemoryBound(to: Weak.self).pointee.object
        case (.unowned, false):
            address.assumingMemoryBound(to: Unowned.self).pointee.object
        case (.unowned, true):
            address.assumingMemoryBound(to: OptionalUnowned.self).pointee.object
        case (.unownedUnsafe, false):
            address.assumingMemoryBound(to: UnownedUnsafe.self).pointee.object
        case (.unownedUnsafe, true):
            address.assumingMemoryBound(to: OptionalUnownedUnsafe.self).pointee.object
        }
    }
}

/// Dynamic types a field was found holding that hold nothing the walk acts
/// on, kept so the next body that finds one there reads no further: the last
/// two found in this field, compared first, and every one found in any field,
/// asked when neither is it.
///
/// A plan is kept per declared type, so every `Any` field shares one, and
/// every `any Palette` field another: with three types in turn the last two
/// kept missing, and each view holding one was copied and walked on every
/// body (review of 4388af345, 2026-10-12). Whether a type holds nothing is
/// the type's alone (``PropertyPlans/exact(_:)``), so one answer serves every
/// field.
///
/// Read by the probe that runs before a view is copied
/// (``RootProbe/findsSomething(at:)``), so kept behind pointers that are
/// never freed, as the plans holding it never are: a stored property of a
/// class is checked for exclusive access at run time on every read.
struct EmptyTypes {
    private let entries: UnsafeMutablePointer<UInt>
    /// Every type found holding nothing, in any field
    /// (``PropertyPlans/emptyTypes``).
    private let everywhere: UnsafeMutablePointer<Set<ObjectIdentifier>>

    init(everywhere: UnsafeMutablePointer<Set<ObjectIdentifier>>) {
        entries = .allocate(capacity: 2)
        entries.initialize(repeating: 0, count: 2)
        self.everywhere = everywhere
    }

    /// Whether `type` is known to hold nothing: one of the two last noted
    /// here, or one noted in any field, which this field then notes.
    func contains(_ type: Any.Type) -> Bool {
        let bits = UInt(bitPattern: ObjectIdentifier(type))
        if entries[0] == bits || entries[1] == bits { return true }
        guard everywhere.pointee.contains(ObjectIdentifier(type)) else { return false }
        note(bits)
        return true
    }

    /// Notes `type`, here and for every field.
    func insert(_ type: Any.Type) {
        note(UInt(bitPattern: ObjectIdentifier(type)))
        everywhere.pointee.insert(ObjectIdentifier(type))
    }

    /// Notes the type with identifier `bits` here, dropping the older of the
    /// two.
    private func note(_ bits: UInt) {
        entries[1] = entries[0]
        entries[0] = bits
    }
}

/// One field of a view that the walk acts on only if its value says so — an
/// existential holding a property, a plain class field holding a subclass
/// that is one — read before the view is copied, so a view whose such fields
/// hold nothing is evaluated as it is
/// (``preparedBody(of:plan:context:isMeasuring:)``).
struct RootProbe {
    enum Kind {
        /// An existential (or an optional of one) laid out so.
        case existential(ExistentialLayout)
        /// A plain class held strongly (or an optional of one), the bits of
        /// its declared class's identifier: its class read where the
        /// reference lies.
        case object(declared: UInt)
        /// A plain class, or a class-bound existential, held `unowned` (or
        /// an optional of one), the bits of its declared type's identifier:
        /// its class read where the reference lies
        /// (``DynamicTypes/unownedObject(at:)``).
        case unowned(declared: UInt)
        /// A plain class, or a class-bound existential, held `weak`, the bits
        /// of its declared type's identifier: its object loaded, as the walk
        /// loads it.
        case weak(declared: UInt)
    }

    /// The field's byte offset in the view.
    let offset: Int
    let kind: Kind
    /// The types this field's plan found holding nothing.
    let empty: EmptyTypes

    /// Whether the field at `address` holds something the walk may act on:
    /// a value of a type not known to hold nothing.
    func findsSomething(at address: UnsafeRawPointer) -> Bool {
        let read: DynamicTypeRead
        switch kind {
        case .existential(let layout):
            read = DynamicTypes.existential(at: address, layout)
        case .object(let declared):
            read = DynamicTypes.object(at: address)
            if case .type(let type) = read, UInt(bitPattern: ObjectIdentifier(type)) == declared { return false }
        case .unowned(let declared):
            read = DynamicTypes.unownedObject(at: address)
            if case .type(let type) = read, UInt(bitPattern: ObjectIdentifier(type)) == declared { return false }
        case .weak(let declared):
            guard let object = HeldReferences.load(at: address, .weak, isOptional: true) else { return false }
            let type: Any.Type = type(of: object)
            if UInt(bitPattern: ObjectIdentifier(type)) == declared { return false }
            read = .type(type)
        }
        switch read {
        case .empty: return false
        case .unknown: return true
        case .type(let type): return !empty.contains(type)
        }
    }
}

/// Whether a probe of `probes` finds something the walk may act on in
/// `value`. Nonisolated, and so is the closure it reads `value` through: a
/// main-actor closure handed to the standard library carries a run-time check
/// in a release build that it runs on the main actor.
func probesFindSomething<V>(in value: V, _ probes: [RootProbe]) -> Bool {
    withUnsafePointer(to: value) { pointer in
        let base = UnsafeRawPointer(pointer)
        for probe in probes where probe.findsSomething(at: base + probe.offset) {
            return true
        }
        return false
    }
}
