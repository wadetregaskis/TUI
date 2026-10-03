//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewModifier.swift
//
//  SwiftUI's view modifier: a reusable piece of view composition, written as a
//  `body(content:)` that wraps whatever view it is applied to. This is the
//  protocol SwiftUI source conforms its own modifiers to. TUIkit's buffer-level
//  transform, which works on a rendered `FrameBuffer` instead, is
//  ``BufferModifier``.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - ViewModifier

/// A modifier that you apply to a view or another view modifier, producing a
/// different version of the original value.
///
/// Adopt it to make a reusable composition that applies to any view:
///
/// ```swift
/// struct BorderedCaption: ViewModifier {
///     func body(content: Content) -> some View {
///         content
///             .padding(1)
///             .border(.blue)
///     }
/// }
///
/// extension View {
///     func borderedCaption() -> some View {
///         modifier(BorderedCaption())
///     }
/// }
/// ```
///
/// A modifier may hold `@State` and read `@Environment`, as a view does. Its
/// state belongs to the place it is applied, so two views given the same
/// modifier each keep their own.
///
/// A modifier that also conforms to ``Animatable`` animates: a change to its
/// `animatableData` inside an animated transaction is drawn through every
/// frame between the two values, as an animatable view's is.
@MainActor
public protocol ViewModifier {
    /// The type of view representing the body.
    associatedtype Body: View

    /// Gets the current body of the caller.
    ///
    /// - Parameter content: A proxy for the view the modifier is applied to.
    @ViewBuilder
    func body(content: Content) -> Body

    /// The content view type passed to ``body(content:)``.
    typealias Content = _ViewModifier_Content<Self>

    /// Static witness: whether this modifier conforms to ``Animatable``. The
    /// same shape, and the same reason, as ``BufferModifier/_isAnimatable``;
    /// named apart from it so a type can be both a view and a modifier (as
    /// ``ModifiedContent`` is) without the two answers colliding.
    ///
    /// Not to be implemented by hand: conform to ``Animatable`` instead.
    static var _isAnimatableModifier: Bool { get }

    /// Static witness: this modifier at the value the animation store says to
    /// draw it at, or `nil` when nothing is moving. See
    /// ``BufferModifier/_animated(_:owner:context:isMeasuring:)``.
    ///
    /// Not to be implemented by hand.
    @MainActor
    static func _animatedModifier(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self?
}

extension ViewModifier {
    /// A modifier says nothing continuous about itself unless it is
    /// ``Animatable``.
    @inlinable
    public static var _isAnimatableModifier: Bool { false }

    /// A modifier with nothing continuous about it never needs substituting.
    @inlinable
    public static func _animatedModifier(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        nil
    }

    /// Returns a new modifier that is the result of concatenating `self` with
    /// `modifier`: applying it is applying `self`, then `modifier` around that.
    ///
    /// - Parameter modifier: The modifier to apply after this one.
    /// - Returns: The two, as one modifier.
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ViewModifier where Self: Animatable {
    /// An ``Animatable`` modifier's data is substituted before its body is
    /// built, exactly as an animatable view's is.
    @inlinable
    public static var _isAnimatableModifier: Bool { true }

    /// This modifier at the value the store says to draw it at.
    @MainActor
    public static func _animatedModifier(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        animatedValue(of: modifier, owner: owner, context: context, isMeasuring: isMeasuring)
    }
}

// MARK: - The content proxy

/// The view a ``ViewModifier`` is applied to, as its ``ViewModifier/body(content:)``
/// sees it.
///
/// Generic over the modifier rather than the content, as SwiftUI's is, so one
/// modifier type has one `Content` type whatever it is applied to: the view it
/// stands for is held erased.
public struct _ViewModifier_Content<Modifier: ViewModifier>: View {
    /// The view the modifier was applied to.
    let content: AnyView

    init(_ content: AnyView) {
        self.content = content
    }

    public var body: some View {
        content
    }
}

// MARK: - ModifiedContent

/// A value with a modifier applied to it — what ``View/modifier(_:)`` returns,
/// and what ``ViewModifier/concat(_:)`` builds from two modifiers.
///
/// It is a ``View`` when its content is a view and its modifier a
/// ``ViewModifier``, and itself a ``ViewModifier`` when both halves are.
public struct ModifiedContent<Content, Modifier> {
    /// The content that the modifier transforms into a new view or new view
    /// modifier.
    public var content: Content

    /// The view modifier.
    public var modifier: Modifier

    /// A structure that the defines the content and modifier needed to produce
    /// a new view or view modifier.
    ///
    /// - Parameters:
    ///   - content: The content that the modifier changes.
    ///   - modifier: The modifier to apply to the content.
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    /// The modifier's body, built around this content.
    public var body: some View {
        modifier.body(content: _ViewModifier_Content(AnyView(content)))
    }

    /// Forwarded from the modifier: this view animates exactly when its
    /// modifier does. Declared with the `View` conformance rather than in a
    /// separate conditional `Animatable` one, which could not supply the
    /// witness — see ``ModifiedView/_isAnimatable``.
    @inlinable
    public static var _isAnimatable: Bool { Modifier._isAnimatableModifier }

    /// Forwarded to the modifier, keyed by this view's type so two of the
    /// same modifier around one view keep separate animations.
    @MainActor
    public static func _animated(
        _ view: Self, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        guard let animated = Modifier._animatedModifier(
            view.modifier, owner: Self.self, context: context, isMeasuring: isMeasuring)
        else { return nil }
        var copy = view
        copy.modifier = animated
        return copy
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    /// The first modifier, then the second around it.
    public func body(content: _ViewModifier_Content<Self>) -> some View {
        content.modifier(self.content).modifier(self.modifier)
    }
}

extension ModifiedContent: Animatable where Content: Animatable, Modifier: Animatable {
    /// The content's data, then the modifier's.
    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, Modifier.AnimatableData>

    /// The content's and the modifier's animatable data, together.
    public var animatableData: AnimatableData {
        get { AnimatablePair(content.animatableData, modifier.animatableData) }
        set {
            content.animatableData = newValue.first
            modifier.animatableData = newValue.second
        }
    }
}

// MARK: - EmptyModifier

/// A modifier that leaves the view it is applied to as it is — the identity
/// that conditional modifier code starts from.
public struct EmptyModifier: ViewModifier {
    /// The empty modifier.
    public static let identity = Self()

    /// Creates the empty modifier.
    public init() {}

    /// The content, unchanged.
    public func body(content: Content) -> some View {
        content
    }
}

// MARK: - Applying a modifier

extension View {
    /// Applies a modifier to a view and returns a new view.
    ///
    /// - Parameter modifier: The modifier to apply to this view.
    /// - Returns: This view with the modifier applied.
    public func modifier<T: ViewModifier>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}
