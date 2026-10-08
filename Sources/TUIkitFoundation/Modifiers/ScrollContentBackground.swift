//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollContentBackground.swift
//
//  `scrollContentBackground(_:)`: whether the scrollable views in a subtree
//  paint a background of their own.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Environment

private struct ScrollContentBackgroundKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether the scrollable views in this subtree paint a background of their
    /// own — see ``TUIkit/View/scrollContentBackground(_:)``.
    ///
    /// Internal: SwiftUI exposes the modifier, not an environment value.
    var scrollContentBackground: Visibility {
        get { self[ScrollContentBackgroundKey.self] }
        set { self[ScrollContentBackgroundKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Specifies the visibility of the background for scrollable views within
    /// this view. Matches SwiftUI's modifier of the same name.
    ///
    /// The scrollable views are ``ScrollView``, ``List``, ``Table``, ``Form``
    /// and ``TextEditor``. None of them draws a background of its own here —
    /// a `List` paints its row highlights and nothing behind them — so
    /// `.automatic` and `.hidden` leave them as they are, and SwiftUI's
    /// commonest use draws as it does there:
    ///
    /// ```swift
    /// List { … }
    ///     .scrollContentBackground(.hidden)
    ///     .background(Color.blue)
    /// ```
    ///
    /// `.visible` paints the palette's background (`.windowBackground`) behind
    /// the whole view, its border and scroll bars included: the page's own
    /// colour, which over a coloured container is what makes the scrollable
    /// opaque. That is the macOS reading too, where `.visible` is what makes a
    /// `ScrollView` draw the background a `List` draws by default.
    ///
    /// A `TextEditor` under a ``TextEditorStyle`` of the app's own is drawn by
    /// that style's body, in the editor's place, and paints what that body
    /// paints: the setting reaches the two built-in styles' editor.
    ///
    /// - Parameter visibility: The visibility to use for the background.
    /// - Returns: A view whose scrollables paint, or do not paint, a
    ///   background.
    public func scrollContentBackground(_ visibility: Visibility) -> some View {
        environment(\.scrollContentBackground, visibility)
    }

    /// This scrollable, behind which the palette's background is painted when
    /// ``EnvironmentValues/scrollContentBackground`` is `.visible`. Each of the
    /// five scrollables applies it in its body.
    ///
    /// - Parameter reads: `false` for a scroll view that is framework chrome
    ///   (``ScrollView/asChrome()``), which never paints. Applied either way,
    ///   so the scrollable's body has one shape whatever it is.
    func paintingScrollContentBackground(
        reads: Bool = true
    ) -> ModifiedView<Self, ScrollContentBackgroundModifier> {
        modifier(ScrollContentBackgroundModifier(reads: reads))
    }
}

/// Paints the palette's background behind a scrollable whose environment asks
/// for its background to be `.visible` — and nothing otherwise, at the cost of
/// one environment read.
///
/// Applied by the scrollables themselves; apps use
/// ``TUIkit/View/scrollContentBackground(_:)``.
struct ScrollContentBackgroundModifier: BufferModifier, Equatable {
    /// Whether the environment is read at all — see
    /// ``TUIkit/View/paintingScrollContentBackground(reads:)``.
    let reads: Bool

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        _modify(buffer: buffer, context: context, owner: Self.self)
    }

    func _modify(buffer: FrameBuffer, context: RenderContext, owner: Any.Type) -> FrameBuffer {
        guard reads, context.environment.scrollContentBackground == .visible else { return buffer }
        // The `.background(.windowBackground)` fill, keyed on the same owner, so
        // a palette change inside `withAnimation` moves as any background's does.
        return BackgroundModifier(style: WindowBackgroundShapeStyle())
            ._modify(buffer: buffer, context: context, owner: owner)
    }
}
