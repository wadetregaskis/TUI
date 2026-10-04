//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerAxisEnvironment.swift
//
//  Which way the enclosing stack lays its children out, published so that a
//  child whose appearance depends on it — `Divider`, today — can ask. SwiftUI
//  carries the same information internally, which is how its `Divider`
//  manages to be a horizontal rule in a VStack and a vertical one in an HStack
//  without the caller saying so.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

/// What the stack laying a view out tells the views it lays out: its axis,
/// and — from a lazy stack with `pinnedViews:` — that its sections pin.
///
/// One entry because both are about the stack's OWN children, and the next
/// stack down publishes its own, scope-less: so a section inside a row's
/// `VStack` is not taken for one of the pinned stack's, without a second
/// environment write on every stack's render. Kept within an existential's
/// inline buffer — the stack cores write it on every render, and a value too
/// big for it would be a heap box each time.
struct ContainerRelationship {
    /// The axis the stack lays its children out along.
    var axis: Axis?

    /// The pinned stack whose sections the children may be.
    var pinnedSections: PinnedSectionScope?
}

private struct ContainerAxisKey: EnvironmentKey {
    static let defaultValue = ContainerRelationship()
}

extension EnvironmentValues {
    /// The axis of the stack laying this view out, or `nil` outside one.
    ///
    /// Set by the stack cores on the context they hand their children, and
    /// read by ``Divider`` to choose its orientation. The value is constant
    /// for a given call site — an `HStack` always publishes `.horizontal` —
    /// so writing it directly on a child context cannot leave a memoized
    /// subtree holding a stale one, which is the hazard that makes
    /// `environment(_:_:)` the right tool for values that change.
    ///
    /// Deliberately not public: it describes an implementation relationship
    /// between a container and its children, and SwiftUI does not expose its
    /// equivalent either. A view that wants to know its own axis should be
    /// told by its caller.
    ///
    /// Setting it starts a new container's relationship with its children, so
    /// it clears ``pinnedSectionScope``.
    var containerAxis: Axis? {
        get { self[ContainerAxisKey.self].axis }
        set { self[ContainerAxisKey.self] = ContainerRelationship(axis: newValue) }
    }

    /// The pinned stack whose sections the views below may be — see
    /// ``PinnedSectionScope``. Set by a lazy stack with `pinnedViews:` for its
    /// rows, after it publishes its axis; cleared by the next stack down as it
    /// publishes its own, and by a section for what it draws.
    var pinnedSectionScope: PinnedSectionScope? {
        get { self[ContainerAxisKey.self].pinnedSections }
        set { self[ContainerAxisKey.self].pinnedSections = newValue }
    }
}

extension RenderContext {
    /// This context with ``EnvironmentValues/containerAxis`` set, for a stack
    /// to hand its children.
    ///
    /// Written directly rather than through `environment(_:_:)` because the
    /// value is a property of the call site, not of any state: an `HStack` is
    /// horizontal on every frame it ever renders, so no memoized subtree can
    /// be holding a value that has since changed.
    func publishingContainerAxis(_ axis: Axis) -> Self {
        var copy = self
        copy.environment.containerAxis = axis
        return copy
    }
}

// MARK: - Layouts With an Axis

/// A layout that forwards an axis it cannot state statically: ``AnyLayout``,
/// whose ``Layout/layoutProperties`` — a static property — cannot know the
/// layout it erased. Every other layout states its axis as
/// ``LayoutProperties/stackOrientation``.
///
/// Optional-valued because what `AnyLayout` has erased may well have no axis.
@MainActor
protocol AxisPublishingLayout {
    /// The axis this layout arranges its subviews along, or `nil` for none.
    var containerAxis: Axis? { get }
}
