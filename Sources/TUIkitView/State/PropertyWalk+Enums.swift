//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PropertyWalk+Enums.swift
//
//  The property walk (`PropertyWalk.swift`) at an enum: its case read, and
//  its payload walked where it lies.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension PropertyWalk {
    /// What the enum at `address` holds: its case's payload, in a scope of
    /// that case's. When the case is not the one last recorded at `scope`,
    /// the state created while that one held is dropped first, so the new
    /// case's `@State` starts at its defaults, and nothing of the old case is
    /// left for it to find when it comes back.
    ///
    /// The payload is walked where it lies — projected out of the enum
    /// through its value witnesses and the case put back after — so what
    /// `update()` changes in it is written back, as SwiftUI writes it back
    /// (measured, decisions-DYNP B-DYNP-1). Not an `indirect` case's: its
    /// payload lies in a box every copy of the enum shares, so it is walked
    /// on a copy, as it is where the witnesses are not called.
    ///
    /// Inside an object's storage the enum is walked on a copy, assigned back
    /// after: while its payload is projected out, the field holds no valid
    /// value — a case kept in its payload's spare bits reads as another — and
    /// an `update()` the payload's walk runs may read the field back through
    /// a reference to the object (a child property's `weak var parent`).
    mutating func applyCase(
        of plan: EnumPlan, at address: UnsafeMutableRawPointer, scope: UInt64, updates: UpdateMode
    ) {
        if objectDepth > 0, plan.cases.witnesses != nil {
            applyCaseOnCopy(of: plan, at: address, as: plan.type, scope: scope, updates: updates)
        } else {
            applyCaseWhereItLies(of: plan, at: address, scope: scope, updates: updates)
        }
    }

    /// ``applyCase(of:at:scope:updates:)`` on a copy of the enum of type
    /// `Enum` at `address`, assigned back to it after.
    private mutating func applyCaseOnCopy<Enum>(
        of plan: EnumPlan, at address: UnsafeMutableRawPointer, as _: Enum.Type, scope: UInt64,
        updates: UpdateMode
    ) {
        let field = address.assumingMemoryBound(to: Enum.self)
        var copy = field.pointee
        applyTypedCase(of: plan, at: &copy, scope: scope, updates: updates)
        field.pointee = copy
    }

    /// ``applyCaseWhereItLies(of:at:scope:updates:)`` on the enum `pointer`
    /// points to, typed so that `&value` reaches it without a closure.
    private mutating func applyTypedCase<Enum>(
        of plan: EnumPlan, at pointer: UnsafeMutablePointer<Enum>, scope: UInt64, updates: UpdateMode
    ) {
        applyCaseWhereItLies(of: plan, at: UnsafeMutableRawPointer(pointer), scope: scope, updates: updates)
    }

    /// ``applyCase(of:at:scope:updates:)`` on the enum where it lies.
    private mutating func applyCaseWhereItLies(
        of plan: EnumPlan, at address: UnsafeMutableRawPointer, scope: UInt64, updates: UpdateMode
    ) {
        guard let witnesses = plan.cases.witnesses, let cases = plan.cases.cases else {
            let (label, payload) = EnumCases.current(at: address, as: plan.type)
            applyCase(label: label, scope: scope) { walk, caseScope in
                guard let payload else { return }
                walk.applyPayload(payload, scope: caseScope, updates: updates)
            }
            return
        }
        let tag = witnesses.tag(at: address)
        let index = Int(tag)
        guard index < cases.count else { return }
        let current = cases[index]
        // A case with no payload is recorded as `""`: what replaces it
        // has nothing of it to drop.
        applyCase(label: current.hasPayload ? current.label : "", scope: scope) { walk, caseScope in
            guard current.hasPayload else { return }
            let payload = plan.cases.payload(tag: tag, at: address, as: plan.type)
            if payload.isNone { return }
            if current.isIndirect {
                let (_, copy) = EnumCases.current(at: address, as: plan.type)
                guard let copy else { return }
                walk.applyPayload(copy, scope: caseScope, updates: updates)
                return
            }
            witnesses.projectPayload(at: address)
            walk.applyPayload(payload, at: address, scope: caseScope, updates: updates)
            witnesses.injectTag(tag, at: address)
        }
    }

    /// The case `label`'s part of ``applyCase(of:at:scope:updates:)``: the
    /// record of the case kept at `scope` checked, `body` walking the payload
    /// in the case's scope, and what it created recorded.
    mutating func applyCase(
        label: String, scope: UInt64, _ body: (inout Self, UInt64) -> Void
    ) {
        let recordKey = StateStorage.StateKey(
            identity: identity, propertyIndex: StateStorage.StateKey.enumCaseIndex, scope: scope)
        let record = storage?.enumCaseRecord(at: recordKey)
        if let record, record.label != label {
            storage?.removeValues(forKeys: record.keys)
            record.keys.removeAll()
            record.label = label
        }
        let caseScope = NestedScope.enumCase(label, in: scope)
        let createdBefore = created.count
        caseDepth += 1
        body(&self, caseScope)
        caseDepth -= 1
        // An enum whose cases have created no state keeps no record.
        guard created.count > createdBefore, let storage else { return }
        if let record {
            record.keys.append(contentsOf: created[createdBefore...])
        } else {
            storage.setEnumCaseRecord(
                EnumCaseRecord(label: label, keys: Array(created[createdBefore...])), at: recordKey)
        }
        // What this case created is this record's alone. An enclosing case's
        // record lists this record instead — once, when it is made — and
        // drops what it lists with it (``StateStorage/removeValues(forKeys:)``).
        created.removeSubrange(createdBefore...)
        if record == nil, caseDepth > 0 { created.append(recordKey) }
    }

    /// A case's payload where it lies, at `address`, `plan` planning it: a
    /// tuple's elements each by its position, as SwiftUI takes each case's
    /// payload as a tuple and keeps the elements that are properties, or the
    /// one value at position 0.
    mutating func applyPayload(
        _ plan: PayloadPlan, at address: UnsafeMutableRawPointer, scope: UInt64, updates: UpdateMode
    ) {
        if let elements = plan.elements {
            applySteps(of: elements, at: address, scope: scope, isOwn: false, updates: updates)
        } else if let single = plan.single {
            apply(single, at: address, position: 0, scope: scope, isOwn: false, updates: updates)
        }
    }

    /// A case's payload, a copy the runtime made: what it holds walked on
    /// that copy, so `update()` changes nothing `body` reads.
    mutating func applyPayload(_ payload: Any, scope: UInt64, updates: UpdateMode) {
        func opened<Payload>(_ payload: Payload) {
            applyPayloadOpened(payload, scope: scope, updates: updates)
        }
        _openExistential(payload, do: opened)
    }

    mutating func applyPayloadOpened<Payload>(_ payload: Payload, scope: UInt64, updates: UpdateMode) {
        var copy = payload
        if RuntimeFields.Kind(of: Payload.self) == .tuple {
            // A case holding more than one value: each walked by its
            // position, as SwiftUI takes each case's payload as a tuple and
            // keeps the elements that are properties.
            let fields = PropertyPlans.payloadPlan(of: Payload.self)
            applyTypedSteps(of: fields, at: &copy, scope: scope, updates: updates)
        } else {
            applyTyped(PropertyPlans.slot(Payload.self), at: &copy, position: 0, scope: scope, isOwn: false, updates: updates)
        }
    }

    mutating func applyTypedSteps<Value>(
        of fields: FieldsPlan, at pointer: UnsafeMutablePointer<Value>, scope: UInt64, updates: UpdateMode
    ) {
        applySteps(of: fields, at: UnsafeMutableRawPointer(pointer), scope: scope, isOwn: false, updates: updates)
    }
}
