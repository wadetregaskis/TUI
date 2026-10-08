//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldStyle+Variants.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Default

/// The ordinary field: a coloured surface with half-block caps.
///
/// Matches SwiftUI's `.automatic`, and is what a `TextField` or `SecureField`
/// draws with no style applied.
///
/// `Equatable` for the reason given under ``TextFieldStyle``: a memo below a
/// value the render cache cannot compare declines to cache. It holds nothing, so
/// every instance draws a field identically.
public struct DefaultTextFieldStyle: TextFieldStyle, Equatable {
    /// Creates the default text field style.
    public init() {}

    public var drawsFieldSurface: Bool {
        true
    }
}

// MARK: - Plain

/// A field with no surface and no caps — just its text, in place.
///
/// Matches SwiftUI's `.plain`.
///
/// `Equatable` on the same terms as ``DefaultTextFieldStyle``, and this is the
/// half that earns the cross-type comparison: a frame that swaps the two changes
/// the field's width as well as its surface, so the downcast answering "changed"
/// is what keeps a two-cell measurement from being served to a field that no
/// longer has caps.
public struct PlainTextFieldStyle: TextFieldStyle, Equatable {
    /// Creates the plain text field style.
    public init() {}

    public var drawsFieldSurface: Bool {
        false
    }
}

// MARK: - Convenience

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    /// The default field appearance: a surface with capped ends.
    ///
    /// Usable with leading-dot syntax: `.textFieldStyle(.automatic)`.
    public static var automatic: DefaultTextFieldStyle {
        DefaultTextFieldStyle()
    }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    /// A field with no surface and no caps.
    ///
    /// Usable with leading-dot syntax: `.textFieldStyle(.plain)`.
    public static var plain: PlainTextFieldStyle {
        PlainTextFieldStyle()
    }
}

// MARK: - Environment

// MARK: - Bordered

/// A field framed in a box with rounded corners — the plain field inside
/// `╭╮╰╯`, three rows tall.
///
/// Matches SwiftUI's `.roundedBorder`.
public struct RoundedBorderTextFieldStyle: TextFieldStyle, Equatable {
    /// Creates a rounded border text field style.
    public init() {}

    public var drawsFieldSurface: Bool { false }

    public var fieldBorder: BorderStyle? { .rounded }
}

/// A field framed in a box with square corners — the plain field inside
/// `┌┐└┘`, three rows tall.
///
/// Matches SwiftUI's `.squareBorder`.
public struct SquareBorderTextFieldStyle: TextFieldStyle, Equatable {
    /// Creates a square border text field style.
    public init() {}

    public var drawsFieldSurface: Bool { false }

    public var fieldBorder: BorderStyle? { .line }
}

extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    /// A text field style with a system-defined rounded border.
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}

extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    /// A text field style with a system-defined square border.
    public static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() }
}

/// A field, framed in the box its style names — the body ``TextField`` and
/// ``SecureField`` draw their core through, so the two cannot disagree.
///
/// Reads the style from the context and draws the chosen view in place,
/// rather than holding an `@Environment` and an `if`/`else` in a body: as a
/// composite it copied the whole field core into each layer it passed
/// through, and its `ConditionalView` re-measured through another level — a
/// list of fields measured +27% over the plain core the fields drew before
/// the styles existed. An unbordered field draws its core where it stands; a
/// bordered one draws it inside the border, under a branch identity of its own.
///
/// "Where it stands" is literal: the unbordered core is measured and drawn by a
/// direct call, not through `measureChild` and the generic `renderToBuffer`.
/// Those put a second per-pass measure memo entry at this frame's identity —
/// same proposal, same reads — which could never serve a miss of the frame's
/// own entry, so it was only ever stored: a value hash of the whole core, a key,
/// a lookup, two gate reads, a lease and a store per field per pass. And a
/// render dispatch whose clamp the frame's own render repeats on the same
/// context. Both cores are `Renderable & Layoutable`, which is what the
/// constraint states. An `Animatable` core would still take the general path,
/// for the substitution it makes.
struct _StyledFieldFrame<Content: View & Renderable & Layoutable>: View, Renderable, Layoutable {
    let content: Content

    var body: Never {
        fatalError("_StyledFieldFrame renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let border = context.environment.textFieldStyle.fieldBorder else {
            // An Animatable core needs the substitution the generic render makes;
            // the test is static, so it folds away for the two cores there are.
            if Content._isAnimatable { return TUIkit.renderToBuffer(content, context: context) }
            // In place, at this frame's identity: the generic render minus a clamp
            // the render that reached this frame applies to the same context.
            return content.renderToBuffer(context: context)
        }
        return TUIkit.renderToBuffer(content.border(style: border), context: context.withBranchIdentity("bordered"))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let border = context.environment.textFieldStyle.fieldBorder else {
            if Content._isAnimatable { return measureChild(content, proposal: proposal, context: context) }
            // No memo entry of its own: this frame's entry (same identity, same
            // proposal, same reads) answers every repeat this pass. `isMeasuring`
            // as `measureChild` would have set it.
            if context.isMeasuring { return content.sizeThatFits(proposal: proposal, context: context) }
            var measuring = context
            measuring.isMeasuring = true
            return content.sizeThatFits(proposal: proposal, context: measuring)
        }
        return measureChild(
            content.border(style: border), proposal: proposal, context: context.withBranchIdentity("bordered"))
    }
}

private struct TextFieldStyleKey: EnvironmentKey {
    static let defaultValue: any TextFieldStyle = DefaultTextFieldStyle()
}

extension EnvironmentValues {
    /// The style text-entry fields in this subtree draw themselves with.
    ///
    /// Internal, like every other style key here: the modifier is the API.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``TextFieldStyle``.
    var textFieldStyle: any TextFieldStyle {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for text fields within this view.
    ///
    /// - Parameter style: The style to apply — ``TextFieldStyle/automatic`` or
    ///   ``TextFieldStyle/plain``.
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        environment(\.textFieldStyle, style)
    }
}
