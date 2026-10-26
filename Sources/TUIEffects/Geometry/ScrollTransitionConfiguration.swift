//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollTransitionConfiguration.swift
//
//  `ScrollTransitionPhase` and `ScrollTransitionConfiguration`: where a view
//  is on its way into a scroll view's visible region, and how a scroll
//  transition follows it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Phase

/// The phases that a view transitions between when it scrolls among other
/// views.
///
/// When a view with a scroll transition modifier applied is approaching the
/// visible region of the containing scroll view, the effect will first be
/// applied with the `topLeading` or `bottomTrailing` phase (depending on which
/// edge the view is approaching), then will be moved to the `identity` phase as
/// the view moves into the visible area. The timing and behavior that
/// determines when a view is visible within the container is controlled by the
/// configuration that is provided to the `scrollTransition` modifier.
///
/// In the `identity` phase, scroll transitions should generally not make any
/// visual change to the view they are applied to, since the transition's view
/// modifications in the `identity` phase will be applied to the view as long
/// as it is visible. In the `topLeading` and `bottomTrailing` phases,
/// transitions should apply a change that will be animated to create the
/// transition.
@frozen
public enum ScrollTransitionPhase: Hashable, Sendable {
    /// The scroll transition is being applied to a view that is about to move
    /// into the visible area at the top edge of a vertical scroll view, or the
    /// leading edge of a horizontal scroll view.
    case topLeading

    /// The scroll transition is being applied to a view that is in the visible
    /// area.
    ///
    /// In this phase, a transition should show its steady state appearance,
    /// which will generally not make any visual change to the view.
    case identity

    /// The scroll transition is being applied to a view that is about to move
    /// into the visible area at the bottom edge of a vertical scroll view, or
    /// the trailing edge of a horizontal scroll view.
    case bottomTrailing

    /// Whether this is the `identity` phase.
    public var isIdentity: Bool { self == .identity }

    /// A phase-derived value that can be used to scale or otherwise modify
    /// effects.
    ///
    /// Returns -1.0 when in the topLeading phase, zero when in the identity
    /// phase, and 1.0 when in the bottomTrailing phase.
    public var value: Double {
        switch self {
        case .topLeading: -1
        case .identity: 0
        case .bottomTrailing: 1
        }
    }
}

// MARK: - Configuration

/// The configuration of a scroll transition that controls how a transition is
/// applied as a view is scrolled through the visible region of a containing
/// scroll view or other container.
///
/// Distances are cells, where SwiftUI's are points: a view's progress into
/// the viewport is measured in whole rows (or columns), so an interactive
/// transition moves in steps of one row's worth of the way.
public struct ScrollTransitionConfiguration: Sendable {
    /// How the effect follows the view.
    enum Kind: Sendable {
        /// Interpolated with the view's progress, paced by the curve.
        case interactive(UnitCurve)
        /// Switched when the threshold is crossed, and animated there.
        case animated
        /// Never changed: the identity phase throughout.
        case identity
    }

    let kind: Kind

    /// The point at which the view counts as fully visible: `.visible` unless
    /// the configuration says otherwise, and `.visible(0.5)` for an animated
    /// one, as SwiftUI's own defaults are (read from its configurations on
    /// macOS 15, and seen to behave so: `Tools/SwiftUIProbes/Scroll
    /// transitions/`).
    var visibleThreshold: Threshold = .visible

    /// The animation the effect is moved with, if any.
    var transitionAnimation: Animation?

    /// Creates a new configuration that discretely animates the transition
    /// when the view becomes visible.
    public static let animated = Self.animated()

    /// Creates a new configuration that discretely animates the transition
    /// when the view becomes visible.
    ///
    /// Unlike the interactive configuration, the transition isn't interpolated
    /// as the scroll view is scrolled. Instead, the transition phase only
    /// changes once the threshold has been reached, at which time the given
    /// animation is used to animate to the new phase.
    ///
    /// The threshold is half the view, `.visible(0.5)`, until
    /// ``threshold(_:)`` sets another: SwiftUI's animated configurations start
    /// there, where its interactive ones start at `.visible`.
    ///
    /// - Parameter animation: The animation to use when transitioning between
    ///   states.
    /// - Returns: A configuration that discretely animates between transition
    ///   phases.
    public static func animated(_ animation: Animation = .default) -> Self {
        Self(kind: .animated, visibleThreshold: .visible(0.5), transitionAnimation: animation)
    }

    /// Creates a new configuration that interactively interpolates the
    /// transition's effect as the view is scrolled into the visible region of
    /// the container.
    public static let interactive = Self.interactive()

    /// Creates a new configuration that interactively interpolates the
    /// transition's effect as the view is scrolled into the visible region of
    /// the container.
    ///
    /// - Parameter timingCurve: The curve that adjusts the pace at which the
    ///   effect is interpolated between phases of the transition. The curve is
    ///   applied 'forward' while the view is appearing, meaning that time zero
    ///   corresponds to the view being just hidden, and time 1.0 corresponds to
    ///   the point at which the view reaches the configuration threshold.
    /// - Returns: A configuration that interactively interpolates between
    ///   transition phases based on the current scroll position.
    public static func interactive(timingCurve: UnitCurve = .easeInOut) -> Self {
        Self(kind: .interactive(timingCurve))
    }

    /// Creates a new configuration that does not change the appearance of the
    /// view.
    public static let identity = Self(kind: .identity)

    /// Sets the animation with which the transition will be applied.
    ///
    /// If the transition is interactive, the given animation will be used to
    /// animate the effect toward the current interpolated value, causing the
    /// effect to lag behind the current scroll position.
    ///
    /// - Parameter animation: An animation that will be used to apply the
    ///   transition to the view.
    /// - Returns: A copy of this configuration with the animation set to the
    ///   given value.
    public func animation(_ animation: Animation) -> Self {
        var copy = self
        copy.transitionAnimation = animation
        return copy
    }

    /// Sets the threshold at which the view will be considered fully visible.
    ///
    /// - Parameter threshold: The threshold specifying how much of the view
    ///   must intersect with the container before it is treated as visible.
    /// - Returns: A copy of this configuration with the threshold set to the
    ///   given value.
    public func threshold(_ threshold: Threshold) -> Self {
        var copy = self
        copy.visibleThreshold = threshold
        return copy
    }
}

// MARK: - Threshold

extension ScrollTransitionConfiguration {
    /// Describes a specific point in the progression of a target view within a
    /// container from hidden (fully outside the container) to visible.
    public struct Threshold: Sendable {
        /// The point, as data.
        indirect enum Point: Sendable {
            /// This fraction of the view inside the container, `0...1`.
            case visible(Double)
            /// The view centred in the container.
            case centered
            /// Another point moved this many cells towards the centre.
            case inset(Self, Double)
            /// Two points mixed, `0` the first and `1` the second.
            case interpolated(Self, Self, Double)
        }

        let point: Point

        /// The target view is fully visible within the container.
        public static let visible = Self(point: .visible(1))

        /// The target view is fully hidden, just outside the container.
        public static let hidden = Self(point: .visible(0))

        /// The target view is centered within the container.
        public static var centered: Self { Self(point: .centered) }

        /// The target view is visible by the given amount, where zero is fully
        /// hidden, and one is fully visible.
        ///
        /// Values less than zero or greater than one are clamped.
        ///
        /// - Parameter amount: How much of the view is inside the container.
        /// - Returns: The threshold.
        public static func visible(_ amount: Double) -> Self {
            Self(point: .visible(min(1, max(0, amount))))
        }

        /// Returns a threshold that is met when the target view is closer to
        /// the center of the container by `distance`, in cells. Use negative
        /// values to move the threshold away from the center.
        ///
        /// - Parameter distance: How much closer to the centre, in cells.
        /// - Returns: The threshold.
        public func inset(by distance: Double) -> Self {
            Self(point: .inset(point, distance))
        }

        /// Creates a new threshold that combines this threshold value with
        /// another threshold, interpolated by the given amount.
        ///
        /// - Parameters:
        ///   - other: The second threshold value.
        ///   - amount: The ratio with which this threshold is combined with the
        ///     given threshold, where zero is equal to this threshold, 1.0 is
        ///     equal to `other`, and values in between combine the two
        ///     thresholds.
        /// - Returns: The combined threshold.
        public func interpolated(towards other: Self, amount: Double) -> Self {
            Self(point: .interpolated(point, other.point, amount))
        }
    }
}

extension ScrollTransitionConfiguration.Threshold.Point {
    /// How far the view's leading (or top) edge is from the edge of the
    /// container it comes in at when this point is met: `0` with the view just
    /// outside, `length` with it just wholly inside. Along one axis.
    ///
    /// - Parameters:
    ///   - length: The view's extent along the axis.
    ///   - container: The container's.
    func depth(length: Double, container: Double) -> Double {
        switch self {
        case .visible(let amount):
            // The view inside by `amount` of itself — or of the container, for
            // a view longer than it, which can never be more inside than that.
            return amount * min(length, container)
        case .centered:
            return (container + length) / 2
        case .inset(let base, let distance):
            return base.depth(length: length, container: container) + distance
        case .interpolated(let from, let to, let amount):
            let start = from.depth(length: length, container: container)
            return start + (to.depth(length: length, container: container) - start) * amount
        }
    }
}
