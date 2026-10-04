//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Text Field Style

/// A style that customises the appearance of text-entry fields — SwiftUI's
/// `TextFieldStyle`, applied with ``TUIkit/View/textFieldStyle(_:)``.
///
/// TUIkit ships the two SwiftUI names a terminal can tell apart:
/// - ``DefaultTextFieldStyle`` (`.automatic`): the field draws itself — a
///   coloured surface with half-block caps for its rounded ends, so it reads
///   as a box you can type into even when it is empty.
/// - ``PlainTextFieldStyle`` (`.plain`): no surface and no caps. The text sits
///   on whatever is behind it, which is what an editable value inline in a
///   sentence or a row wants.
///
/// ```swift
/// TextField("Name", text: $name)             // a box
/// TextField("Name", text: $name)
///     .textFieldStyle(.plain)                // just the text
/// ```
///
/// Everything else about the field is unchanged: the caret, the selection, the
/// horizontal scroll, click-to-caret, and the suggestion drop-down all behave
/// the same either way.
///
/// SwiftUI's `.roundedBorder` and `.squareBorder` frame the field in a box,
/// drawn in box-drawing characters — rounded corners (`╭╮╰╯`) or square ones
/// (`┌┐└┘`) — around the plain field. A box is a row above and below in a
/// terminal, so a bordered field is three rows tall.
///
/// A protocol rather than an enum, matching SwiftUI and ``ListStyle`` beside it,
/// so a `where Self ==` extension gives the leading-dot spelling. SwiftUI's own
/// requirement is underscored and effectively closed; this one is a plain
/// readable property, so a caller *can* conform — the styles here are simply
/// the two the framework draws.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/textFieldStyle(_:)`` puts the style into the environment, and
/// the render cache keeps memoized subtrees honest by comparing each injected
/// value with the one applied there last frame. A value it cannot compare may
/// have changed under a buffer it is about to serve with nothing able to notice,
/// so every memo below one declines to cache at all — not the fields alone, but
/// everything under the modifier.
///
/// Both built-in styles are therefore `Equatable`. Neither holds anything, so
/// `==` within a type is vacuously true and every instance of one draws a field
/// identically. Between types it is the downcast in the comparison that answers,
/// which is what a field needs in both directions at once: the caps a style does
/// or does not draw are two cells of width as well as two glyphs, so a swap
/// changes what the field measures as much as what it paints, and must read as a
/// change.
///
/// A custom style need not conform — the paragraph above says a caller can write
/// one, and that stays true. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's text field styles declare no such conformance, and this is
///   one of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol TextFieldStyle: Sendable {
    /// Whether the field paints its own surface: the field-background colour
    /// behind the text, and the half-block caps at either end.
    ///
    /// `false` leaves the text on whatever is behind the field — deliberately
    /// no background at all rather than the palette's, so a plain field inside
    /// a tinted container picks up that container's tint the way ordinary text
    /// does.
    var drawsFieldSurface: Bool { get }

    /// The box the field is framed in, or `nil` for none.
    var fieldBorder: BorderStyle? { get }
}

extension TextFieldStyle {
    /// A style frames its field in nothing unless it says otherwise.
    public var fieldBorder: BorderStyle? { nil }
}

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
struct _StyledFieldFrame<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never {
        fatalError("_StyledFieldFrame renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let border = context.environment.textFieldStyle.fieldBorder else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        return TUIkit.renderToBuffer(content.border(style: border), context: context.withBranchIdentity("bordered"))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let border = context.environment.textFieldStyle.fieldBorder else {
            return measureChild(content, proposal: proposal, context: context)
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

// MARK: - Field chrome

/// The caps a styled field draws around its content, and what they cost.
///
/// One type because `TextField` and `SecureField` draw the same chrome from
/// two `_*Core` views: the arithmetic has to appear in four places (each
/// view's `sizeThatFits` and `renderToBuffer`), and four copies of "the caps
/// are two cells" is exactly how a measure and a render come to disagree.
@MainActor
struct FieldChrome {
    /// The cells the caps occupy in total — 2 with a surface, 0 without.
    let width: Int

    /// The leading cap, or `""` for a plain field.
    let open: String

    /// The trailing cap, or `""`.
    let close: String

    /// The field's surface colour, or `nil` when the style draws none.
    let surface: Color?

    /// The colour the caps are painted in, or `nil` for a style that draws none.
    ///
    /// Kept beside the bytes because the bytes state its OPAQUE spelling and the alpha
    /// has to reach the compositor separately — see ``claims(lineWidth:)``. It is the
    /// field surface, or the surface lerped toward the accent while hovered, so a
    /// palette that fades its page fades these too now that a derived surface carries
    /// the page's alpha (§39).
    let capColor: Color?

    /// Cells before the content starts — the leading cap, or none.
    ///
    /// Everything positioned against the content reads this rather than
    /// assuming 1: the caret's animated cells, the combo-box disclosure's click
    /// range, and the click-to-caret column mapping. A plain field's content
    /// starts at column 0, and each of those was an off-by-one waiting to
    /// happen.
    var leadingCells: Int { width / 2 }

    /// Cells after the content ends — the trailing cap, or none.
    ///
    /// The combo box's click target reaches through it: the cap is a single
    /// cell hard against the `▾`, and a click one cell wide of a two-cell
    /// target is a miss the pointer has no way to see coming.
    var trailingCells: Int { width - leadingCells }

    /// Builds the chrome for a style, tinting the caps toward the accent while
    /// hovered so the affordance reads as "clickable" without mimicking the
    /// focused look.
    /// - Parameter background: what the field is drawn ON — the page, or the
    ///   surface of a container that painted one (a `TabView`'s body). The
    ///   field's own surface is derived from it, so a field inside a tab does
    ///   not come out the same colour as the tab.
    init(
        style: any TextFieldStyle, palette: any Palette, isHovered: Bool,
        on background: Color? = nil
    ) {
        guard style.drawsFieldSurface else {
            self.width = 0
            self.open = ""
            self.close = ""
            self.surface = nil
            self.capColor = nil
            return
        }
        let surface =
            (background.map { palette.fieldBackground(on: $0) } ?? palette.fieldBackground)
            .resolve(with: palette)
        let capColor =
            isHovered
            ? Color.lerp(surface, palette.accent.resolve(with: palette), phase: 0.35)
            : surface
        self.width = 2
        let caps = Self.caps(in: capColor.opaqueSpelling)
        self.open = caps.open
        self.close = caps.close
        self.surface = surface
        self.capColor = capColor
    }

    /// The pair of caps last spelled, with everything their bytes are a function of.
    private struct SpelledCaps {
        let color: Color
        let depth: ColorDepth
        /// By value, as `ScrollbarMemo.Key` keeps it: at sixteen colours an RGB
        /// colour is spelled as the slot nearest what the terminal REPORTED that
        /// slot paints, and a task-local pin changes the report without moving
        /// `TerminalColors.generation`.
        let terminal: TerminalColors
        let open: String
        let close: String
    }

    /// The caps last spelled. Main-actor state, like the chrome itself.
    private static var lastCaps: SpelledCaps?

    /// The two caps in `color`, spelled once per colour, depth and terminal report
    /// rather than twice per field per render.
    ///
    /// The glyphs are constants, so the bytes are a function of the colour, the
    /// depth the emitter quantises to and the terminal's report — and nothing else.
    /// Every unhovered field on a page has the same cap colour, so the last pair
    /// answers almost every field: the spelling (a `TextStyle`, its introducer
    /// derived, twice) was 5.3% of a page of 200 fields. A miss — a hovered field's
    /// lerped colour, a palette or depth change — spells them as `colorize` does.
    private static func caps(in color: Color) -> (open: String, close: String) {
        let depth = ColorDepth.current
        let terminal = TerminalColors.current
        if let last = lastCaps, last.color == color, last.depth == depth, last.terminal == terminal {
            return (last.open, last.close)
        }
        // One introducer for the pair, wrapped as `colorize` wraps (`ANSIRenderer.wrap`
        // is what `render` returns), as a button's caps are.
        var style = TextStyle()
        style.foregroundColor = color
        let sequence = ANSIRenderer.styleSequence(for: style)
        let open = ANSIRenderer.wrap(String(TerminalSymbols.openCap), in: sequence)
        let close = ANSIRenderer.wrap(String(TerminalSymbols.closeCap), in: sequence)
        lastCaps = SpelledCaps(color: color, depth: depth, terminal: terminal, open: open, close: close)
        return (open, close)
    }

    /// What the caps owe on a field line `lineWidth` cells wide.
    ///
    /// Here rather than at the two call sites, because the trailing cap's column is
    /// `lineWidth - trailingCells` and this is the type that knows what
    /// ``trailingCells`` is — `TextField` and `SecureField` would each have re-derived
    /// it, which is how the two drift.
    ///
    /// The caps are half-block glyphs with no background of their own, so this is an
    /// INK claim. The field's surface is claimed by the content renderer, which is what
    /// paints it (§30).
    func claims(lineWidth: Int) -> [OpacityRegion] {
        guard let capColor, width > 0 else { return [] }
        return [
            OpacityRegion.claim(width: leadingCells, height: 1, ink: capColor),
            OpacityRegion.claim(
                offsetX: lineWidth - trailingCells, width: trailingCells, height: 1,
                ink: capColor),
        ].compactMap { $0 }
    }

    /// The chrome width for a style, without building the glyphs — what
    /// `sizeThatFits` needs, where there is no palette and nothing to draw.
    static func width(for style: any TextFieldStyle) -> Int {
        style.drawsFieldSurface ? 2 : 0
    }
}
