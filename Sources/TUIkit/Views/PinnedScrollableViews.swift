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
/// takes over; a pinned footer stays at the bottom the same way. Outside a
/// scroll view, or for a view that is not a `Section`, pinning changes
/// nothing. See ``LazyVStack/init(alignment:spacing:pinnedViews:content:)``.
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

    /// What a section at `identity` pins — nothing unless it is one of the
    /// stack's own.
    func pins(at identity: ViewIdentity) -> (headers: Bool, footers: Bool) {
        guard identity.siblingSteps(belowDepth: Int(stackDepth)) == 1 else { return (false, false) }
        return (pinsHeaders, pinsFooters)
    }
}

// MARK: - The Stack That Hands It Out

extension _VStackCore {
    /// `context` with this stack's pinned-section scope for its rows, when it
    /// pins (``PinnedSectionScope``) — the one place every windowed render
    /// path takes its rows' context from.
    ///
    /// The scope changes what a section row draws, and a memoized row is
    /// served by its view value, which the scope is not part of: so a change
    /// of it — `pinnedViews:` toggled — drops what was kept below this stack,
    /// as an `.environment(_:_:)` modifier's change does, through the same
    /// once-a-pass record.
    func scopingPinnedSections(_ context: RenderContext) -> RenderContext {
        let scope =
            pinsSectionHeaders || pinsSectionFooters
            ? PinnedSectionScope(
                stackDepth: Int32(clamping: context.identity.depth),
                pinsHeaders: pinsSectionHeaders, pinsFooters: pinsSectionFooters)
            : nil
        if let cache = context.renderCache,
            cache.noteAppliedEnvironment(
                scope as Any, identity: context.identity,
                keyPath: \EnvironmentValues.pinnedSectionScope,
                depth: context.environmentApplicationDepth) == .changed
        {
            cache.clearAffected(by: context.identity)
        }
        guard let scope else { return context }
        var scoped = context
        scoped.environment.pinnedSectionScope = scope
        return scoped
    }
}
