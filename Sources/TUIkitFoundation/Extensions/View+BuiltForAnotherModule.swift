//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+BuiltForAnotherModule.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

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
/// type is concrete. Step B7's carve of TUIkitTextInput met five such
/// modifiers: `border`, `id`, `foregroundStyle`, `focused` and `onAppear`, whose
/// results name `_BorderRings`, `_IDModifier`, `_StyleEnvironmentView`,
/// `_FocusedModifier` and `OnAppearModifier`. TUIkitPresentation names a sixth,
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
    /// Draws this view with a border of `style` (`border(style:)`), at
    /// `context`'s identity.
    ///
    /// For a view of another module that draws a border inside its own
    /// `renderToBuffer(context:)`, as a styled text field does: where it named
    /// `border(style:)` itself, the lookup sat at the top of the function, so
    /// every field paid it on every frame, bordered or not.
    package func renderBordered(style: BorderStyle?, context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(border(style: style), context: context)
    }

    /// Measures this view with a border of `style` (`border(style:)`): the
    /// measure twin of ``renderBordered(style:context:)``.
    package func measureBordered(style: BorderStyle?, proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(border(style: style), proposal: proposal, context: context)
    }

    /// This view with a border (`border()`), erased.
    package func erasedBorder() -> AnyView {
        AnyView(border())
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
    /// For a presentation's background view (TUIkitPresentation's
    /// `presentationBackground(alignment:content:)`), which the presenter puts
    /// behind the presented content on every frame the presentation is open.
    package func erasedBackground(alignment: Alignment, _ background: AnyView) -> AnyView {
        AnyView(self.background(alignment: alignment) { background })
    }
}
