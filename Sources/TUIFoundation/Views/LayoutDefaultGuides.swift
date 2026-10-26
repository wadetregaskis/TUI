//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutDefaultGuides.swift
//
//  Which layout types answer a guide by `Layout`'s default
//  `explicitAlignment`, learnt from the default as it runs: what lets a stack
//  aligning on an edge skip laying out a layout that cannot give the edge a
//  value of its own.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// The layout types whose `explicitAlignment(of:in:proposal:subviews:cache:)`
/// along each axis has been seen to be `Layout`'s default, kept for the life
/// of the process, as a conformance never changes.
///
/// ``Layout/_definesExplicitAlignment`` is `true` unless a layout says
/// otherwise, because Swift cannot ask whether a conformance implements a
/// requirement itself. So a stack aligning on `.leading` asked every layout of
/// an app's own for the guide, and the layout answered it after a whole pass —
/// its subviews resolved, sized and placed — on every frame, to find the
/// default's answer for an edge: none (`customlayout`: 5.7% of a frame, under
/// a `.border()`, since a guide passes a border).
///
/// This is not a test of whether a type overrides the requirement, which
/// cannot be made; it is a record that the default RAN for the type. A
/// requirement's witness is fixed per conformance, so the default runs for a
/// type only where its conformance implements nothing of its own, and then on
/// every call: once seen, the type answers by the default for good. A type
/// that implements the requirement is never recorded, whatever its own
/// implementation calls — a layout it delegates to is recorded as itself.
/// The horizontal and vertical requirements are two witnesses, so a type is
/// recorded per axis. The first query of a type still makes the pass; every
/// later one reads a set.
///
/// Held through pointers kept as constants, for the reason `PropertyPlans`
/// and `BodyWitnessMemo` keep theirs that way: a static variable is checked
/// for exclusivity on every read and write, where a load through a constant
/// pointer is a plain load.
@MainActor
enum LayoutDefaultGuides {
    /// The types seen answering a horizontal guide by the default.
    private static let horizontal = permanentSet()

    /// The types seen answering a vertical guide by the default.
    private static let vertical = permanentSet()

    private static func permanentSet() -> UnsafeMutablePointer<Set<ObjectIdentifier>> {
        let pointer = UnsafeMutablePointer<Set<ObjectIdentifier>>.allocate(capacity: 1)
        pointer.initialize(to: [])
        return pointer
    }

    /// Records that `type` answered a guide along `axis` by the default —
    /// called by the default itself, and by nothing else.
    static func noteDefault(_ type: Any.Type, along axis: Axis) {
        let set = axis == .horizontal ? horizontal : vertical
        let key = ObjectIdentifier(type)
        if !set.pointee.contains(key) { set.pointee.insert(key) }
    }

    /// Whether `type` has been seen answering a guide along `axis` by the
    /// default, which gives an edge or the centre no value and a custom guide
    /// or a baseline only its subviews' (``Layout/explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``).
    static func answersByDefault(_ type: Any.Type, along axis: Axis) -> Bool {
        (axis == .horizontal ? horizontal : vertical).pointee.contains(ObjectIdentifier(type))
    }
}

extension Layout {
    /// Whether this layout may give a guide along `axis` a value its
    /// subviews did not: ``Layout/_definesExplicitAlignment``, read past an
    /// erasing layout to what it erased (``ExplicitAlignmentForwarding``),
    /// and `false` for a type seen answering along `axis` by the default
    /// (``LayoutDefaultGuides``).
    func definesExplicitAlignment(along axis: Axis) -> Bool {
        if let forwarding = self as? any ExplicitAlignmentForwarding {
            return forwarding.definesExplicitAlignment(along: axis)
        }
        return Self._definesExplicitAlignment && !LayoutDefaultGuides.answersByDefault(type(of: self), along: axis)
    }
}

extension AlignmentGuideQuery {
    /// The axis the guide asked about lies along: a horizontal alignment's
    /// guide is a position across the width.
    var axis: Axis {
        switch self {
        case .horizontal: .horizontal
        case .vertical: .vertical
        }
    }
}
