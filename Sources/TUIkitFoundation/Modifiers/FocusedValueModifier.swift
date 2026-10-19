//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusedValueModifier.swift
//
//  `.focusedValue(_:_:)` and `.focusedSceneValue(_:_:)`: publishing a value
//  for `@FocusedValue` readers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkitCore
import TUIkitView

// MARK: - Modifiers

extension View {
    /// Modifies this view by injecting a value that you provide for use by
    /// other views whose state depends on the focused view hierarchy.
    ///
    /// Mirrors SwiftUI's `focusedValue(_:_:)`. A ``FocusedValue`` reader sees
    /// the value while the focus is on this view or anywhere inside it.
    ///
    /// ```swift
    /// List(notes, selection: $selection) { Text($0.title) }
    ///     .focusedValue(\.selectedNote, $selectedNote)
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: The key path to associate `value` with when adding it to
    ///     the existing table of exported focus values.
    ///   - value: The focus value to export.
    /// - Returns: A modified representation of this view.
    public func focusedValue<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value
    ) -> some View {
        _FocusedValueModifier(
            content: self, publishing: KeyPathPublishing(keyPath: keyPath, value: value),
            isScene: false)
    }

    /// Creates a new view that exposes the provided value to other views
    /// whose state depends on the focused view hierarchy.
    ///
    /// Mirrors SwiftUI's `focusedValue(_:_:)`. Pass `nil` when no value is
    /// currently available: a reader then sees what an enclosing view
    /// publishes, if anything.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to associate `value` with when adding it to
    ///     the existing table of exported focus values.
    ///   - value: The focus value to export, or `nil` if no value is currently
    ///     available.
    /// - Returns: A modified representation of this view.
    public func focusedValue<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value?
    ) -> some View {
        _FocusedValueModifier(
            content: self, publishing: KeyPathPublishing(keyPath: keyPath, value: value),
            isScene: false)
    }

    /// Sets the focused value for the given object type.
    ///
    /// Mirrors SwiftUI's `focusedValue(_:)`. Read it with
    /// `@FocusedValue(Model.self)`.
    ///
    /// - Parameter object: The `@Observable` object to publish, or `nil`.
    /// - Returns: A modified representation of this view.
    public func focusedValue<T>(_ object: T?) -> some View where T: AnyObject, T: Observable {
        _FocusedValueModifier(content: self, publishing: ObjectPublishing(object: object), isScene: false)
    }

    /// Modifies this view by injecting a value that you provide for use by
    /// other views whose state depends on the focused scene.
    ///
    /// Mirrors SwiftUI's `focusedSceneValue(_:_:)`. A ``FocusedValue`` reader
    /// sees the value wherever the focus is — a terminal app is one scene —
    /// unless a view on the focus's path publishes the same key, which wins.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to associate `value` with when adding it to
    ///     the existing table of published focus values.
    ///   - value: The focus value to publish.
    /// - Returns: A modified representation of this view.
    public func focusedSceneValue<T>(
        _ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T
    ) -> some View {
        _FocusedValueModifier(
            content: self, publishing: KeyPathPublishing(keyPath: keyPath, value: value),
            isScene: true)
    }

    /// Creates a new view that exposes the provided value to other views
    /// whose state depends on the active scene.
    ///
    /// Mirrors SwiftUI's `focusedSceneValue(_:_:)`.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to associate `value` with when adding it to
    ///     the existing table of published focus values.
    ///   - value: The focus value to publish, or `nil` if no value is
    ///     currently available.
    /// - Returns: A modified representation of this view.
    public func focusedSceneValue<T>(
        _ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T?
    ) -> some View {
        _FocusedValueModifier(
            content: self, publishing: KeyPathPublishing(keyPath: keyPath, value: value),
            isScene: true)
    }

    /// Sets the focused scene value for the given object type.
    ///
    /// Mirrors SwiftUI's `focusedSceneValue(_:)`. Read it with
    /// `@FocusedValue(Model.self)`.
    ///
    /// - Parameter object: The `@Observable` object to publish, or `nil`.
    /// - Returns: A modified representation of this view.
    public func focusedSceneValue<T>(_ object: T?) -> some View where T: AnyObject, T: Observable {
        _FocusedValueModifier(content: self, publishing: ObjectPublishing(object: object), isScene: true)
    }
}

// MARK: - What a modifier publishes

/// What one modifier writes into its table.
protocol FocusedValuePublishing {
    func write(into table: inout FocusedValues)
}

/// A value under a key path of the app's own.
struct KeyPathPublishing<Value>: FocusedValuePublishing {
    let keyPath: WritableKeyPath<FocusedValues, Value?>
    let value: Value?

    func write(into table: inout FocusedValues) {
        table[keyPath: keyPath] = value
    }
}

/// An `@Observable` object, under its type.
struct ObjectPublishing<Object: AnyObject>: FocusedValuePublishing {
    let object: Object?

    func write(into table: inout FocusedValues) {
        table[FocusedObjectKey<Object>.self] = object
    }
}

// MARK: - The modifier

/// Publishes its table each render, and draws its content unchanged at its
/// own identity — the identity a reader's focus path is tested against.
struct _FocusedValueModifier<Content: View, Publishing: FocusedValuePublishing>: View {
    let content: Content
    let publishing: Publishing
    let isScene: Bool

    var body: Never {
        fatalError("_FocusedValueModifier renders via Renderable")
    }
}

extension _FocusedValueModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { publish(context: context) }
        return TUIkitView.renderToBuffer(content, context: context)
    }

    /// Publishes this frame's table, and says what a value-memoizing ancestor
    /// may do about it.
    ///
    /// A publication is per-frame presence: the registry keeps last frame's
    /// tables only until this frame's walk replaces them. So a served subtree
    /// must publish again, which it can — what it published is a value, and it
    /// is the same value on every hit, since a hit is a frame on which nothing
    /// the subtree's buffer depends on changed.
    private func publish(context: RenderContext) {
        var table = FocusedValues()
        publishing.write(into: &table)
        guard !table.isEmpty else { return }
        let identity = context.identity
        let isScene = isScene
        FocusedValueRegistrar.post(table, by: identity, isScene: isScene, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        // Built only while a memo records, so the live path allocates no second
        // closure. The publisher's identity is captured: a hit is served at the
        // place the subtree was recorded, and a reader's focus path is tested
        // against where the modifier drew.
        journal.append(
            EffectJournal.Entry(
                kind: FocusedValueRegistrar.kind, channelToken: context.environment.keyChannelToken
            ) { replay in
                FocusedValueRegistrar.post(table, by: identity, isScene: isScene, context: replay)
            })
    }
}

extension _FocusedValueModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// The one publication `.focusedValue` / `.focusedSceneValue` makes, shared by
/// the live render and by a value memo replaying it — see `EffectJournal`.
enum FocusedValueRegistrar {
    /// The journal kind of a focused-value publication.
    static let kind = EffectJournal.Kind("focusedValue")

    /// Posts `table` into the registry of `context`'s focus manager.
    ///
    /// Refuses the two throwaway managers — a dimmed backdrop's and a focus
    /// probe's — whose renders are pictures of the page, not the page: what
    /// they publish would describe controls nobody can focus.
    @MainActor
    static func post(_ table: FocusedValues, by identity: ViewIdentity, isScene: Bool, context: RenderContext) {
        guard let manager = context.environment.focusManager,
            !manager.isBackdrop, !manager.suppressesAutoFocus
        else { return }
        manager.focusedValues.post(table, by: identity, isScene: isScene)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _FocusedValueModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _FocusedValueModifier: DrawsContentUnchanged {}
/// Measures its content in the context it is given, so an alignment guide
/// inside it is asked through it — see `HandsContentItsContext`.
extension _FocusedValueModifier: HandsContentItsContext {}
