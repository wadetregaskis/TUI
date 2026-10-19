//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Environment Modifier

/// A modifier that injects a value into the environment for child views.
///
/// `EnvironmentModifier` conforms to both `View` and ``Renderable``.
/// Because ``renderToBuffer(_:context:)`` checks `Renderable` first,
/// the `body` property below is **never called during rendering**.
/// It exists only to satisfy the `View` protocol requirement.
/// All actual work happens in `renderToBuffer(context:)`.
public struct EnvironmentModifier<Content: View, V>: View {
    // The key path, the content, then the value: the per-pass memos key a
    // view by a hash of its bytes, and padding is whatever the memory held
    // before — skipped by the hash, where a type with none is plain words.
    // The content first left a gap before the word-aligned key path whatever
    // its size; here only a word-aligned value after an odd-sized content can
    // leave one, and most environment values are byte-aligned (flags, colours,
    // enums). `ContainerLayoutPaddingTests`.

    /// The key path to modify.
    public let keyPath: WritableKeyPath<EnvironmentValues, V>

    /// The content view.
    public let content: Content

    /// The value to inject.
    public let value: V

    /// Creates a new environment modifier.
    public init(content: Content, keyPath: WritableKeyPath<EnvironmentValues, V>, value: V) {
        self.content = content
        self.keyPath = keyPath
        self.value = value
    }
    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View {
        content
    }
}

extension EnvironmentModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: contentContext(context))
    }

    /// The context the content is drawn in: `context` with the value written
    /// — and noted, for the caches below (``noteEnvironmentChange``). For the
    /// render, and for a caller that takes the content apart instead of
    /// drawing it whole: a `List` reading the rows of a `Section` this wraps.
    package func contentContext(_ context: RenderContext) -> RenderContext {
        // Create modified environment and render content with it.
        // The modified context carries the environment through the render tree —
        // no global state sync needed.
        let uncomparable = noteEnvironmentChange(value, at: keyPath, context: context)
        var modifiedEnvironment = context.environment.setting(keyPath, to: value)
        if uncomparable { modifiedEnvironment.hasUncomparableEnvironmentValue = true }
        // Derived from `context.environment` one line up, so the services are
        // the same two objects and the mirrors need no re-deriving.
        var modifiedContext = context.withDerivedEnvironment(modifiedEnvironment)
        modifiedContext.environmentApplicationDepth += 1
        return modifiedContext
    }
}

// MARK: - Cache Coherency

/// Drops cached buffers below an environment modifier when the value it
/// injects at `keyPath` has changed since the last pass — for
/// ``EnvironmentModifier`` and ``TransformEnvironmentModifier`` alike, the one
/// place it is implemented.
///
/// A free function generic over the VALUE alone, so neither caller has to
/// name the other's type to reach it: a transform calling a static on
/// `EnvironmentModifier<Content, V>` would instantiate that type's metadata —
/// a hashed runtime lookup — on every visit, for nothing.
///
/// The render cache keys on identity, view value and size — not on the
/// environment. That is what makes it cheap, and it is why a **scoped**
/// style change is invisible to it: `.foregroundStyle(x)` applied *above* an
/// `.equatable()` boundary leaves the view value identical, so the lookup
/// hits and hands back the buffer rendered under the old style. Wrong
/// pixels, not merely stale work.
///
/// Detecting it here rather than in the key is the cheaper half of the
/// trade: one comparison per environment modifier per pass, against a
/// dictionary walk per memoized view per pass. The `@State`-driven case was
/// already covered by accident (the declaring view's identity is an ancestor
/// of the cached one, so `clearAffected(by:)` reaches it); this covers the
/// rest — a preference written by a sibling, an `@AppStorage` value, a
/// binding threaded down from somewhere that is not an ancestor.
///
/// A value that is not `Equatable` cannot be compared at all, so the subtree
/// declares itself cache-unsafe instead: `EquatableView` already refuses to
/// store a buffer whose render tripped the tracker. Memoization is lost
/// under such a modifier, which is a performance cost rather than a
/// correctness one — the right way round.
///
/// - Parameters:
///   - value: The value the modifier injects.
///   - keyPath: Where it injects it — the slot it is noted under.
///   - context: The modifier's own context: its identity, its depth, and the
///     environment ABOVE it, whose tracker an uncomparable value trips.
/// - Returns: `true` when the injected value is uncomparable, so the caller
///   marks the environment it passes down.
private func noteEnvironmentChange<V>(
    _ value: V, at keyPath: WritableKeyPath<EnvironmentValues, V>, context: RenderContext
) -> Bool {
    guard let cache = context.renderCache else { return false }
    // A palette is noted as every other keeper of one compares it —
    // `ComparablePalette`: by value where it is `Equatable`, through its
    // derivation for the framework's own wrappers, by its id otherwise, as
    // `Palette`'s documentation asks of a palette whose colours change. Noted
    // raw, a palette with no `Equatable` of its own — the Theming guide's
    // shape, and the Terminal palette once the environment has grounded it —
    // answered `.incomparable`, and `.palette(_:)` turned off every memo below
    // it for good. `.theme(_:)` and the render loop's snapshot already compare
    // it this way.
    //
    // Handed over as the expression, not a value made here: the parameter
    // is an autoclosure, so the cast and the `Any` box happen only on the
    // visits that compare — once a pass — and not on the repeat visits of
    // two-pass layout, which the once-per-pass check answers without them.
    switch cache.noteAppliedEnvironment(
        (value as? any Palette).map(ComparablePalette.init) ?? value, identity: context.identity,
        keyPath: keyPath, depth: context.environmentApplicationDepth)
    {
    case .changed:
        cache.clearAffected(by: context.identity)
    case .incomparable:
        // Two routes, because a memoizing view can sit on either side of
        // this modifier. Below it: the tracker exists by then, and
        // `EquatableView` already declines to store when it is tripped.
        // Above it — the usual arrangement, `.equatable().foregroundStyle(…)`
        // — there is no tracker here yet, so the signal has to travel *down*
        // the environment instead. Hence the flag as well.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return true
    case .first, .unchanged:
        break
    }
    return false
}

// MARK: - Layoutable

extension EnvironmentModifier: Layoutable {
    /// Measures the wrapped content under the modified environment without
    /// rendering it.
    ///
    /// Without this conformance, `measureChild` would fall through to its
    /// render-to-measure fallback (the view is `Renderable` and its body
    /// returns the same content — `V.Body == Content`, which is also
    /// `View`, so it would still hit the fallback). That fallback renders
    /// the content to measure it (historically *twice* per measure — a
    /// second render at `naturalWidth + 8` probed flexibility, since
    /// retired). With `Image` typically wrapped in several environment
    /// modifiers (character set, colour mode, dithering, placeholder, …)
    /// and each layout pass touching it multiple times, that escalates
    /// into many ASCIIConverter runs per frame — the demo's "twelve-second
    /// render" was almost entirely re-running the ASCII conversion to
    /// *measure* the same image.
    ///
    /// Forwarding the measurement to the content under the modified
    /// environment matches the semantics of the render path and skips
    /// rendering the (possibly expensive) content to measure it.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Also on the measure walk. The measure memo has the same environment
        // blind spot as the buffer cache, and measurement runs first, so a
        // change noticed only on the render walk would already have served a
        // stale size. The once-per-pass short circuit in
        // `noteAppliedEnvironment` is what makes this affordable: two-pass
        // layout visits the same modifier many times per frame. The render's
        // own context, so the two cannot describe different environments.
        measureChild(content, proposal: proposal, context: contentContext(context))
    }
}

// MARK: - Transform Environment Modifier

/// A modifier that CHANGES an environment value rather than replacing it.
///
/// The difference from ``EnvironmentModifier`` is entirely one of timing: a set
/// value is known when the view is built, a transformed one cannot be, because
/// it is a function of whatever the enclosing environment happens to hold when
/// this subtree renders. So the value is computed here, at render time —
/// read, transformed and written back through ONE projection of the key path —
/// and noted for the render cache by the same function `EnvironmentModifier`
/// notes with, so the cache is kept honest about it in one place.
///
/// Done inline rather than by rendering an `EnvironmentModifier` as a child:
/// no extra node in the identity path, no second dispatch. Nor by building one
/// and calling its methods, which is what this did: that copied the content
/// into a new modifier on every visit, and read the value through the key
/// path and then wrote it through it again — two projections, the second
/// re-reading the value before its write — where one does both.
public struct TransformEnvironmentModifier<Content: View, V>: View {
    // The two word-sized fields, then the content last, so nothing follows it
    // whatever its size: the content first left seven undefined bytes before
    // the key path over a scroll view (`ContainerLayoutPaddingTests`), which
    // the per-pass memos' value hash read then and must skip now.

    /// The key path to transform.
    public let keyPath: WritableKeyPath<EnvironmentValues, V>

    /// The transformation to apply to the inherited value.
    public let transform: (inout V) -> Void

    /// The content view.
    public let content: Content

    /// Creates a new transforming environment modifier.
    public init(
        content: Content,
        keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) {
        self.content = content
        self.keyPath = keyPath
        self.transform = transform
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View {
        content
    }

    /// The context the content is drawn and measured in: `context` with the
    /// transform applied — exactly what an ``EnvironmentModifier`` injecting
    /// the transformed value makes of it.
    ///
    /// Run on both walks, and it must produce the same value on each or the
    /// measured size would describe a different environment than the drawn one.
    /// It does, because the only inputs are the inherited value and the
    /// caller's closure.
    ///
    /// The value is written into the copy before it is noted, where an
    /// `EnvironmentModifier` notes first and writes after. The order cannot be
    /// seen: the note reads only `context` — the environment above — never
    /// the copy, and the key path's setter writes only the copy.
    ///
    /// A key path that reaches through a class — `\.model.count`, with the
    /// model an object in the environment — is copied out and written back
    /// instead. Through ONE access, the access to the object's property would
    /// be held across the caller's closure, and a closure that reads that same
    /// property (`{ $0 = model.count + 1 }`) would trap for exclusivity.
    package func transformed(_ context: RenderContext) -> RenderContext {
        var environment = context.environment
        let value: V
        if keyPath is ReferenceWritableKeyPath<EnvironmentValues, V> {
            var copy = environment[keyPath: keyPath]
            transform(&copy)
            environment[keyPath: keyPath] = copy
            value = copy
        } else {
            value = applying(transform, to: &environment[keyPath: keyPath])
        }
        if noteEnvironmentChange(value, at: keyPath, context: context) {
            environment.hasUncomparableEnvironmentValue = true
        }
        // Derived from `context.environment`, as `EnvironmentModifier`'s is.
        var modified = context.withDerivedEnvironment(environment)
        modified.environmentApplicationDepth += 1
        return modified
    }
}

/// `transform` applied to `value` in place, and the value it leaves.
///
/// What lets ``TransformEnvironmentModifier`` read, transform and write back
/// through ONE access to `&environment[keyPath:]` and still have the value
/// to note: the copy is taken inside that access.
private func applying<V>(_ transform: (inout V) -> Void, to value: inout V) -> V {
    transform(&value)
    return value
}

extension TransformEnvironmentModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: transformed(context))
    }
}

extension TransformEnvironmentModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: transformed(context))
    }
}

// MARK: - Uncomparable Environment Values

private struct UncomparableEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FocusSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct KeepsHiddenStateKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the state of a branch a conditional turns away from is kept
    /// rather than dropped — set by `View.keepsStateWhileHidden(_:)` for its
    /// content, and read by ``ConditionalView``, which otherwise drops the
    /// branch it left the moment it flips, as SwiftUI gives a view inserted
    /// again fresh state.
    package var keepsHiddenState: Bool {
        get { self[KeepsHiddenStateKey.self] }
        set { self[KeepsHiddenStateKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Whether a control rendered here should stay OUT of the focus ring while
    /// everything else about it goes on working.
    ///
    /// Set by `View.hidden()`. A hidden view is not somewhere Tab can land — it
    /// has no picture to land on — but it is otherwise alive: its `@State`
    /// persists, its `.onAppear` fires, its `.keyboardShortcut` still works (a
    /// hidden button holding a shortcut is a real SwiftUI idiom), and a
    /// `.sheet` it presents still presents.
    ///
    /// This is why `.hidden()` cannot use `isolatedForBackground()`, which
    /// swaps the focus manager wholesale: a presentation's own section
    /// registration and `grabInput` would go to the throwaway too, and the
    /// sheet would draw with nothing able to reach it. The flag separates the
    /// two — individual controls consult it, SECTIONS ignore it — which is the
    /// distinction "hidden" needs and "inert" (`View.dimmed()`) deliberately
    /// does not.
    ///
    /// `@usableFromInline`: the `@inlinable` `FocusRegistration.register(context:handler:focusID:)`
    /// in TUIkit reads it (module split step A3).
    @usableFromInline
    package var isFocusSuppressed: Bool {
        get { self[FocusSuppressedKey.self] }
        set { self[FocusSuppressedKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Whether some ancestor injected an environment value that is not
    /// `Equatable`.
    ///
    /// Change detection at the modifier is what lets the render cache key stay
    /// free of the environment (see `EnvironmentModifier.noteEnvironmentChange`),
    /// and it needs a comparison. A value that cannot be compared could change
    /// under a memoized subtree with nothing to notice, so subtrees below one
    /// decline to cache — losing memoization there, rather than serving pixels
    /// rendered under a value that has since changed.
    public var hasUncomparableEnvironmentValue: Bool {
        get { self[UncomparableEnvironmentKey.self] }
        set { self[UncomparableEnvironmentKey.self] = newValue }
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension EnvironmentModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<Inner: View>(_ view: Inner) -> any View {
        EnvironmentModifier<Inner, V>(content: view, keyPath: keyPath, value: value)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension EnvironmentModifier: ChildViewProvider where Content: ChildViewProvider {}

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension TransformEnvironmentModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<Inner: View>(_ view: Inner) -> any View {
        TransformEnvironmentModifier<Inner, V>(content: view, keyPath: keyPath, transform: transform)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension TransformEnvironmentModifier: ChildViewProvider where Content: ChildViewProvider {}

// MARK: - Removal Transitions

/// Each draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension EnvironmentModifier: DrawsContentUnchanged {}
extension TransformEnvironmentModifier: DrawsContentUnchanged {}

/// Each measures its content under the value it writes — see
/// ``ContentContextStating``.
extension EnvironmentModifier: ContentContextStating {
    package func contentLayoutContext(_ context: RenderContext) -> RenderContext { contentContext(context) }
}
extension TransformEnvironmentModifier: ContentContextStating {
    package func contentLayoutContext(_ context: RenderContext) -> RenderContext { transformed(context) }
}
