//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnumPayloads.swift
//
//  An enum's current case and its payload, reached in place: the case read
//  and the payload projected out and put back through the enum's value
//  witnesses, so the property walk can write what `update()` changed into the
//  payload, as SwiftUI does (decisions-DYNP B-DYNP-1).
//
//  Two runtime layouts are read here, both part of Swift's stable ABI:
//
//  - The value witness table, a pointer stored one word before a type's
//    metadata. An enum's table extends the common one with three functions
//    after its eight functions, two sizes and two 32-bit fields:
//    `getEnumTag`, `destructiveProjectEnumData` and
//    `destructiveInjectEnumTag` (swift/ABI/ValueWitness.def). Each takes the
//    value's address and the metadata, and the tag where it writes one.
//  - The enum's field descriptor (`FieldDescriptors`): one record per case,
//    by tag, each with a flags word (bit 0: the case is `indirect`), its
//    payload's mangled type (absent for an empty case), and its name.
//
//  The value witnesses are `swiftcc` functions, called here through a C
//  function type. Measured on macOS arm64 only (session notes
//  `DYNVFIX/probe/vwt.swift`, for a native enum, a generic one instantiated
//  at run time and the standard library's `Optional`). On Linux, arm64 and
//  x86_64, it is reasoned, not measured: for two pointers and a 32-bit
//  integer `swiftcc` passes the arguments in the C argument registers and
//  returns in the C return register, and a witness takes no `self`, error or
//  async context, the only parameters it gives registers of their own. On
//  WebAssembly an indirect call checks the callee's signature, which a
//  `swiftcc` one does not match, and on Windows it was not measured: there
//  the walk falls back to a copy of the payload the runtime makes, and what
//  `update()` changes there is not written back. An `arm64e` build, which
//  TUIkit does not make, would have to authenticate the table's signed
//  function pointers before calling them.
//
//  Created by Wade Tregaskis
//  License: MIT

/// An enum type's case witnesses and its cases, as the property walk needs
/// them.
@MainActor
final class EnumCasesPlan {
    /// One of the enum's cases.
    struct Case {
        /// The case's name.
        let label: String
        /// Whether its payload lives in a box that every copy of the enum
        /// shares (`indirect`).
        let isIndirect: Bool
        /// Whether it has a payload.
        let hasPayload: Bool
    }

    /// The enum's value witnesses, or `nil` where they are not called (see
    /// the file's header).
    let witnesses: EnumWitnesses?
    /// The cases, by tag, or `nil` when the enum's field descriptor could not
    /// be read.
    let cases: [Case]?
    /// What each payload case's payload is planned as, by tag: learned on
    /// the first value seen holding that case, since the payload's type is
    /// given as a mangled name the runtime resolves only through an entry
    /// point the compiler reserves to itself.
    private var payloads: [PayloadPlan?] = []

    init(_ type: Any.Type) {
        witnesses = EnumWitnesses(type)
        cases = enumCases(of: type)
    }

    /// The plan for the payload of the case with `tag`, in the enum at
    /// `address`, of type `Enum`, that holds it.
    func payload<Enum>(tag: UInt32, at address: UnsafeMutableRawPointer, as _: Enum.Type) -> PayloadPlan {
        let index = Int(tag)
        if index < payloads.count, let known = payloads[index] { return known }
        let plan = PayloadPlan(declaredType: EnumCases.payloadType(at: address, as: Enum.self))
        while payloads.count <= index { payloads.append(nil) }
        payloads[index] = plan
        return plan
    }
}

/// What the walk does with one case's payload: a tuple's elements each by
/// its position, or the payload as one value at position 0.
@MainActor
struct PayloadPlan {
    /// The payload's declared type.
    let declaredType: Any.Type?
    /// The elements of a tuple payload, or `nil`.
    let elements: FieldsPlan?
    /// The payload as one value, when it is not a tuple.
    let single: SlotPlan?

    init(declaredType: Any.Type?) {
        self.declaredType = declaredType
        guard let declaredType else {
            elements = nil
            single = nil
            return
        }
        if RuntimeFields.Kind(of: declaredType) == .tuple {
            elements = PropertyPlans.payloadPlan(of: declaredType)
            single = nil
        } else {
            elements = nil
            single = PropertyPlans.slot(declaredType)
        }
    }

    /// Whether the walk does nothing with this payload.
    var isNone: Bool {
        if let elements { return elements.steps.isEmpty }
        return single?.isNone ?? true
    }
}

/// An enum type's value witnesses for its case: read, project, inject.
struct EnumWitnesses {
    private typealias GetTag = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UInt32
    private typealias Project = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Void
    private typealias Inject = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void

    private let metadata: UnsafeRawPointer
    private let getTag: GetTag
    private let project: Project
    private let inject: Inject

    /// `type`'s witnesses, or `nil` on a platform where they are not called.
    init?(_ type: Any.Type) {
        #if arch(wasm32) || os(Windows)
            return nil
        #else
            // A metatype's address is data, which `-deduplicate` never moves; read, not compared.
            // swiftlint:disable:next function_address_identity
            metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
            let word = MemoryLayout<Int>.size
            let table = metadata.load(fromByteOffset: -word, as: UnsafeRawPointer.self)
            // Eight functions, `size` and `stride`, then `flags` and
            // `extraInhabitantCount`, two 32-bit fields: the enum's three
            // follow.
            let first = 10 * word + 8
            getTag = unsafeBitCast(table.load(fromByteOffset: first, as: UnsafeRawPointer.self), to: GetTag.self)
            project = unsafeBitCast(
                table.load(fromByteOffset: first + word, as: UnsafeRawPointer.self), to: Project.self)
            inject = unsafeBitCast(
                table.load(fromByteOffset: first + 2 * word, as: UnsafeRawPointer.self), to: Inject.self)
        #endif
    }

    /// The tag of the case the enum at `address` holds.
    func tag(at address: UnsafeRawPointer) -> UInt32 {
        getTag(address, metadata)
    }

    /// Leaves the enum at `address` holding only its payload, at its start:
    /// the case's bits the payload shares are cleared until
    /// ``injectTag(_:at:)`` puts them back.
    func projectPayload(at address: UnsafeMutableRawPointer) {
        project(address, metadata)
    }

    /// Puts the case `tag` back into the enum at `address`, whose payload
    /// ``projectPayload(at:)`` projected.
    func injectTag(_ tag: UInt32, at address: UnsafeMutableRawPointer) {
        inject(address, tag, metadata)
    }
}

/// `type`'s cases, by tag, from its field descriptor — or `nil` if it has
/// none to read.
private func enumCases(of type: Any.Type) -> [EnumCasesPlan.Case]? {
    guard let records = FieldDescriptors.records(ofValueType: type) else { return nil }
    var cases: [EnumCasesPlan.Case] = []
    cases.reserveCapacity(records.count)
    for record in records {
        let name = record.name.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) }
        cases.append(
            EnumCasesPlan.Case(
                label: name ?? "", isIndirect: record.flags & 1 != 0, hasPayload: record.mangledTypeName != nil))
    }
    return cases
}

/// An enum's current case, as the runtime's reflection reads it: never
/// through a `customMirror`.
enum EnumCases {
    /// The name of the case of the enum at `address` — `""` for a case with
    /// no payload — and a copy of its payload.
    static func current<Enum>(at address: UnsafeMutableRawPointer, as _: Enum.Type) -> (label: String, payload: Any?) {
        let value = address.assumingMemoryBound(to: Enum.self).pointee
        guard RuntimeChildren.count(of: value, as: Enum.self) > 0 else { return ("", nil) }
        let child = RuntimeChildren.child(of: value, as: Enum.self, at: 0)
        return (child.name ?? "", child.value)
    }

    /// The declared type of the payload of the case the enum at `address`
    /// holds, or `nil` for a case without one. The runtime hands the payload
    /// back as an `Any` whose type is the case's declared one — an
    /// existential stays one — which opening it names.
    static func payloadType<Enum>(at address: UnsafeMutableRawPointer, as _: Enum.Type) -> Any.Type? {
        let value = address.assumingMemoryBound(to: Enum.self).pointee
        guard RuntimeChildren.count(of: value, as: Enum.self) > 0 else { return nil }
        return _openExistential(RuntimeChildren.child(of: value, as: Enum.self, at: 0).value, do: storedType)
    }
}

/// `Stored`, the type an opened existential held.
private func storedType<Stored>(_: Stored) -> Any.Type {
    Stored.self
}
