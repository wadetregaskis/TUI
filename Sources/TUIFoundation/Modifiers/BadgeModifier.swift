//  🖥️ TUI — A Terminal UI framework for Swift
//  BadgeModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that displays a decorative badge on a view.
///
/// Badges are typically used with List rows to show counts, status,
/// or other labels. The badge is rendered right-aligned and styled
/// with a dimmed foreground color.
///
/// The badge value is stored in the environment and propagates to
/// child views. Badges automatically hide when:
/// - The count is 0 (for integer badges)
/// - The label is nil (for optional Text/String badges)
nonisolated package struct BadgeModifier<Content: View>: View {
    /// The content to apply the badge to.
    let content: Content

    /// The badge value (Int, Text, or String).
    let value: BadgeValue

    @MainActor public var body: Never {
        fatalError("BadgeModifier renders via Renderable")
    }
}

// MARK: - Badge Value

/// Represents a badge value that can be Int or String.
public enum BadgeValue: Sendable {
    /// An integer badge (0 hides the badge).
    case int(Int)

    /// A String badge (nil hides the badge).
    case string(String?)

    /// Returns true if the badge should be hidden.
    public var isHidden: Bool {
        switch self {
        case .int(let intValue):
            return intValue == 0
        case .string(let string):
            return string == nil || string?.isEmpty == true
        }
    }

    /// Returns the display text for the badge.
    public var displayText: String {
        switch self {
        case .int(let intValue):
            return "\(intValue)"
        case .string(let string):
            return string ?? ""
        }
    }
}

// MARK: - Equatable

extension BadgeModifier: Equatable where Content: Equatable {
    package static func == (lhs: BadgeModifier<Content>, rhs: BadgeModifier<Content>) -> Bool {
        lhs.content == rhs.content && lhs.value == rhs.value
    }
}

extension BadgeValue: Equatable {
    public static func == (lhs: BadgeValue, rhs: BadgeValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let lhsValue), .int(let rhsValue)):
            return lhsValue == rhsValue
        case (.string(let lhsString), .string(let rhsString)):
            return lhsString == rhsString
        default:
            return false
        }
    }
}

// MARK: - Badge Extraction

/// Type-erased peek at a ``BadgeModifier``'s value. A protocol conformance
/// check is a cached runtime lookup; the `Mirror` walk it replaces ran on
/// EVERY row of every `List` frame and profiled at 8% of a plain list render
/// (session-list-after.trace, 2026-07-31) — almost all of it for rows with no
/// badge at all.
@MainActor
private protocol BadgeCarrying {
    var carriedBadgeValue: BadgeValue { get }
    /// The `\.badgeProminence` written around the badge, the write nearest it
    /// winning — `nil` where none is.
    var carriedBadgeProminence: BadgeProminence? { get }
}

@MainActor extension BadgeModifier: BadgeCarrying {
    fileprivate var carriedBadgeValue: BadgeValue { value }
    fileprivate var carriedBadgeProminence: BadgeProminence? { nil }
}

/// A row whose badge has an environment write around it is still a badged
/// row, and a `.badgeProminence(_:)` written there is that badge's: the badge
/// sees the environment where `.badge(_:)` is written, as any view does —
/// measured on macOS 15.8 (`Tools/SwiftUIProbes/Badge prominence/badgeprom.swift`):
/// `.badge(5).badgeProminence(.decreased)` draws the decreased badge, and
/// `.badgeProminence(.decreased).badge(5)`, written inside the badge, the
/// standard one (decisions B72).
///
/// A conformance rather than a walk through the row's wrappers, so that the
/// type gate (``viewTypeCarriesBadge(_:)``) still answers from the row's type
/// alone and an unbadged row pays nothing for it.
///
/// The write is recognised by its value's TYPE, not by comparing its key path
/// with `\.badgeProminence`: the environment has one value of that type, and
/// key-path equality compares getter addresses, which the linker's
/// deduplication can fold (the `key_path_identity` lint rule).
@MainActor extension EnvironmentModifier: BadgeCarrying where Content: BadgeCarrying {
    fileprivate var carriedBadgeValue: BadgeValue { content.carriedBadgeValue }
    fileprivate var carriedBadgeProminence: BadgeProminence? {
        content.carriedBadgeProminence ?? value as? BadgeProminence
    }
}

/// A list row's badge as the list draws it: its value, and the prominence
/// written around the row's `.badge(_:)` — `nil` where none is, so the list's
/// own applies.
///
/// `@usableFromInline`, with its fields, for `LazyListRowContent`'s
/// `@inlinable` ``LazyListRowContent/badge``, which reads it in place.
@usableFromInline
package struct ListRowBadge: Sendable {
    @usableFromInline package let value: BadgeValue
    @usableFromInline package let prominence: BadgeProminence?

    package init(value: BadgeValue, prominence: BadgeProminence? = nil) {
        self.value = value
        self.prominence = prominence
    }
}

/// The badge a row carries and the prominence written around it —
/// ``extractBadgeValue(from:)`` for a list, which draws both.
@MainActor
package func extractListRowBadge<V: View>(from view: V) -> ListRowBadge? {
    guard let carrier = view as? any BadgeCarrying else { return nil }
    return ListRowBadge(value: carrier.carriedBadgeValue, prominence: carrier.carriedBadgeProminence)
}

/// Extracts the badge value from a view if it's wrapped in a BadgeModifier.
///
/// This is used by List to extract badge values during row extraction.
@MainActor
package func extractBadgeValue<V: View>(from view: V) -> BadgeValue? {
    (view as? any BadgeCarrying)?.carriedBadgeValue
}

/// Whether ``extractBadgeValue(from:)`` could ever answer for a view of
/// `type` — a static property of the row TYPE, no instance needed.
///
/// For a caller that defers building its rows (`List`'s windowed extraction,
/// where an unchanged row is served from the render cache without being
/// built), this is what makes the badge peek free for the overwhelmingly
/// common badge-less row: `extractBadgeValue` needs the BUILT view, and
/// building one every frame just to hear "no badge" was the last per-row
/// construction left on the hit path.
@MainActor
package func viewTypeCarriesBadge<V: View>(_ type: V.Type) -> Bool {
    type is any BadgeCarrying.Type
}

/// The badge a `List` ROW carries — ``extractListRowBadge(from:)``, but seeing
/// past `ForEach`'s value memo.
///
/// The two walks that read a row's badge off its view value — `_ListCore`'s
/// child walk (a `ForEach` with a static row beside it) and `Section`'s — are
/// handed the child as it comes out of `ForEach.makeChild`, which wraps an
/// `Equatable`-element row in `_MemoizedRow`. That wrapper is `Renderable` and
/// therefore *opaque* to the cast above, so the badge on every such row was
/// simply not there: `List { Text("Inbox").badge(7); ForEach(names) {
/// Text($0).badge(9) } }` drew the 7 and none of the 9s. This is the same
/// wrapper-eats-metadata shape `_ListCore.sectionRow(of:)` goes through
/// ``_ValueMemoWrapping`` for, and it goes through it the same way.
///
/// The memo's TYPE is asked before its content, which is what keeps this free:
/// ``_ValueMemoWrapping/memoizedContent`` BUILDS the row, and the whole point
/// of the memo is that in steady state most rows are never built. A row whose
/// static type cannot carry a badge — all but a `.badge(_:)`-outermost row —
/// is answered by the type check alone, exactly as the windowed path's
/// ``viewTypeCarriesBadge(_:)`` gate answers it there.
///
/// Only a row that really IS badged is built here. Where the memo then misses,
/// it builds that row a second time for its buffer — which is precisely what
/// the windowed path already pays for a badged row
/// (`extractBadgeValue(from: content(element))` beside the memoized render);
/// where the memo hits, it builds nothing and this is the only build. So the
/// two arrangements are priced alike, instead of the badge being cheap in one
/// and absent in the other.
@MainActor
package func extractRowBadge(from view: any View) -> ListRowBadge? {
    if let badge = extractListRowBadge(from: view) { return badge }
    guard let memo = view as? any _ValueMemoWrapping,
        viewTypeCarriesBadge(memo.memoizedContentType)
    else { return nil }
    return extractListRowBadge(from: memo.memoizedContent)
}

/// Whether ``extractRowBadge(from:)`` could answer for `view`, asked without
/// building anything: the row's own type, or behind `ForEach`'s value memo the
/// row type the memo would build. `false` means the row has no badge.
///
/// What a row the list draws only when it must (`deferredListRow(of:listRow:context:placedByRamp:)`)
/// says up front, so a hug measure asking every row's width asks no
/// badge-less row for its badge, which would draw it.
@MainActor
package func rowCarriesBadge(_ view: any View) -> Bool {
    if view is any BadgeCarrying { return true }
    guard let memo = view as? any _ValueMemoWrapping else { return false }
    return viewTypeCarriesBadge(memo.memoizedContentType)
}

// MARK: - Renderable

@MainActor extension BadgeModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: badgeContext(context))
    }

    /// The context the content is drawn and measured in: `context` with the
    /// badge value in the environment.
    fileprivate func badgeContext(_ context: RenderContext) -> RenderContext {
        context.withEnvironment(context.environment.setting(\EnvironmentValues.badgeValue, to: value))
    }
}

// MARK: - Layoutable

@MainActor extension BadgeModifier: Layoutable {
    /// Measures `content` under the *same* badge-bearing environment the render
    /// uses: a child that draws the badge (a tab, a list row) sizes differently
    /// with it set, so the plain context would under-measure.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: badgeContext(context))
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it.
@MainActor extension BadgeModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }

    /// Its content's context: the badge value it publishes
    /// (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { badgeContext(context) }
}

/// A badge on several views is each one's, as SwiftUI's modifier on a `Group`
/// reaches each member: `Group { a; b }.badge(2)` in a `List` badges both
/// rows, and in an `HStack` lays them side by side, where it drew `a` over
/// `b`.
@MainActor extension BadgeModifier: ContentRewrapping {
    public func rewrapping<V: View>(_ view: V) -> any View {
        BadgeModifier<V>(content: view, value: value)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``ContentRewrapping`` wrapper.
@MainActor extension BadgeModifier: ChildViewProvider where Content: ChildViewProvider {}

/// Each of a row's cells badged, as each member is.
@MainActor extension BadgeModifier: GridRowProviding where Content: GridRowProviding {}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension BadgeModifier: DrawsContentUnchanged {}

// MARK: - In a Form

/// A badge written on a form row is the row's the form lays out, which keeps
/// its place, as SwiftUI's form keeps it (measured, `Tools/SwiftUIProbes/Form rows`).
@MainActor extension BadgeModifier: FormRowRewrapping {
    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        BadgeModifier<V>(content: row, value: value)
    }
}
