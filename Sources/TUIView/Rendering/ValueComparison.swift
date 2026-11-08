//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueComparison.swift
//
//  How two values of one type compare, field by field, made once from the type
//  by the walk that makes its value-hash plan (`ValueHashPlanBuilder`), so what
//  that walk refuses, this refuses: bitfields, stripped metadata, a metatype
//  that may lie in no bytes at all.
//
//  A hash says a value's BYTES are the same, and a view built afresh from equal
//  data has new addresses in its bytes: an array's, a closure's, a `@State`'s
//  box. So a hash of one misses where nothing changed. This is not a hash, so it
//  can ask what each field means instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

/// A field the walk binds from its view's identity or environment, so its bytes
/// say nothing: a new box per construction, the same state behind each. A
/// comparison skips it; what it binds has its own invalidation.
package protocol _BoundFromTheWalk {}
extension State: _BoundFromTheWalk {}
extension Environment: _BoundFromTheWalk {}

/// A field that says nothing to compare but that it may read something else: a
/// `Binding`, whose closures are new each time it is made. See ``ValueComparison``.
package protocol _ComparedOpaquely {}
extension Binding: _ComparedOpaquely {}

/// A type a comparison reads through typed Swift: an optional's case, a
/// conditional's branch. Nothing else tells them apart without reading bytes a
/// value may leave undefined (see ``_ValueHashing``, its twin for a hash).
package protocol _ValueComparing {
    /// The types this holds, which a type holding it can compare only if these
    /// can be.
    static var comparedPayloads: [Any.Type] { get }

    /// Whether the values at `lhs` and `rhs` compare equal.
    ///
    /// Nonisolated, as everything that runs a plan is (see
    /// ``ValueHashPlans``): a conformance on a view declares its witness
    /// `nonisolated`.
    static func valuesEqual(
        _ lhs: UnsafeRawPointer, _ rhs: UnsafeRawPointer, strict: Bool, plans: ValueHashPlans
    ) -> Bool
}

/// How two values of one type compare: ``ValueHashPlans/comparison(for:)``.
///
/// A field goes by the first of these that applies, the walk's rules
/// (``ValueHashPlanBuilder``) deciding where it does not say otherwise:
///
/// - bound from the walk (`@State`, `@Environment`, ``_BoundFromTheWalk``):
///   skipped;
/// - another `DynamicProperty`: no comparison, since what it reads is unknown;
/// - a function, or what reads its source (a `Binding`): opaque, which `strict`
///   counts as changed and otherwise is ignored. TUI cannot see a closure's
///   captures, and its bytes differ every time it is made;
/// - ``_ValueComparing``: read through typed Swift;
/// - `Equatable`: its own `==`;
/// - a struct or tuple: its fields; a class: by identity; a one-byte enum or an
///   existential metatype: its bytes;
/// - anything else (an existential, a payload enum that is not `Equatable`): no
///   comparison, and so none for a type holding one.
package final class ValueComparison {
    /// One field a comparison does not read as bytes.
    enum Field {
        case opaque
        /// An `Equatable` type, compared by its own `==` (``equal(_:_:_:)``).
        case equatable(any Equatable.Type)
        case typed(any _ValueComparing.Type)
    }

    private struct Run {
        let offset: Int
        let count: Int
    }

    private struct Step {
        let offset: Int
        let field: Field
    }

    /// The bytes compared whole: only what the walk says every value defines.
    private let runs: [Run]
    private let steps: [Step]

    /// Whether a value holds a closure or a `Binding` directly, not behind an
    /// optional: what makes a `strict` comparison unequal without a look.
    package let holdsOpaque: Bool

    init(_ items: [ValueHashPlanBuilder.Item]) {
        var runs: [Run] = []
        var steps: [Step] = []
        var holdsOpaque = false
        for unsafe item in unsafe items {
            switch unsafe item {
            case .bytes(let offset, let count, _) where count > 0:
                if let last = runs.last, last.offset + last.count == offset {
                    runs[runs.count - 1] = Run(offset: last.offset, count: last.count + count)
                } else {
                    runs.append(Run(offset: offset, count: count))
                }
            case .compared(_, .opaque):
                holdsOpaque = true
            case .compared(let offset, let field):
                steps.append(Step(offset: offset, field: field))
            case .bytes, .step:
                break
            }
        }
        self.runs = runs
        self.steps = steps
        self.holdsOpaque = holdsOpaque
    }

    /// The `==` of `E`, over addresses: an `any Equatable.Type` opens into `E`
    /// at the call, so a field keeps its type rather than a closure over two
    /// addresses, which would be of an unsafe type (strict memory safety). The
    /// closure ran this same generic code, unspecialized, so nothing is lost.
    private static func equal<E: Equatable>(_: E.Type, _ lhs: UnsafeRawPointer, _ rhs: UnsafeRawPointer) -> Bool {
        unsafe lhs.assumingMemoryBound(to: E.self).pointee == rhs.assumingMemoryBound(to: E.self).pointee
    }

    /// Whether the values at `lhs` and `rhs` compare equal: a closure or a
    /// `Binding` is ignored, or under `strict` is changed.
    func equal(_ lhs: UnsafeRawPointer, _ rhs: UnsafeRawPointer, strict: Bool, plans: ValueHashPlans) -> Bool {
        if strict, holdsOpaque { return false }
        for run in runs where unsafe memcmp(lhs + run.offset, rhs + run.offset, run.count) != 0 { return false }
        for step in steps {
            switch step.field {
            case .opaque:
                break
            case .equatable(let type):
                if unsafe !Self.equal(type, lhs + step.offset, rhs + step.offset) { return false }
            case .typed(let type):
                if unsafe !type.valuesEqual(lhs + step.offset, rhs + step.offset, strict: strict, plans: plans) { return false }
            }
        }
        return true
    }

    /// ``equal(_:_:strict:plans:)`` of two values held by value.
    func equal<T>(_ lhs: T, _ rhs: T, strict: Bool, plans: ValueHashPlans) -> Bool {
        withUnsafePointer(to: lhs) { left in
            withUnsafePointer(to: rhs) { right in
                unsafe equal(UnsafeRawPointer(left), UnsafeRawPointer(right), strict: strict, plans: plans)
            }
        }
    }
}

extension Optional: _ValueComparing {
    package static var comparedPayloads: [Any.Type] { [Wrapped.self] }

    /// The case by `== nil`, never from the bytes (see `_mixValueHash`); a
    /// `.some` holds its payload at the optional's own address.
    package static func valuesEqual(
        _ lhs: UnsafeRawPointer, _ rhs: UnsafeRawPointer, strict: Bool, plans: ValueHashPlans
    ) -> Bool {
        let leftIsNone = unsafe isNone(lhs.assumingMemoryBound(to: Self.self).pointee)
        let rightIsNone = unsafe isNone(rhs.assumingMemoryBound(to: Self.self).pointee)
        if leftIsNone || rightIsNone { return leftIsNone == rightIsNone }
        return unsafe plans.comparison(for: Wrapped.self)?.equal(lhs, rhs, strict: strict, plans: plans) ?? false
    }
}

extension ConditionalView: _ValueComparing {
    package nonisolated static var comparedPayloads: [Any.Type] { [TrueContent.self, FalseContent.self] }

    /// The same branch, and that branch's content equal.
    package nonisolated static func valuesEqual(
        _ lhs: UnsafeRawPointer, _ rhs: UnsafeRawPointer, strict: Bool, plans: ValueHashPlans
    ) -> Bool {
        func same<T>(_ left: T, _ right: T) -> Bool {
            plans.comparison(for: T.self)?.equal(left, right, strict: strict, plans: plans) ?? false
        }
        switch unsafe (lhs.assumingMemoryBound(to: Self.self).pointee, rhs.assumingMemoryBound(to: Self.self).pointee) {
        case (.trueContent(let left), .trueContent(let right)): return same(left, right)
        case (.falseContent(let left), .falseContent(let right)): return same(left, right)
        default: return false
        }
    }
}
