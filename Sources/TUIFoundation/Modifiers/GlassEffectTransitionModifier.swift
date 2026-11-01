//  🖥️ TUI — A Terminal UI framework for Swift
//  GlassEffectTransitionModifier.swift
//
//  `glassEffectID(_:in:)` and `glassEffectTransition(_:)`: how the glass in a
//  container arrives, and which glass is the same glass from one view to the
//  next.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A structure that describes changes to apply when a glass effect is added or
/// removed from the view hierarchy — mirrors SwiftUI's `GlassEffectTransition`.
///
/// In a ``GlassEffectContainer``, glass that arrives under an animation — a
/// view inserted inside `withAnimation`, or a glass that was ``Glass/identity``
/// becoming one — materializes: its surface fades in with the animation, and
/// its rim's lines are drawn from half-way (a glyph is drawn or not), as
/// SwiftUI's materialize transition fades the glass in. It arrives by itself,
/// and joins the glass beside it once it has arrived.
/// ``matchedGeometry``, SwiftUI's default, is drawn as ``materialize``: its
/// growing out of the nearest glass is not drawn (decisions B-GLASS-6).
/// ``identity`` appears at once. Glass leaving goes with its view — its view's
/// own transition plays its glass out with it.
///
/// `Equatable`, unlike SwiftUI's: an environment value the render memo cannot
/// compare turns memoization off below it.
public struct GlassEffectTransition: Sendable, Equatable {
    private enum Kind: UInt8, Sendable, Equatable {
        case matchedGeometry
        case materialize
        case identity
    }

    private let kind: Kind

    /// Returns the matched geometry glass effect transition.
    ///
    /// SwiftUI derives a newly appearing glass's geometry from a nearby glass
    /// in the container and grows it out of that one. Here it materializes, as
    /// ``materialize`` does.
    public static var matchedGeometry: Self { Self(kind: .matchedGeometry) }

    /// The materialize glass effect transition, which fades the glass in with
    /// the animation, and does not match the geometry of any other glass
    /// effect.
    public static var materialize: Self { Self(kind: .materialize) }

    /// The identity transition specifying no changes: the glass appears at
    /// once.
    public static var identity: Self { Self(kind: .identity) }

    /// Whether the glass fades in as it arrives.
    var fadesIn: Bool { kind != .identity }
}

extension View {
    /// Associates a glass effect transition with any glass effects defined
    /// within this view — mirrors SwiftUI's `glassEffectTransition(_:)`.
    ///
    /// In a ``GlassEffectContainer``, the transition says how a glass arrives
    /// under an animation — see ``GlassEffectTransition``.
    ///
    /// - Parameter transition: How the glass arrives.
    /// - Returns: The view, its glass arriving so.
    nonisolated public func glassEffectTransition(_ transition: GlassEffectTransition) -> some View {
        environment(\.glassEffectTransition, transition)
    }

    /// Associates an identity value to glass effects defined within this view
    /// — mirrors SwiftUI's `glassEffectID(_:in:)`.
    ///
    /// In a ``GlassEffectContainer``, glass with an id is the same glass
    /// wherever it is drawn: one that moves from one view to another — two
    /// branches of an `if`, two places in a stack — under an animation does not
    /// arrive again, where glass without one would materialize in its new
    /// place. SwiftUI also animates its geometry from the old place to the new;
    /// that is not drawn here (decisions B-GLASS-6).
    ///
    /// - Parameters:
    ///   - id: The glass's identity, or `nil` for none.
    ///   - namespace: The namespace the id is in.
    /// - Returns: The view, its glass identified.
    nonisolated public func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View {
        environment(\.glassEffectID, id.map { GlassNamespacedID(namespace: namespace, id: AnyHashable($0)) })
    }
}

private struct GlassEffectTransitionKey: EnvironmentKey {
    static let defaultValue = GlassEffectTransition.matchedGeometry
}

private struct GlassEffectIDKey: EnvironmentKey {
    static var defaultValue: GlassNamespacedID? { nil }
}

extension EnvironmentValues {
    /// How the glass in this subtree arrives in a container.
    var glassEffectTransition: GlassEffectTransition {
        get { self[GlassEffectTransitionKey.self] }
        set { self[GlassEffectTransitionKey.self] = newValue }
    }

    /// The identity of the glass in this subtree, or `nil`.
    var glassEffectID: GlassNamespacedID? {
        get { self[GlassEffectIDKey.self] }
        set { self[GlassEffectIDKey.self] = newValue }
    }
}

// MARK: - Arriving

/// The owner of a glass's arrival in the animation store.
private enum GlassArrival {
    /// Where an identified glass's arrival is kept: one place for every glass
    /// with an id, keyed by the id, so a glass that moves keeps its record.
    static let identifiedRoot = ViewIdentity(rootType: Self.self)
}

extension EnvironmentValues {
    /// How present the glass drawn at `identity` in a container is: `0` on
    /// the pass it arrives under an animation, rising to `1`; `1` without an
    /// animation, once it has arrived, and for a glass whose transition is
    /// ``GlassEffectTransition/identity``.
    ///
    /// Asked on every pass the glass draws in a container, which keeps its
    /// record (the container's glass declares a render side effect already, so
    /// no memo skips the asking).
    @MainActor
    func glassArrival(at identity: ViewIdentity, storage: StateStorage) -> Double {
        guard glassEffectTransition.fadesIn else { return 1 }
        let key =
            glassEffectID.map {
                AnimationStore.Key(
                    identity: GlassArrival.identifiedRoot, owner: ObjectIdentifier(GlassArrival.self),
                    slot: $0.hashValue)
            } ?? AnimationStore.Key(identity: identity, owner: ObjectIdentifier(GlassArrival.self))
        return storage.animations.arrivalPhase(
            for: key, animation: canAnimate ? transaction.effectiveAnimation : nil, nowNanos: frameNowNanos,
            isMeasuring: false)
    }
}
