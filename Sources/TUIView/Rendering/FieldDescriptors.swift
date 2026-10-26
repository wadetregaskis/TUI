//  🖥️ TUI — A Terminal UI framework for Swift
//  FieldDescriptors.swift
//
//  A type's field records, read from the field descriptor the compiler emits
//  for it: what the runtime's reflection entry points (`RuntimeFields`) read
//  them from, for what those entry points do not hand back.
//
//  The layouts read here are part of Swift's stable ABI:
//
//  - A struct's or an enum's metadata: its kind, then its nominal type
//    descriptor (swift/ABI/Metadata.h, `TargetValueMetadata`). A Swift
//    class's metadata: its kind (the `isa` where Objective-C interoperates),
//    its superclass, where Objective-C interoperates two words of cache and
//    one of data, then 24 bytes of flags and sizes, then its descriptor
//    (`TargetClassMetadata`). Measured on macOS arm64
//    (`Tools/SwiftUIProbes/Swift runtime layouts/own.swift`); the layout without Objective-C is the
//    same less those three words, reasoned, not measured.
//  - The type descriptor: flags (the low five bits its kind: 16 a class, 17
//    a struct), parent, name and access function, 32 bits each, then a
//    relative pointer to its field descriptor (`TargetTypeContextDescriptor`).
//  - The field descriptor: its mangled type name and superclass, relative
//    pointers; its kind and record size, 16 bits each; its record count, 32
//    bits; then the records. Each record is a flags word, a relative pointer
//    to the field's mangled type name (absent for an enum case without a
//    payload), and one to its name (swift/RemoteInspection/Records.h). An
//    enum's records are its cases, payload cases first in declaration order
//    and then the empty ones: record `i` is the case whose tag is `i`. A
//    class's are its own stored fields, not its superclasses'.
//  - A field's mangled type name ends with its ownership when that is not
//    strong: `Xw` for `weak`, `Xo` for `unowned`, `Xu` for `unowned(unsafe)`
//    (swift/docs/ABI/Mangling.rst). Its symbolic references — a byte from 1
//    to 0x17 and a 32-bit offset, or a byte from 0x18 to 0x1F and a pointer —
//    are addresses, not characters, and are stepped over.
//
//  Where pointers are signed (arm64e), a descriptor's address is one, and
//  reading the ownership is not attempted.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A type's field records, as its field descriptor lists them.
enum FieldDescriptors {
    /// One record: a stored field, or an enum's case.
    struct Record {
        /// Its flags. Bit 0: an enum case is `indirect`.
        let flags: UInt32
        /// The field's mangled type name, or `nil` for an enum case without
        /// a payload.
        let mangledTypeName: UnsafeRawPointer?
        /// The field's name, a C string, or `nil` where the record has none.
        let name: UnsafeRawPointer?
    }

    /// How a stored field holds its value.
    enum Ownership {
        case strong
        case weak
        case unowned
        case unownedUnsafe
    }

    /// The records of `type`, a struct or an enum, or `nil` if it has no
    /// field descriptor to read.
    static func records(ofValueType type: Any.Type) -> [Record]? {
        guard let description = valueTypeDescriptor(of: type) else { return nil }
        return records(described: description)
    }

    /// The ownership of the stored field at `index` among those `owner`
    /// declares — a struct's fields, or a Swift class's own, not its
    /// superclasses' — whose name is `name`; or `nil` where its record cannot
    /// be read, or is not that field's.
    static func ownership(ofField index: Int, named name: String, in owner: Any.Type) -> Ownership? {
        #if _ptrauth(_arm64e)
            return nil
        #else
            let description: UnsafeRawPointer?
            switch RuntimeFields.Kind(of: owner) {
            case .struct:
                description = valueTypeDescriptor(of: owner).flatMap { described($0, as: 17) }
            case .class:
                description = classDescriptor(of: owner).flatMap { described($0, as: 16) }
            default:
                description = nil
            }
            guard let description, let records = records(described: description), index < records.count,
                let recordName = records[index].name,
                String(cString: recordName.assumingMemoryBound(to: CChar.self)) == name,
                let mangledTypeName = records[index].mangledTypeName
            else { return nil }
            return ownership(ofMangledName: mangledTypeName)
        #endif
    }

    /// The ownership a field's mangled type name ends with.
    static func ownership(ofMangledName name: UnsafeRawPointer) -> Ownership {
        let bytes = name.assumingMemoryBound(to: UInt8.self)
        var index = 0
        // The last two characters read: none across a symbolic reference.
        var previous: UInt8 = 0
        var last: UInt8 = 0
        while bytes[index] != 0 {
            switch bytes[index] {
            case 0x01...0x17:
                index += 1 + MemoryLayout<Int32>.size
                previous = 0
                last = 0
            case 0x18...0x1F:
                index += 1 + MemoryLayout<UnsafeRawPointer>.size
                previous = 0
                last = 0
            default:
                previous = last
                last = bytes[index]
                index += 1
            }
        }
        guard previous == UInt8(ascii: "X") else { return .strong }
        switch last {
        case UInt8(ascii: "w"): return .weak
        case UInt8(ascii: "o"): return .unowned
        case UInt8(ascii: "u"): return .unownedUnsafe
        default: return .strong
        }
    }

    /// A struct's or an enum's type descriptor: its metadata's second word.
    private static func valueTypeDescriptor(of type: Any.Type) -> UnsafeRawPointer? {
        // A metatype's address is data, which `-deduplicate` never moves; read, not compared.
        // swiftlint:disable:next function_address_identity
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        return metadata.load(fromByteOffset: MemoryLayout<Int>.size, as: UnsafeRawPointer?.self)
    }

    /// A Swift class's type descriptor, after the header described above.
    private static func classDescriptor(of type: Any.Type) -> UnsafeRawPointer? {
        // A metatype's address is data, which `-deduplicate` never moves; read, not compared.
        // swiftlint:disable:next function_address_identity
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        #if _runtime(_ObjC)
            let words = 5
        #else
            let words = 2
        #endif
        return metadata.load(fromByteOffset: words * MemoryLayout<Int>.size + 24, as: UnsafeRawPointer?.self)
    }

    /// `description`, if it describes a type of descriptor kind `kind`.
    private static func described(_ description: UnsafeRawPointer, as kind: UInt32) -> UnsafeRawPointer? {
        description.load(as: UInt32.self) & 0x1F == kind ? description : nil
    }

    /// The records of the type that `description`, a type descriptor,
    /// describes, or `nil` if it has no field descriptor.
    private static func records(described description: UnsafeRawPointer) -> [Record]? {
        // Flags, parent, name and access function come first: 32 bits each.
        guard let fields = relativeTarget(at: description + 16) else { return nil }
        let recordSize = Int(fields.load(fromByteOffset: 10, as: UInt16.self))
        let count = Int(fields.load(fromByteOffset: 12, as: UInt32.self))
        guard recordSize >= 12 else { return nil }
        var records: [Record] = []
        records.reserveCapacity(count)
        for index in 0..<count {
            let record = fields + 16 + index * recordSize
            records.append(
                Record(
                    flags: record.load(as: UInt32.self), mangledTypeName: relativeTarget(at: record + 4),
                    name: relativeTarget(at: record + 8)))
        }
        return records
    }

    /// The address a 32-bit relative pointer at `address` points to, or
    /// `nil` for a null one.
    private static func relativeTarget(at address: UnsafeRawPointer) -> UnsafeRawPointer? {
        let offset = address.load(as: Int32.self)
        return offset == 0 ? nil : address + Int(offset)
    }
}
