//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollAnchorMode.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Anchor mode

/// Which policy a scrollable applies to its persisted anchor when the data
/// changes underneath it — the four modes of `Documentation/Layout and scrolling/Scroll anchoring.md`
/// §1.1, made explicit rather than implied by which render path happens to run.
///
/// | Mode | Meaning |
/// |---|---|
/// | ``top`` | The view stays at the top, whatever rows are added / removed / moved. |
/// | ``bottom`` | The view stays at the bottom (follow-the-log). |
/// | ``row`` | A designated row keeps its place on screen as rows change around it. |
/// | ``window`` | *No* anchor (the default): the rows on screen stay where they are unless something explicitly moves them — the row at the top keeps its line as the content above it changes, or, under ``ScrollWindowHold/offset``, the offset keeps its value in lines. |
///
/// Only ``row`` holds a row of its own. ``top`` and ``bottom`` are
/// **positional** (see ``ScrollAnchor``'s doc comment: they name an edge, not a
/// row): at their edge they keep the view there, and away from it they are
/// Window. That is why a prepend under ``top`` shows the new first rows rather
/// than following the old one down — and why the top-row hold is the scroll
/// view's to switch on (``ScrollContentWindow/topRowHold``), which knows
/// whether the view is at an edge, and not a property of the mode.
///
/// ``row`` is designated through its own API — ``ScrollAnchor/row(_:)`` written
/// into a bound ``TUI/View/anchorPosition(_:)`` — per the spec's guardrail
/// #1, rather than by overloading the `UnitPoint` anchor. It is deliberately
/// *not* declarable: ``resolved(defaultScrollAnchor:)`` maps a `UnitPoint` and
/// can only yield ``top``, ``bottom`` or ``window``, since a declaration has no
/// way to name which row it means.
///
/// `@usableFromInline`: the type of the `@inlinable` `EnvironmentValues.declaredAnchorModes`
/// (module split step A3).
///
/// `Sendable` stated, as it was inferred while the type was not usable from
/// inline code: the compiler infers it only for types that are not.
@usableFromInline
package enum ScrollAnchorMode: Equatable, Sendable {
    case top
    case bottom
    case row
    case window

    /// The mode a scrollable runs in given its ``EnvironmentValues/defaultScrollAnchor``.
    ///
    /// `nil` — no anchor asked for — is ``window``, the spec's default. A
    /// `UnitPoint` near the top or bottom edge resolves to that edge's mode;
    /// anything mid-content has no edge meaning and stays ``window``. The
    /// 0.75 threshold matches the bottom-affinity test the scroll view
    /// already applies, so the two cannot drift apart.
    ///
    /// `@usableFromInline`: the `@inlinable` `EnvironmentValues.declaredAnchorModes` calls it
    /// (module split step A3).
    @usableFromInline
    static func resolved(defaultScrollAnchor anchor: UnitPoint?) -> Self {
        guard let y = anchor?.y else { return .window }
        if y >= 0.75 { return .bottom }
        if y <= 0.25 { return .top }
        return .window
    }

    /// Which DECLARED mode governs this frame: a scrollable places itself by
    /// its ``ScrollAnchorRole/initialOffset`` anchor on the frame it first
    /// renders, and by its ``ScrollAnchorRole/sizeChanges`` anchor from then on.
    ///
    /// That single sentence is the whole of the role split, and it is
    /// **behaviour-neutral for every view that has not used the role
    /// overload**: the unlabelled `defaultScrollAnchor(_:)` sets both roles to
    /// the same `UnitPoint`, so `opening` and `standing` are the same value and
    /// the substitution cannot change anything. It has to be expressed this way
    /// round — the opening frame reading the OPENING anchor — rather than as an
    /// extra seek, because today's opening placement is not a separate step: a
    /// scrollable with no content yet is at its own bottom (`offset 0 ==
    /// maxOffset 0`), so the follow rule glues on frame one and *that* is what
    /// lands a `.bottom` view at the tail. A `.bottom` declared for
    /// `.sizeChanges` alone therefore needs the opening frame to consult
    /// something that is NOT `.bottom`, or it would open at the tail after all.
    /// `opening` is OPTIONAL for the same reason the environment key it comes
    /// from is doubly so: a handler told only `declaredAnchorMode` — which is
    /// every caller that predates the roles, the tests among them — must keep
    /// behaving exactly as it did, and the way to guarantee that is to make
    /// "nobody stated an opening anchor" defer rather than default.
    package static func governing(opening: Self?, standing: Self, hasOpened: Bool) -> Self {
        hasOpened ? standing : (opening ?? standing)
    }

    /// The mode actually in effect: a **non-nil** bound
    /// ``TUI/View/anchorPosition(_:)`` overrides the declared anchor
    /// (``resolved(defaultScrollAnchor:)``); `nil` means "no departure from the
    /// declaration" and falls back to it. The scroll handlers capture
    /// `declaredAnchorMode` at render so event-time code can read it.
    ///
    /// This is what makes writing `nil` restore the declared anchor — the
    /// declaration is re-asserted by the view tree every render, so it is
    /// always recoverable and the framework keeps no hidden shadow state. It is
    /// also why `.window` and `nil` must stay distinct: `.window` is an
    /// explicit release (the user scrolled away), `nil` is "never left".
    package static func effective(boundAnchor: ErasedScrollAnchor?, declared: Self) -> Self {
        switch boundAnchor {
        case .none: return declared
        case .top: return .top
        case .bottom: return .bottom
        case .row: return .row
        case .window: return .window
        }
    }
}
