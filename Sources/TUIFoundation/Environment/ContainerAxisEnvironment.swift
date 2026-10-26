//  🖥️ TUI — A Terminal UI framework for Swift
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

import TUIView

/// What the stack laying a view out tells the views it lays out: its axis,
/// and — from a lazy stack with `pinnedViews:` — that its sections pin.
///
/// One entry because both are about the stack's OWN children, and the next
/// stack down publishes its own, scope-less: so a section inside a row's
/// `VStack` is not taken for one of the pinned stack's, without a second
/// environment write on every stack's render. Kept within an existential's
/// inline buffer — the stack cores write it on every render, and a value too
/// big for it would be a heap box each time.
struct ContainerRelationship: Equatable {
    /// The axis the stack lays its children out along.
    var axis: Axis?

    /// The pinned stack whose sections the children may be.
    var pinnedSections: PinnedSectionScope?

    /// Whether the view laying these out offered them no width — see
    /// ``EnvironmentValues/offeredNoWidth``.
    var offersNoWidth = false
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

    /// Whether the view laying this one out offered it no width — SwiftUI's
    /// unspecified proposal, which a frame with an ideal width answers with
    /// that ideal (`FlexibleFrameView.isOfferedNoWidth(in:)`).
    ///
    /// Set by `.fixedSize()` for its content. Passed on as SwiftUI passes an
    /// unspecified width on, measured (`Tools/SwiftUIProbes/Flexible
    /// frames/ideal-placed.out`): by a modifier, which lays its content out
    /// where it is itself (`.padding`, `.border`, a background's base), by a
    /// row, which lays its views along the width it was not offered, and by a
    /// stack or a layout of statically one view; cleared by what offers its
    /// views a width as it places them — a column of several, a `ZStack`
    /// of several, a `Grid`, a layout with no axis, an overlay's or a
    /// background's layer — and by the frame that reads it, which offers its
    /// content its ideal. One entry with the container's axis, which every
    /// stack writes anyway, so a column clears it at no cost.
    var offeredNoWidth: Bool {
        get { self[ContainerAxisKey.self].offersNoWidth }
        set { self[ContainerAxisKey.self].offersNoWidth = newValue }
    }

    /// The whole relationship, read or written as one entry.
    fileprivate var containerRelationship: ContainerRelationship {
        get { self[ContainerAxisKey.self] }
        set { self[ContainerAxisKey.self] = newValue }
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
    ///
    /// A new container's walk takes its sections apart, whatever the walk that
    /// drew it kept whole (`RenderContext.keepsSectionsWhole`): a stack in a
    /// pinned stack's row lays out its own sections' parts.
    ///
    /// The stack offers its views a width — ``EnvironmentValues/offeredNoWidth``
    /// cleared with the rest of the relationship — unless `passesNoWidthOn`
    /// and it was offered none itself: a row, which lays its views along the
    /// width, and a stack of statically one view pass the unspecified width
    /// on, as SwiftUI's do.
    ///
    /// Written only where it differs from the relationship in force: a write
    /// copies the whole environment, which the context shares with the one
    /// it came from, and a column inside a column, or inside a bordered box
    /// that stacks its body, publishes the very relationship it was given —
    /// `deep` spent 1.0% of its frame copying environments here, its every
    /// level a bordered column. The one read it costs is the read a row made
    /// anyway, for the width it may pass on.
    package func publishingContainerAxis(_ axis: Axis, passesNoWidthOn: Bool = false) -> Self {
        var copy = self
        let inForce = environment.containerRelationship
        let published = ContainerRelationship(axis: axis, offersNoWidth: passesNoWidthOn && inForce.offersNoWidth)
        if published != inForce { copy.environment.containerRelationship = published }
        copy.sectionWholeness = .apart
        return copy
    }

    /// This context with ``EnvironmentValues/offeredNoWidth`` cleared — for a
    /// container that publishes no axis and offers its views a width as it
    /// places them (a `ZStack` of several layers, a layout with no axis, an
    /// overlay's layer) — unless `passesNoWidthOn`.
    package func offeringAWidth(unless passesNoWidthOn: Bool = false) -> Self {
        guard !passesNoWidthOn, environment.offeredNoWidth else { return self }
        var copy = self
        copy.environment.offeredNoWidth = false
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
