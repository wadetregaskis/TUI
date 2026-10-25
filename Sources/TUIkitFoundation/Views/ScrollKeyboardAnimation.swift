//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollKeyboardAnimation.swift
//
//  The TUI-only opt-in that makes a scrollable's Page Up/Down and Home/End
//  glide rather than jump (decisions B27-ANIMATING; the design note's §4,
//  `Documentation/SwiftUI parity/Decisions/Scrolling/Animated scrolling, a
//  design (B27).md`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// `@usableFromInline`, so internal rather than `private`, with its default:
/// the `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ScrollKeyboardAnimationKey: EnvironmentKey {
    /// None: the keys jump, as they always have.
    @usableFromInline static let defaultValue: Animation? = nil
}

extension EnvironmentValues {
    /// The animation a scrollable's Page Up/Down and Home/End glide with, or
    /// `nil` (the default) to jump. Set with
    /// ``TUIkit/View/scrollKeyboardAnimation(_:)``. TUI-specific.
    @inlinable
    public var scrollKeyboardAnimation: Animation? {
        get { self[ScrollKeyboardAnimationKey.self] }
        set { self[ScrollKeyboardAnimationKey.self] = newValue }
    }
}

extension View {
    /// Makes Page Up, Page Down, Home and End glide a line at a time to where
    /// they take a `ScrollView` below, along `animation`'s curve, rather than
    /// jump there; `nil` jumps, as the keys do by default. TUI-specific:
    /// SwiftUI on macOS has no keyboard scrolling of this kind to animate.
    ///
    /// The key lands where it always has — on the page the scroll target
    /// behaviour (`.paging`, `.viewAligned`) picks, at the edge, or at the tail
    /// for End — and the view glides there. A key pressed while one glides
    /// counts from where it is going, so three presses move exactly three
    /// pages; an arrow lands the glide first and then steps. The wheel stops
    /// it where it stands. The view is ``ScrollPhase/interacting`` throughout,
    /// as for any key, and idle a quarter of a second after it lands. Under
    /// reduce motion, and with no animation scheduler, the keys jump.
    ///
    /// The arrows, the wheel and a push into an overscroll allowance do not
    /// glide: they move a line or a few at once.
    public func scrollKeyboardAnimation(_ animation: Animation? = .default) -> some View {
        environment(\.scrollKeyboardAnimation, animation)
    }
}
