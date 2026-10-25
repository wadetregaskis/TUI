//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyTransition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling
import TUIkitView

/// How a view arrives and how it leaves.
///
/// ```swift
/// if showDetail {
///     Detail().transition(.move(edge: .top).combined(with: .opacity))
/// }
/// ```
///
/// A transition is a function of one number — how *present* the view is, `0`
/// absent through `1` fully there — applied to the cells the view drew. An
/// insertion runs it forwards, a removal backwards.
///
/// ## What a terminal changes about this
///
/// The effects are applied to the **rendered buffer**, not to the layout. A
/// view sliding in gets its space at once and moves into it, as SwiftUI's
/// does — measured, the layout changes at once and the views it displaces
/// glide out of its way with the change (``View/transition(_:)-(AnyTransition)``, "The views
/// around it"). What a transition here never does is change the view's own
/// size as it plays: that is what makes it cost one buffer transform per
/// frame rather than a full re-layout — in a grid of whole cells, a view
/// growing by fractions of a cell has nothing to show for most of the frames
/// anyway.
///
/// `.scale` is the effect that changes most: there is no sub-cell rendering to
/// shrink, so it reveals the view from its anchor a whole cell at a time.
///
/// While a view is ARRIVING, the slot clips it: the part still outside is not
/// drawn. A SwiftUI frame clips nothing — `View.clipped(antialiased:)`
/// documents that a bounding frame is used only for layout and that content
/// beyond it stays visible — so a view sliding in there is expected to cross
/// its siblings. Here it would cross them by *erasing* them: a terminal cell
/// holds one glyph, so an arriving view has no way to be over a neighbour
/// without taking its cell. Wrap the transition in a container that clips (a
/// `ScrollView`, a `List`) and SwiftUI agrees; put it in a plain stack and this
/// is a deviation.
///
/// ## Overshoot
///
/// A spring goes past its target and comes back, so a phase above `1` is a
/// real value and not a rounding artefact — `Animation.bouncy` peaks at
/// **1.0460**, `Animation.snappy` at **1.0063**, and `Animation.smooth`, which
/// has no bounce, at exactly 1.
///
/// ``move(edge:)`` and ``offset(x:y:)`` draw that: past 1 the view stands a
/// cell or two clear of the slot it has just arrived in, floating over
/// whatever is beside it as `View.offset(x:y:)` does. The
/// displacement follows the curve with no minimum, so `.snappy`'s 0.13 of a
/// cell across a twenty-cell view draws no bounce at all — which is right,
/// since SwiftUI's snappy does not visibly bounce either. It is a whole number
/// of cells, so the bounce is bigger on a wide view (four cells across an
/// 80-column row at `.bouncy`) and, vertically, needs a panel eleven rows tall
/// before it moves at all.
///
/// ``opacity`` and ``scale`` stop at 1, and for reasons belonging to the
/// effects rather than to the spring: nothing is more opaque than opaque, and
/// `.scale` uncovers the buffer from an anchor — the buffer IS the slot, so
/// there is nothing beyond it to uncover.
///
/// Three consequences of floating the overshoot, each chosen and each a
/// deviation from a permanent `.offset`:
///
/// - **Clicks stay at the slot.** A transitioning view's hit-test regions
///   describe where it will be, not the cells it is passing through, for the
///   whole transition. Moving them with the picture would let them win the hit
///   test over a peer control the bounce is standing on, which is a worse
///   failure than a click landing where the eye aimed 100 ms ago.
/// - **Trailing blanks do not erase.** The floated cells are trimmed of
///   trailing padding first; a row that was all padding becomes nothing at all.
///   Leading blanks inside a row that has content do still paint over what they
///   pass, and so do INTERIOR ones — a `Spacer` between two labels erases what
///   is under the gap for as long as the bounce lasts. A layer has one origin,
///   not one per line, and rectangular content rather than a set of inked cells.
/// - **The screen edge cuts rather than pushes.** A view bouncing at the edge
///   loses the columns that fall off it, instead of sliding back on screen the
///   way a menu does.
public struct AnyTransition: Sendable, Equatable {

    /// One effect, or several composed. A value rather than a closure so a
    /// transition can be compared, stored, and reasoned about in a test.
    indirect enum Effect: Sendable, Equatable {
        /// Whether the effect moves the view — every one but a fade and none.
        var hasMotion: Bool {
            switch self {
            case .identity, .opacity: false
            case .move, .offset, .scale: true
            case .combined(let first, let second): first.hasMotion || second.hasMotion
            }
        }

        /// Appears and disappears with no effect at all.
        case identity
        /// Fades toward the background.
        case opacity
        /// Slides in from, or out towards, an edge.
        case move(edge: Edge)
        /// Slides from a displacement of its own choosing.
        case offset(x: Int, y: Int)
        /// Reveals from an anchor, a cell at a time, starting from `factor`
        /// of the view.
        case scale(factor: Double, anchor: UnitPoint)
        /// Both, applied in order.
        case combined(Self, Self)
    }

    let insertion: Effect
    let removal: Effect

    /// A transition with a body of the app's own, drawn through that body —
    /// in which case `insertion` and `removal` are unused. `nil` for every
    /// transition made of the effects above, which keep their buffer path.
    /// See ``Transition``.
    let custom: _AnyTransitionBox?

    /// The animation the view arrives with where this transition names one,
    /// overriding the change's: `nil` where it names none and arrives under
    /// the change's, and `.some(nil)` where it names none at all —
    /// `.animation(nil)` — and arrives at once whatever the change's.
    ///
    /// A double optional, the third state the style cascade's `Font??` and
    /// `TextCase??` carry for the same reason: `nil` stated is not `nil`
    /// unsaid. SwiftUI plays `.opacity.animation(nil)` at once under
    /// `withAnimation`, both ways (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr1.out` T5).
    ///
    /// One for each half, as SwiftUI keeps them (T4): `asymmetric(insertion:
    /// .opacity.animation(.linear(duration: 2)), removal:
    /// .opacity.animation(.linear(duration: 8)))` arrives in two seconds and
    /// leaves in eight, whatever the change's animation.
    var insertionAnimation: Animation??

    /// The animation the view leaves with where this transition names one,
    /// or names none at all; `nil` where it leaves under the change's. See
    /// ``insertionAnimation``.
    var removalAnimation: Animation??

    init(insertion: Effect, removal: Effect, insertionAnimation: Animation?? = nil, removalAnimation: Animation?? = nil) {
        self.insertion = insertion
        self.removal = removal
        self.custom = nil
        self.insertionAnimation = insertionAnimation
        self.removalAnimation = removalAnimation
    }

    /// A transition drawn through a ``Transition``'s body.
    init(custom: _AnyTransitionBox, insertionAnimation: Animation?? = nil, removalAnimation: Animation?? = nil) {
        self.insertion = .identity
        self.removal = .identity
        self.custom = custom
        self.insertionAnimation = insertionAnimation
        self.removalAnimation = removalAnimation
    }

    private init(_ effect: Effect) {
        self.init(insertion: effect, removal: effect)
    }

    /// Whether this transition moves its view, as
    /// ``TransitionProperties/hasMotion`` says of a ``Transition``: a moved,
    /// offset or scaled effect does, at either end, and a fade or nothing does
    /// not. A transition with a body of the app's own says for itself.
    var hasMotion: Bool {
        if let custom { return custom.hasMotion }
        return insertion.hasMotion || removal.hasMotion
    }

    /// What this transition plays as here: itself, or — where the environment
    /// reduces motion and it has some — a fade, with its own animation.
    func reducingMotion(in environment: EnvironmentValues) -> Self {
        guard environment.accessibilityReduceMotion, hasMotion else { return self }
        return Self(
            insertion: .opacity, removal: .opacity, insertionAnimation: insertionAnimation,
            removalAnimation: removalAnimation)
    }

    /// Create an instance that type-erases `transition`.
    ///
    /// The built-in transitions erase to the effects they are made of, and
    /// combine as those do; a transition of your own is drawn through its
    /// body — see ``Transition``.
    @MainActor
    public init<T: Transition>(_ transition: T) {
        self = transition._erased
    }
}

// MARK: - The built-in transitions

extension AnyTransition {
    /// Appears and disappears at once.
    public static let identity = AnyTransition(.identity)

    /// Fades in and out — the default, and what a view an `if` puts in or takes
    /// out does without `.transition(_:)`, as in SwiftUI (see
    /// `View.transition(_:)`).
    public static let opacity = AnyTransition(.opacity)

    /// Slides in from `edge`, and back out to it.
    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition(.move(edge: edge))
    }

    /// Slides in from a displacement, and back out to it.
    public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition {
        AnyTransition(.offset(x: x, y: y))
    }

    /// Slides in from the displacement, and back out to it.
    public static func offset(_ offset: CellSize) -> AnyTransition {
        .offset(x: offset.width, y: offset.height)
    }

    /// Grows from `scale` of the view at the anchor, and shrinks back to it.
    ///
    /// A cell grid cannot draw a view smaller than its cells, so the view is
    /// uncovered from the anchor rather than shrunk: `scale` is how much of it
    /// shows when the transition starts, `0` for none. Above `1` it would be a
    /// view drawn larger than its slot, which nothing here can draw, so such
    /// a transition shows the view whole.
    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(.scale(factor: scale, anchor: anchor))
    }

    /// Grows from nothing at the centre, and shrinks back to it.
    public static let scale = AnyTransition.scale(scale: defaultScale)

    /// What ``scale`` scales from: SwiftUI's own value (measured), a hair
    /// above zero so that its transform stays invertible. In whole cells it is
    /// nothing.
    static let defaultScale = 1e-5

    /// In from the leading edge, out to the trailing one — SwiftUI's own
    /// definition of a slide, which is asymmetric on purpose: a row leaving a
    /// list should carry on in the direction it was going, not reverse.
    public static let slide = AnyTransition.asymmetric(
        insertion: .move(edge: .leading), removal: .move(edge: .trailing))

    /// In from `edge` while fading in, and out towards the opposite edge
    /// while fading out — the way a new screen pushes the old one along.
    public static func push(from edge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge.opposite).combined(with: .opacity))
    }

    /// A transition that arrives one way and leaves another.
    ///
    /// Each half keeps the animation it was given: `insertion`'s arrives with
    /// its own, and `removal`'s leaves with its own, as SwiftUI's do
    /// (measured, `Tools/SwiftUIProbes/Transitions/tr1.out` T4).
    public static func asymmetric(
        insertion: AnyTransition, removal: AnyTransition
    ) -> AnyTransition {
        guard insertion.custom == nil, removal.custom == nil else {
            return AnyTransition(
                custom: _AnyTransitionBox(.asymmetric, insertion, removal),
                insertionAnimation: insertion.insertionAnimation, removalAnimation: removal.removalAnimation)
        }
        return AnyTransition(
            insertion: insertion.insertion, removal: removal.removal,
            insertionAnimation: insertion.insertionAnimation, removalAnimation: removal.removalAnimation)
    }

    /// This transition and another, applied together.
    ///
    /// The pair plays as one effect, so each half runs under one animation:
    /// the one this transition names, `nil` included, or else the one
    /// `other` names. SwiftUI runs each part under its own
    /// (`Tools/SwiftUIProbes/Transitions/tr2.out` T12) — a deviation only
    /// where both parts name different animations.
    public func combined(with other: AnyTransition) -> AnyTransition {
        // Spelt out rather than `??`, which on a double optional could as well
        // unwrap one level as choose between two.
        let insertionAnimation = insertionAnimation == nil ? other.insertionAnimation : insertionAnimation
        let removalAnimation = removalAnimation == nil ? other.removalAnimation : removalAnimation
        guard custom == nil, other.custom == nil else {
            return AnyTransition(
                custom: _AnyTransitionBox(.combined, self, other),
                insertionAnimation: insertionAnimation, removalAnimation: removalAnimation)
        }
        return AnyTransition(
            insertion: .combined(insertion, other.insertion),
            removal: .combined(removal, other.removal),
            insertionAnimation: insertionAnimation, removalAnimation: removalAnimation)
    }

    /// This transition, run with a particular animation whatever the change
    /// that caused it was made under — or, with `nil`, with none: the view
    /// then comes and goes at once, even inside `withAnimation`, as SwiftUI's
    /// does (measured, `Tools/SwiftUIProbes/Transitions/tr1.out` T5).
    ///
    /// A half that already names an animation of its own keeps it, as in
    /// SwiftUI, where the animation nearest the view wins (`tr2.out` T9–T11):
    /// `.opacity.animation(.linear(duration: 2)).animation(.linear(duration: 8))`
    /// runs in two seconds, `.opacity.animation(nil).animation(.linear(duration: 8))`
    /// at once, and an `asymmetric` whose insertion has one keeps it while its
    /// removal takes `animation`.
    public func animation(_ animation: Animation?) -> AnyTransition {
        var animated = self
        if insertionAnimation == nil { animated.insertionAnimation = .some(animation) }
        if removalAnimation == nil { animated.removalAnimation = .some(animation) }
        return animated
    }
}

extension Edge {
    /// The edge across from this one.
    var opposite: Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}
