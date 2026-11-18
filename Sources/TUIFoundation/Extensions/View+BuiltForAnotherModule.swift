//  🖥️ TUI — A Terminal UI framework for Swift
//  View+BuiltForAnotherModule.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling
import TUIView

// MARK: - Views built here for another module of the package

/// Each of these applies one of this module's public modifiers whose `some View`
/// result names a type only this module can see, and hands the result back in a
/// form another module of the package can hold: drawn or measured
/// (``View/renderBordered(style:context:)``), or erased to an ``AnyView``.
///
/// Built in that other module, such a modifier's result is opaque there: Swift
/// substitutes an opaque result's underlying type only in a client that can see
/// every type it names, so the client asks the runtime for the type, and for its
/// `View` conformance, which the runtime finds by demangling its name each time
/// it is asked (CONTRIBUTING.md, "Crossing a module boundary"). Built here, the
/// type is concrete. Step B7's carve of TUITextInput met five such
/// modifiers: `border`, `id`, `foregroundStyle`, `focused` and `onAppear`, whose
/// results name `_BorderRings`, `_IDModifier`, `_StyleEnvironmentView`,
/// `_FocusedModifier` and `OnAppearModifier`. TUIPresentation names a sixth,
/// `background(alignment:content:)`, whose result names
/// `BackgroundLayerModifier`: a lookup on every frame of a presentation with a
/// background view since step B5 carved the presentations out, which the
/// crossing predictor flagged at step C1. Widening those types, or making
/// the modifiers `@inlinable`, would let every app see through the same public
/// modifiers too, which changes the app's own code; these entry points change
/// nothing outside the package.
///
/// Each is generic over the view it is given, so it is called unspecialised
/// from another module, and the erasing ones box their result: use them on a
/// path where that costs less than the lookup it saves, which is every path the
/// lookup would run on.
extension View {
    /// Draws this view in the framework chrome's box of `style` — the line and
    /// a blank cell either side inside it (`bordered(…, insetsContent: true)`,
    /// which an app's `border(style:)` no longer adds) — at `context`'s
    /// identity.
    ///
    /// For a view of another module that draws a border inside its own
    /// `renderToBuffer(context:)`, as a styled text field does: where it named
    /// `border(style:)` itself, the lookup sat at the top of the function, so
    /// every field paid it on every frame, bordered or not.
    package func renderBordered(style: BorderStyle?, context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(chromeBox(style: style), context: context)
    }

    /// Measures this view in the framework chrome's box of `style`: the
    /// measure twin of ``renderBordered(style:context:)``.
    package func measureBordered(style: BorderStyle?, proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(chromeBox(style: style), proposal: proposal, context: context)
    }

    /// This view in the framework chrome's box, erased: a grouped `Form`'s
    /// section.
    package func erasedBorder() -> AnyView {
        AnyView(chromeBox(style: nil))
    }

    /// The framework chrome's box: the line, and the blank cell either side
    /// inside it that `.border()` drew until 2026-11-17 and the chrome keeps.
    private func chromeBox(style: BorderStyle?) -> some View {
        bordered(style: style, colour: nil, width: 1, insetsContent: true)
    }

    /// This view identified by `id` (`id(_:)`), erased.
    package func erasedID(_ id: String) -> AnyView {
        AnyView(self.id(id))
    }

    /// This view with `color` as its foreground style (`foregroundStyle(_:)`),
    /// erased.
    package func erasedForegroundStyle(_ color: Color) -> AnyView {
        AnyView(foregroundStyle(color))
    }

    /// This view with its focus bound to `condition` (`focused(_:)`), erased.
    package func erasedFocused(_ condition: FocusState<Bool>.Binding) -> AnyView {
        AnyView(focused(condition))
    }

    /// This view running `action` when it appears (`onAppear(perform:)`),
    /// erased.
    package func erasedOnAppear(perform action: @escaping () -> Void) -> AnyView {
        AnyView(onAppear(perform: action))
    }

    /// This view with `background` behind it, placed by `alignment`
    /// (`background(alignment:content:)`), erased.
    ///
    /// For a presentation's background view (TUIPresentation's
    /// `presentationBackground(alignment:content:)`), which the presenter puts
    /// behind the presented content on every frame the presentation is open.
    package func erasedBackground(alignment: Alignment, _ background: AnyView) -> AnyView {
        AnyView(self.background(alignment: alignment) { background })
    }
}
