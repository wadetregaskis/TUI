//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldDescriptors.swift
//
//  A type's field records, read from the field descriptor the compiler emits
//  for it: what the runtime's reflection entry points (`RuntimeFields`) read
//  them from, for what those entry points do not hand back.
//
//  The layouts read here are part of Swift's stable ABI:
//
//  - A struct's or an enum's metadata: its kind, then its nominal type
//    descriptor (swift/ABI/Metadata.h, `TargetValueMetadata`).
//  - The type descriptor: flags, parent, name and access function, 32 bits
//    each, then a relative pointer to its field descriptor
//    (`TargetTypeContextDescriptor`).
//  - The field descriptor: its mangled type name and superclass, relative
//    pointers; its kind and record size, 16 bits each; its record count, 32
//    bits; then the records. Each record is a flags word, a relative pointer
//    to the field's mangled type name (absent for an enum case without a
//    payload), and one to its name (swift/RemoteInspection/Records.h). An
//    enum's records are its cases, payload cases first in declaration order
//    and then the empty ones: record `i` is the case whose tag is `i`.
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

    /// The records of `type`, a struct or an enum, or `nil` if it has no
    /// field descriptor to read.
    static func records(ofValueType type: Any.Type) -> [Record]? {
        // A metatype's address is data, which `-deduplicate` never moves; read, not compared.
        // swiftlint:disable:next function_address_identity
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        let word = MemoryLayout<Int>.size
        guard let description = metadata.load(fromByteOffset: word, as: UnsafeRawPointer?.self) else { return nil }
        return records(described: description)
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
