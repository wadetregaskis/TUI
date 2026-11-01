//  🖥️ TUI — A Terminal UI framework for Swift
//  FormStyle+Variants.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

extension FormStyle {

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any FormStyle` existential so ``makeBody(configuration:)`` can return
    /// its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(
            observingStyleBody(of: Self.self, kind: .styleRender, context: context) {
                makeBody(configuration: configuration)
            }, context: context)
    }
}

// MARK: - Built-in Form Styles

/// The default form style: **columns** in TUI (the classic macOS form layout),
/// matching how `automatic` resolves on macOS.
///
/// `Equatable` for the reason given under ``FormStyle``: a memo below a value the
/// render cache cannot compare declines to cache.
public struct AutomaticFormStyle: FormStyle, Equatable {
    /// The form, laid out in this style — what a style composing this one
    /// draws. ``Form`` lays a built-in style out itself, reading the rows out
    /// of the content, which it can do through the configuration's erasure.
    public func makeBody(configuration: Configuration) -> some View {
        Form(configuration).formStyle(self)
    }

    /// Creates an automatic form style.
    public init() {}
}

/// A form style that aligns labels in a right-justified column against a shared
/// pillar of whitespace, with controls left-aligned after it — the classic macOS
/// "Settings" look.
///
/// `Equatable` on the same terms as ``AutomaticFormStyle``. Laying out identically
/// to it does not make it compare equal to it — see ``FormStyle``.
public struct ColumnsFormStyle: FormStyle, Equatable {
    /// The form, laid out in this style — what a style composing this one
    /// draws. ``Form`` lays a built-in style out itself, reading the rows out
    /// of the content, which it can do through the configuration's erasure.
    public func makeBody(configuration: Configuration) -> some View {
        Form(configuration).formStyle(self)
    }

    /// Creates a columns form style.
    public init() {}
}

/// A form style that draws each ``Section`` as a bordered group with its title —
/// the grouped (iOS-style) layout — and spreads each field row across it, as
/// SwiftUI's does: the label at the leading edge, a fixed value at the trailing
/// edge, a field or a slider from 45% of the row. A `Toggle` with its own label
/// is spread the same way: the label at the leading edge, the checkbox at the
/// trailing one.
///
/// `Equatable` on the same terms as ``AutomaticFormStyle``, and this is the half
/// that earns the cross-type comparison: replacing it with either of the others
/// takes the section borders away.
public struct GroupedFormStyle: FormStyle, Equatable {
    /// The form, laid out in this style — what a style composing this one
    /// draws. ``Form`` lays a built-in style out itself, reading the rows out
    /// of the content, which it can do through the configuration's erasure.
    public func makeBody(configuration: Configuration) -> some View {
        Form(configuration).formStyle(self)
    }

    /// Creates a grouped form style.
    public init() {}
}

// MARK: - FormStyle Static Accessors

extension FormStyle where Self == AutomaticFormStyle {
    /// The default form style — **columns** in TUI (macOS convention).
    public static var automatic: AutomaticFormStyle { AutomaticFormStyle() }
}

extension FormStyle where Self == ColumnsFormStyle {
    /// A form style with labels right-aligned to a shared pillar (macOS form).
    public static var columns: ColumnsFormStyle { ColumnsFormStyle() }
}

extension FormStyle where Self == GroupedFormStyle {
    /// A form style that draws each section as a bordered group.
    public static var grouped: GroupedFormStyle { GroupedFormStyle() }
}

// MARK: - Environment

/// Environment key for the form style.
private struct FormStyleKey: EnvironmentKey {
    static var defaultValue: StyleChain<any FormStyle> { StyleChain(AutomaticFormStyle()) }
}

extension EnvironmentValues {
    /// The form style for this environment.
    ///
    /// Controls how ``Form`` views render. Set via the
    /// ``View/formStyle(_:)`` modifier. Default: ``AutomaticFormStyle``
    /// (columns).
    ///
    /// The built-in styles are `Equatable` so that a memo below one can still
    /// store — see ``FormStyle`` for why the render cache has to ask.
    public var formStyle: any FormStyle {
        get { self[FormStyleKey.self].style }
        set { self[FormStyleKey.self] = self[FormStyleKey.self].pushing(newValue) }
    }

    /// The style in force and the ones outside it — what ``Form/init(_:)``
    /// inside a custom style's body lays out with. See ``StyleChain``.
    var formStyleChain: StyleChain<any FormStyle> {
        get { self[FormStyleKey.self] }
        set { self[FormStyleKey.self] = newValue }
    }
}

// MARK: - Form Style Modifier

extension View {
    /// Sets the style for forms within this view.
    ///
    /// ```swift
    /// Form { … }
    ///     .formStyle(.grouped)
    /// ```
    ///
    /// - Parameter style: The form style to apply.
    /// - Returns: A view whose forms use the specified style.
    public func formStyle<S: FormStyle>(_ style: S) -> some View {
        environment(\.formStyle, style)
    }
}
