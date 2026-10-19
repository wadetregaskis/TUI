//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Identity.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Splices a keyed step into the wrapped content's structural identity, so
/// changing the key gives the subtree a fresh identity. It carries no visual
/// effect (`modify` returns the buffer unchanged) — only `adjustContext`
/// re-keys, and because `ModifiedView` calls `adjustContext` on **both** the
/// measure and render passes, `@State` keys off the same spliced identity in
/// each, preserving measure/render alignment.
///
/// Generic over the id, which it keeps as its own type rather than as an
/// `AnyHashable`: the view's value hash reads it as the plain value it is,
/// where a box would hash a pointer.
private struct _IDModifier<ID: Hashable>: BufferModifier {
    /// Its content stays where it is laid out — an identity moves nothing — so a guide inside it
    /// passes unmoved (``BufferModifier/_keepsContentGeometry``).
    static var _keepsContentGeometry: Bool { true }

    let key: String

    /// The id itself, which ``key`` is the string of: what a scroll view
    /// reports back to a `.scrollPosition(id:)` binding when this view is the
    /// one it shows.
    let id: ID

    /// The witness that makes this key readable from outside the modified
    /// view, where `adjustContext` alone leaves no trace of it: a container
    /// sees only the child's positional step, since the re-keyed step is the
    /// one BELOW. `ScrollViewProxy.scrollTo(_:anchor:)` is what reads it.
    var _explicitIDKey: String? { key }

    /// The id, for the read-back (``_explicitIDKey`` is for the seek).
    var _explicitID: AnyHashable? { AnyHashable(id) }

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        buffer
    }

    func adjustContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(erasedType: Self.self, key: key)
    }
}

extension View {
    /// Binds an explicit identity to this view.
    ///
    /// Mirrors SwiftUI's `id(_:)`. When `id` changes, the view is treated as a
    /// *different* view: its `@State` resets to its initial values, its
    /// `onAppear`/`task` fire again, and its cached buffer is discarded — all of
    /// which fall out automatically from the identity change, since `@State`,
    /// lifecycle tokens, and the render cache all key off the structural
    /// identity path.
    ///
    /// ```swift
    /// ProfileView(user: user)
    ///     .id(user.id)   // switching users restarts the subtree
    /// ```
    ///
    /// - Note: `.id()` re-keys only what sits *below* it in the modifier chain,
    ///   matching SwiftUI: put it outermost (`content.onAppear{…}.id(k)`) so the
    ///   whole subtree, including its lifecycle, resets on a key change. The
    ///   `Hashable` id is collapsed to `String(describing:)` for the key (as
    ///   `ForEach` does), so two distinct values with identical descriptions
    ///   would alias one identity.
    ///
    /// - Note: The key is also the tag
    ///   ``ScrollViewProxy/scrollTo(_:anchor:)`` seeks by, so tagging a row of
    ///   a scroll view's content stack makes it a scroll target — the shape
    ///   SwiftUI's own `ScrollViewReader` example is written in.
    ///
    /// - Parameter id: A value that identifies this view.
    /// - Returns: A view with the given identity bound to it.
    public func id<ID: Hashable>(_ id: ID) -> some View {
        modifier(_IDModifier(key: identityKey(id), id: id))
    }
}
