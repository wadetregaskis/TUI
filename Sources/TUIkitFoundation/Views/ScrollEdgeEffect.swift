//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollEdgeEffect.swift
//
//  The scroll edge effects: `ScrollEdgeEffectStyle`, `scrollEdgeEffectStyle(_:for:)`
//  and `scrollEdgeEffectHidden(_:for:)` (refusal review O7, decisions A12).
//
//  In SwiftUI they style scrolled content where it passes under a bar — a
//  toolbar, a `safeAreaBar` — fading it (`.soft`) or cutting it at a rule
//  (`.hard`), or showing it plain (hidden). Here nothing passes under a bar:
//  a bar is subtracted from what the view beside it is offered (decisions B6,
//  whose fuller safe area the owner declined on 2026-10-12), so scrolled
//  content stops at a bar's edge, as `.hard` cuts it. These return `self`, and
//  that is not a stub (see `MediumGuaranteedModifiers.swift`): `.automatic`,
//  `.hard` and hidden describe what is always drawn, and the tests assert that
//  guarantee rather than the no-op. `.soft`, content seen faded through a bar,
//  is the one style the medium cannot give, and is left out so that code
//  asking for it fails to compile (O7, ruled 2026-10-12).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollEdgeEffectStyle

/// How scrolled content is drawn where it meets a bar. Mirrors SwiftUI's
/// `ScrollEdgeEffectStyle`, without `.soft`.
///
/// Scrolled content never passes under a bar here, so it always stops at the
/// bar's edge: what ``hard`` asks for, and what ``automatic`` is. SwiftUI's
/// `.soft` fades the content seen through a bar; there is nothing to see
/// through, so it is left out rather than accepted and not drawn.
public struct ScrollEdgeEffectStyle: Hashable, Sendable {
    private enum Kind: Hashable, Sendable {
        case automatic, hard
    }

    private let kind: Kind

    /// The style the platform chooses: here, content stopping at the bar.
    public static var automatic: Self { Self(kind: .automatic) }

    /// Content cut sharply at the bar's edge, which is how it always meets a
    /// bar here.
    public static var hard: Self { Self(kind: .hard) }
}

// MARK: - Modifiers

extension View {
    /// Configures the scroll edge effect of scroll views within this view.
    /// Mirrors SwiftUI's `scrollEdgeEffectStyle(_:for:)`.
    ///
    /// Scrolled content stops at a bar's edge here, never passing under it, so
    /// both styles — ``ScrollEdgeEffectStyle/automatic`` and
    /// ``ScrollEdgeEffectStyle/hard`` — and `nil`, which leaves the style to
    /// the views above, are what is drawn already.
    ///
    /// - Parameters:
    ///   - style: The style, or `nil` for the inherited one.
    ///   - edges: The edges the style is for.
    /// - Returns: This view, unchanged.
    public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View {
        self
    }

    /// Hides, or shows, the scroll edge effect of scroll views within this
    /// view. Mirrors SwiftUI's `scrollEdgeEffectHidden(_:for:)`.
    ///
    /// With the effect hidden, SwiftUI draws content under a bar unaltered.
    /// Here content never passes under a bar, so there is nothing to draw
    /// unaltered and nothing to hide: hidden or shown, scrolled content stops
    /// at the bar's edge.
    ///
    /// - Parameters:
    ///   - hidden: Whether the effect is hidden.
    ///   - edges: The edges it is hidden for.
    /// - Returns: This view, unchanged.
    public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View {
        self
    }
}
