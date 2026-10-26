//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentTransitionModifier.swift
//
//  `contentTransition(_:)`: a change WITHIN a view, animated — each text's or
//  image's old drawing dissolving into its new one (`ContentDissolve`,
//  TUIFoundation).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// A kind of transition that applies to the content within a single view,
/// rather than to the insertion or removal of a view.
///
/// Set the behavior of content transitions within a view with the
/// `contentTransition(_:)` modifier, passing in one of the defined transitions,
/// such as ``opacity`` or ``interpolate`` as the parameter.
///
/// > Tip: Content transitions only take effect within transactions that apply
/// an ``Animation`` to the views inside the `contentTransition(_:)` modifier.
///
/// ## In cells
///
/// Every transition but ``identity`` dissolves a `Text`'s or an `Image`'s old
/// drawing into its new one, cell by cell, through the opacity compositor: a cell's colours blend,
/// and its glyph changes half way. That IS `interpolate` here — a cell whose
/// character is the same in both keeps it and moves only its colours, which is
/// what SwiftUI's interpolation does for "matching glyph pairs", and anything
/// else uses an opacity animation, which is SwiftUI's own fallback.
/// `numericText` dissolves the changed digits too: SwiftUI promises its
/// rolling digits only "in certain environments". The symbol-effect content
/// transitions are not offered (they need the Symbols framework's types).
public struct ContentTransition: Equatable, Sendable {
    enum Storage: Equatable, Sendable {
        /// What an environment holds when nothing has said otherwise: a
        /// change is drawn at once.
        case unspecified
        case identity
        case opacity
        case interpolate
        case numericText(countsDown: Bool)
        case numericValue(Double)
    }

    let storage: Storage

    /// The identity content transition, which indicates that content changes
    /// shouldn't animate.
    ///
    /// You can pass this value to a `contentTransition(_:)` modifier to
    /// selectively disable animations that would otherwise be applied by a
    /// ``withAnimation(_:_:)`` block.
    public static let identity = Self(storage: .identity)

    /// A content transition that indicates content fades from transparent to
    /// opaque on insertion, and from opaque to transparent on removal.
    public static let opacity = Self(storage: .opacity)

    /// A content transition that indicates the views attempt to interpolate
    /// their contents during transitions, where appropriate.
    ///
    /// A cell whose character is the same before and after keeps it and moves
    /// its colours; any other cell dissolves, as an opacity transition does.
    public static let interpolate = Self(storage: .interpolate)

    /// Creates a content transition intended to be used with `Text` views
    /// displaying numeric text. In certain environments changes to the text
    /// will enable a nonstandard transition tailored to numeric characters
    /// that count up or down; here the changed digits dissolve.
    ///
    /// - Parameter countsDown: true if the numbers represented by the text are
    ///   counting downwards.
    /// - Returns: a new content transition.
    public static func numericText(countsDown: Bool = false) -> Self {
        Self(storage: .numericText(countsDown: countsDown))
    }

    /// Creates a content transition intended to be used with `Text` views
    /// displaying numbers.
    ///
    /// ```swift
    /// Text("\(value)")
    ///     .contentTransition(.numericText(value: value))
    /// ```
    ///
    /// - Parameter value: the value represented by the `Text` view being
    ///   animated. The difference between the old and new values when the
    ///   text changes will be used to determine the animation direction.
    /// - Returns: a new content transition.
    public static func numericText(value: Double) -> Self {
        Self(storage: .numericValue(value))
    }

    /// Whether a change under this transition is drawn as a dissolve.
    var dissolves: Bool {
        switch storage {
        case .unspecified, .identity: false
        case .opacity, .interpolate, .numericText, .numericValue: true
        }
    }
}

private struct ContentTransitionKey: EnvironmentKey {
    static let defaultValue = ContentTransition(storage: .unspecified)
}

private struct ContentTransitionAddsDrawingGroupKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The current method of animating the contents of views.
    ///
    /// Unset, it is a value equal to none of the named transitions — as in
    /// SwiftUI, measured — and a change is drawn at once, as TUI has always
    /// drawn one.
    ///
    /// Each `Text` and `Image` reads it as it draws, as SwiftUI's leaf views
    /// do: under a transition that dissolves, it keeps its last drawing and
    /// dissolves a change made under an animation (see
    /// ``View/contentTransition(_:)``).
    public var contentTransition: ContentTransition {
        get { self[ContentTransitionKey.self] }
        set {
            self[ContentTransitionKey.self] = newValue
            // What the leaves read, which cannot see this type: written here,
            // by the one setter, so the two always agree.
            contentDissolves = newValue.dissolves
        }
    }

    /// A Boolean value that controls whether views that render content
    /// transitions use GPU-accelerated rendering.
    ///
    /// A rendering strategy with no visible contract: SwiftUI wraps the
    /// transition in a drawing group, which changes how it is composited and
    /// not what it shows. A terminal composites cells either way, so the value
    /// is kept for whoever reads it and draws the same thing.
    public var contentTransitionAddsDrawingGroup: Bool {
        get { self[ContentTransitionAddsDrawingGroupKey.self] }
        set { self[ContentTransitionAddsDrawingGroupKey.self] = newValue }
    }
}

extension View {
    /// Modifies the view to use a given transition as its method of animating
    /// changes to the contents of its views.
    ///
    /// This modifier allows you to perform a transition that animates a change
    /// within a single view. A change made under an animation — inside
    /// ``withAnimation(_:_:)``, say — dissolves from the old drawing to the new
    /// one over the animation, rather than replacing it at once:
    ///
    /// ```swift
    /// Text("\(count)")
    ///     .contentTransition(.numericText(value: Double(count)))
    /// ```
    ///
    /// > Tip: The `contentTransition(_:)` modifier only has an effect within
    /// the context of an ``Animation``.
    ///
    /// Each `Text` and `Image` inside reads the transition and dissolves its
    /// own change, as SwiftUI's leaf views do, so an inner
    /// `contentTransition(.identity)` exempts its part. A view that is not a
    /// text or an image — a shape, a colour, a control's chrome — changes as
    /// it would without the modifier: an animatable one animates. A leaf keeps
    /// the size of its new content, so a drawing that shrinks loses its edges
    /// at once.
    ///
    /// - Parameter transition: The transition to apply when animating the
    ///   content change.
    public func contentTransition(_ transition: ContentTransition) -> some View {
        environment(\.contentTransition, transition)
    }
}
