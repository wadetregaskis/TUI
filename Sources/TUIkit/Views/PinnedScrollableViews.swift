//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PinnedScrollableViews.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Pinned Scrollable Views

/// A set of view types that may be pinned to the bounds of a scroll view.
///
/// Mirrors SwiftUI's `PinnedScrollableViews`, and is handed to a lazy stack's
/// `pinnedViews:` the same way:
///
/// ```swift
/// ScrollView {
///     LazyVStack(alignment: .leading, pinnedViews: .sectionHeaders) {
///         ForEach(groups) { group in
///             Section(group.name) {
///                 ForEach(group.items) { Text($0.title) }
///             }
///         }
///     }
/// }
/// ```
///
/// Inside a vertical ``ScrollView`` a pinned `Section` header stays at the
/// viewport's top while any of its section's content is under it, and the
/// section's last row pushes it up and away — so the next section's header
/// takes over; a pinned footer stays at the bottom the same way. A row's
/// sections — ``LazyHStack/init(alignment:spacing:pinnedViews:content:)``'s and
/// ``LazyHGrid/init(rows:alignment:spacing:pinnedViews:content:)``'s — pin the
/// same way to a horizontal scroll view's leading and trailing edges. Outside
/// a scroll view, or for a view that is not a `Section`, pinning changes
/// nothing. See ``LazyVStack/init(alignment:spacing:pinnedViews:content:)``
/// and ``LazyVGrid/init(columns:alignment:spacing:pinnedViews:content:)``,
/// whose headers span the columns.
public struct PinnedScrollableViews: OptionSet, Sendable {
    /// The corresponding value of the raw type.
    public let rawValue: UInt32

    /// Creates a new option set from the given raw value.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The header view of each `Section` will be pinned.
    public static let sectionHeaders = Self(rawValue: 1 << 0)

    /// The footer view of each `Section` will be pinned.
    public static let sectionFooters = Self(rawValue: 1 << 1)
}

// MARK: - The Scope a Pinned Stack Hands Its Sections

/// What a lazy stack with `pinnedViews:` tells the sections it holds: which of
/// their parts to pin, and where the stack is.
///
/// Only the stack's OWN sections pin, as in SwiftUI (measured on macOS 15.8):
/// a section written in the stack's content or made there by a `ForEach`,
/// whatever views and modifiers wrap it. A section inside one of the stack's
/// rows — in a `VStack` there, say — is part of that row and scrolls with it.
/// Two things tell them apart. The scope travels in the stack's relationship
/// with its children (``ContainerRelationship``), which the next stack down
/// replaces with its own. And the stack's own sections are one sibling step
/// below it (``ViewIdentity/siblingSteps(belowDepth:)``), where a section in a
/// row among other views — in a `ZStack`, which publishes nothing — is two.
///
/// Small on purpose: it rides in the entry every stack core writes on every
/// render, which must fit an existential's inline buffer.
struct PinnedSectionScope: Equatable {
    /// The identity depth of the stack's core, whose children the sections are.
    var stackDepth: Int32

    /// Whether the sections' headers are pinned.
    var pinsHeaders: Bool

    /// Whether the sections' footers are pinned.
    var pinsFooters: Bool

    /// Whether a section at `identity` is one of the stack's own.
    func owns(sectionAt identity: ViewIdentity) -> Bool {
        identity.siblingSteps(belowDepth: Int(stackDepth)) == 1
    }

    /// What a section at `identity` pins — nothing unless it is one of the
    /// stack's own.
    func pins(at identity: ViewIdentity) -> (headers: Bool, footers: Bool) {
        guard owns(sectionAt: identity) else { return (false, false) }
        return (pinsHeaders, pinsFooters)
    }
}

// MARK: - How the Stack Lays Out Its Own Sections

/// How a pinned lazy stack lays out its children, for the sections it keeps
/// whole.
///
/// Everywhere else a `Section` is its header's, content's and footer's views,
/// the container's own children (decisions B16). A pinned stack keeps its own
/// sections whole (``ChildViewProvider/staysWhole(in:)``) because pinning is
/// done BY the section — it knows where its header, content and footer are,
/// which a flattened row cannot say — and the section lays its views out as the
/// stack would have: along the stack's axis, `spacing` apart, each aligned
/// across by the stack's alignment. So `LazyVStack(spacing: 1, pinnedViews:
/// .sectionHeaders)` spaces a header from its first row as SwiftUI's does
/// (measured on macOS 15.8).
///
/// A value of its own beside ``PinnedSectionScope`` rather than inside it: the
/// scope rides in the entry every stack core writes on every render, which
/// must stay within an existential's inline buffer, and an alignment would not
/// fit. Written only by a stack that pins, and read only by a section the scope
/// says is the stack's own.
struct PinnedSectionLayout: Equatable {
    /// The stack's axis: a column's sections lay out downward, a row's along it.
    var axis: Axis

    /// The stack's spacing between its children.
    var spacing: Int

    /// The stack's alignment: its horizontal half for a column, its vertical
    /// half for a row.
    var alignment: Alignment
}

private struct PinnedSectionLayoutKey: EnvironmentKey {
    static let defaultValue: PinnedSectionLayout? = nil
}

extension EnvironmentValues {
    /// How the pinned stack whose sections the views below may be lays out
    /// its children — see ``PinnedSectionLayout``.
    var pinnedSectionLayout: PinnedSectionLayout? {
        get { self[PinnedSectionLayoutKey.self] }
        set { self[PinnedSectionLayoutKey.self] = newValue }
    }
}

// MARK: - Whether a Section Stays Whole

/// Whether a `Section` resolved in `context` is handed to its container whole
/// (``ChildViewProvider/staysWhole(in:)``): in a walk that keeps sections whole
/// — a `List`'s, the section APIs' — and as one of a pinned lazy stack's own
/// sections, which pins its header and footer itself.
@MainActor
func sectionStaysWhole(in context: RenderContext) -> Bool {
    if context.keepsSectionsWhole { return true }
    guard let scope = context.environment.pinnedSectionScope else { return false }
    return scope.owns(sectionAt: context.identity)
}

// MARK: - The Stack That Hands It Out

/// A stack core that can pin its sections' headers and footers: a lazy
/// stack's, in a column (`LazyVStack`, a `LazyVGrid`'s sections) or along a
/// row (`LazyHStack`, a `LazyHGrid`'s).
@MainActor
protocol PinningStackCore {
    /// Whether the stack pins its sections' headers.
    var pinsSectionHeaders: Bool { get }

    /// Whether the stack pins its sections' footers.
    var pinsSectionFooters: Bool { get }

    /// How the stack lays out its children, for the sections it keeps whole.
    var pinnedSectionLayout: PinnedSectionLayout { get }
}

extension PinningStackCore {
    /// `context` with this stack's pinned-section scope for its rows, when it
    /// pins (``PinnedSectionScope``) — the one place every render path takes
    /// its rows' context from.
    ///
    /// The scope changes what a section row draws, and a memoized row is
    /// served by its view value, which the scope is not part of: so a change
    /// of it — `pinnedViews:` toggled — drops what was kept below this stack,
    /// as an `.environment(_:_:)` modifier's change does, through the same
    /// once-a-pass record.
    func scopingPinnedSections(_ context: RenderContext) -> RenderContext {
        let scope = pinnedSectionScope(context)
        let layout = scope.map { _ in pinnedSectionLayout }
        if let cache = context.renderCache {
            let scopeChanged =
                cache.noteAppliedEnvironment(
                    scope as Any, identity: context.identity,
                    keyPath: \EnvironmentValues.pinnedSectionScope,
                    depth: context.environmentApplicationDepth) == .changed
            // The layout too, while the stack pins: a section it keeps whole
            // draws with its spacing and alignment, which a memoized buffer
            // does not key on either. Not while it does not — pinning switched
            // on again is a change of scope, which clears what was kept — so a
            // stack that pins nothing pays the one note it always did.
            let layoutChanged =
                layout != nil
                && cache.noteAppliedEnvironment(
                    layout as Any, identity: context.identity,
                    keyPath: \EnvironmentValues.pinnedSectionLayout,
                    depth: context.environmentApplicationDepth) == .changed
            if scopeChanged || layoutChanged { cache.clearAffected(by: context.identity) }
        }
        guard let scope else { return context }
        var scoped = context
        scoped.environment.pinnedSectionScope = scope
        scoped.environment.pinnedSectionLayout = layout
        return scoped
    }

    /// `context` with this stack's pinned-section scope and layout, when it
    /// pins, for a walk that only asks — a measure, a placement query — and so
    /// notes nothing: whether a section stays whole is decided where its
    /// children are resolved (``sectionStaysWhole(in:)``), and every walk of a
    /// pinned stack must decide it the same way.
    func withPinnedSectionScope(_ context: RenderContext) -> RenderContext {
        guard let scope = pinnedSectionScope(context) else { return context }
        var scoped = context
        scoped.environment.pinnedSectionScope = scope
        scoped.environment.pinnedSectionLayout = pinnedSectionLayout
        return scoped
    }

    /// The scope this stack hands its rows in `context`, or `nil` when it pins
    /// nothing.
    private func pinnedSectionScope(_ context: RenderContext) -> PinnedSectionScope? {
        guard pinsSectionHeaders || pinsSectionFooters else { return nil }
        return PinnedSectionScope(
            stackDepth: Int32(clamping: context.identity.depth),
            pinsHeaders: pinsSectionHeaders, pinsFooters: pinsSectionFooters)
    }
}

extension _VStackCore: PinningStackCore {
    /// A column: its sections lay out downward, aligned across by its
    /// alignment.
    var pinnedSectionLayout: PinnedSectionLayout {
        PinnedSectionLayout(
            axis: .vertical, spacing: spacing,
            alignment: Alignment(horizontal: alignment, vertical: .top))
    }
}

extension _HStackCore: PinningStackCore {
    /// A row: its sections lay out along it, aligned up and down by its
    /// alignment.
    var pinnedSectionLayout: PinnedSectionLayout {
        PinnedSectionLayout(
            axis: .horizontal, spacing: spacing,
            alignment: Alignment(horizontal: .leading, vertical: alignment))
    }
}
