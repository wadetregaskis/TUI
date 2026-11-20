//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+ForegroundStyle.swift
//
//  `Text`'s own `foregroundStyle(_:) -> Text`, generic over `ShapeStyle` as
//  SwiftUI's is, and what each kind of style is kept as until the text is
//  drawn: a colour as the text's ink, a content level (`.secondary` and the
//  rest) as a statement resolved against the style in force where the text is
//  drawn, and any other style on a run.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

extension Text {
    /// Sets the style of the text displayed by this view — mirrors SwiftUI's
    /// `Text.foregroundStyle(_:)`.
    ///
    /// A colour is the text's ink. A content level — `.primary`, `.secondary`,
    /// `.tertiary`, `.quaternary`, `.quinary` — is resolved where the text is
    /// drawn, against the style in force there: under `.foregroundStyle(.red)`,
    /// `Text("x").foregroundStyle(.secondary)` is red at the secondary level, and
    /// with no style stated it is the palette's secondary tier. As in SwiftUI, a
    /// level named by ``View/foregroundStyle(_:_:)`` plays no part in a text's
    /// own: under `.foregroundStyle(.red, .blue)` the text's `.secondary` is
    /// still the secondary red, where a `View`'s `.foregroundStyle(.secondary)`
    /// draws blue (measured, macOS 15.8.3: #FF9C96,
    /// `Tools/SwiftUIProbes/Text foregroundStyle levels (TXTFG)/`). Under a
    /// view's own level with no style above it — a `VStack`'s
    /// `.foregroundStyle(.secondary)` — a text's level replaces that level
    /// rather than fading it further: its `.secondary` is the palette's
    /// secondary tier and its `.primary` the foreground, as SwiftUI's are
    /// (#808080 and #272727, `nested.out`). Under a level of a colour it is a
    /// level of that level: below `.foregroundStyle(.red)`, a view's
    /// `.secondary` makes a text's own `.secondary` red at a quarter (#FFCDCA).
    /// Any other style — `.tint`, `.foreground`, a gradient — is resolved where
    /// the text is drawn too.
    ///
    /// ```swift
    /// VStack {
    ///     Text("Title")
    ///     Text("Subtitle").foregroundStyle(.secondary)   // the secondary red
    /// }
    /// .foregroundStyle(.red)
    /// ```
    ///
    /// When a text states its style twice, the first one written wins, as in
    /// SwiftUI (measured, the same probe): `.foregroundStyle(.red)
    /// .foregroundStyle(.blue)` is red. A level written first is a level of
    /// the style written after it, as of a style above:
    /// `.foregroundStyle(.secondary).foregroundStyle(.blue)` is the secondary
    /// blue (`Color.blue.secondary`, measured).
    ///
    /// > Note: The style is kept in the text's own value, not painted by a
    ///   modifier, so a change to it inside ``withAnimation(_:_:)`` happens at
    ///   once, where ``View/foregroundStyle(_:)-(S)``'s fades: nothing here asks the
    ///   animator, and asking it would cost a lookup in every `Text` on every
    ///   frame. Wrap the text — `VStack { Text(…) }.foregroundStyle(…)` — to
    ///   fade it (Deliberate deviations T10, decisions WL-Q1).
    ///
    /// - Parameter style: The style to draw the text in.
    /// - Returns: A new text with the style applied.
    @inlinable
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        // Inlinable so that these casts are decided where `S` is known: for a
        // colour, which nearly every call states, the call compiles to the
        // colour's store alone, as the colour overload it replaced did.
        if let color = style as? Color { return withForegroundColor(color) }
        if let level = style as? HierarchicalShapeStyle { return withForegroundLevel(level) }
        return withForegroundShape(style)
    }

    /// The colour spelling, so that a leading dot finds every static colour on
    /// ``Color`` — `.palette.accent`, `.rgb(…)`, `.ansi(…)`, `.default` —
    /// which the generic overload finds only where `ShapeStyle` forwards it.
    ///
    /// Not SwiftUI's, whose `Text` has the generic overload alone. Disfavoured,
    /// as ``View/foregroundStyle(_:)-(Color)`` is, so it is chosen only where
    /// the generic overload finds no answer: every call SwiftUI accepts resolves
    /// as it does there — `.secondary` is the content level, not
    /// ``Color/secondary`` — and costs no more.
    ///
    /// - Parameter style: The colour to draw the text in.
    /// - Returns: A new text with the colour applied.
    @_disfavoredOverload
    public func foregroundStyle(_ style: Color) -> Text {
        withForegroundColor(style)
    }

    // Of two styles on one text the first written wins, as in SwiftUI
    // (`Text+StatementOrder.swift`): each of these leaves a text that states a
    // style already as it is, but for a content level, which takes the style
    // written after it as the style it is a level of. A whole-text style
    // (``wholeTextShape()``) counts as stated; a fragment's own does not, being
    // the fragment's.

    /// This text drawn in `color`, or, where it states a level, at that level
    /// of `color`: the colour at the level's strength, as `Color.blue.secondary`
    /// draws (measured to be the same pixels).
    @usableFromInline
    func withForegroundColor(_ color: Color) -> Text {
        guard wholeTextShape() == nil else { return self }
        switch style.foregroundInk {
        case .unstated:
            var copy = self
            copy.style.foregroundColor = color
            return copy
        case .stated:
            return self
        default:
            let level = style.foregroundInk.level ?? 0
            var copy = self
            copy.style.foregroundColor = level == 0 ? color : color.opacity(HierarchicalShapeStyle.opacities[level])
            return copy
        }
    }

    /// This text drawn at content level `level` of the style in force where it
    /// is drawn.
    @usableFromInline
    func withForegroundLevel(_ level: HierarchicalShapeStyle) -> Text {
        guard style.foregroundInk == .unstated, wholeTextShape() == nil else { return self }
        var copy = self
        copy.style.foregroundInk = StatedInk(level: level.level)
        return copy
    }

    /// This text drawn in `style`, a style that is neither a colour nor a level:
    /// kept on the text's runs, as ``customAttribute(_:)`` keeps an attribute
    /// (a text of one fragment becomes a text of one run that carries it), since
    /// the text's own style has room for a colour or a level and no more. A
    /// fragment's own ink stays its own.
    ///
    /// Where the text states a level, it stays, and is a level of `style`: on
    /// a text of one fragment the text's own, drawn with `style` in force
    /// (``inWholeTextShape(_:)``); on a concatenation each fragment's that
    /// states no style of its own (``Run/styleResolvingInk(over:in:)``).
    @usableFromInline
    func withForegroundShape<S: ShapeStyle>(_ style: S) -> Text {
        guard self.style.foregroundInk.value == nil, wholeTextShape() == nil else { return self }
        return carryingShape(style)
    }

    /// This text with `style` on its runs (``withForegroundShape(_:)``),
    /// whatever it states already.
    private func carryingShape(_ style: some ShapeStyle) -> Text {
        var text = self
        let level = text.style.foregroundInk.level
        let shape = TextAttributes().adding(TextForegroundShape(style))
        let own = text.runs ?? [Run(text: content, style: TextStyle(), live: nil, link: nil)]
        // A level of the whole goes down to the fragments it reaches only on
        // a concatenation: a text of one fragment keeps it as its own.
        var levelled: TextStyle?
        if let level, text.runs != nil {
            levelled = TextStyle()
            levelled?.foregroundInk = StatedInk(level: level)
        }
        text.runs = own.map { run in
            var run = run
            // `rebased(on:)` fills in what the run did not state: here its ink.
            if let levelled, run.style.foregroundInk == .unstated, run.attributes?[TextForegroundShape.self] == nil {
                run = run.rebased(on: levelled)
            }
            run.attributes = (run.attributes ?? TextAttributes()).merged(over: shape)
            return run
        }
        return text
    }

    /// This text, read again from `original`'s key, with the style of the
    /// whole of it that `original` carries (``wholeTextShape()``), which
    /// reading the key again does not keep. An original with no runs, nearly
    /// every one, pays a nil check.
    func keepingWholeTextShape(of original: Text) -> Text {
        guard original.runs != nil, let (_, shape) = original.wholeTextShape() else { return self }
        // Put back as it was, so not through the first-statement rule: the
        // reading took the original's style, a level with the shape included.
        return carryingShape(shape.style)
    }

    /// This text as a text of no runs, and the style the one run it has
    /// carries, when that run is there only to carry a style of the whole
    /// text (``withForegroundShape(_:)``); `nil` for any other text, which is
    /// nearly every one, at the cost of a nil check.
    ///
    /// Drawn as the plain text with that style in force around it, the text is
    /// drawn as ``View/foregroundStyle(_:)-(S)`` draws its content — a gradient
    /// as a ramp across it — rather than as a concatenation of one run, which
    /// has one colour per run.
    func wholeTextShape() -> (plain: Text, shape: TextForegroundShape)? {
        guard let runs, runs.count == 1, let run = runs.first, run.link == nil, run.live == nil,
            let attributes = run.attributes, attributes.holdsOnly(TextForegroundShape.self),
            let shape = attributes[TextForegroundShape.self]
        else { return nil }
        var plain = self
        plain.runs = nil
        plain.style = run.style.merged(over: style)
        return (plain, shape)
    }
}

// MARK: - Resolving at the draw

extension Text {
    /// The palette's own tier for content level `level`, as the role it is:
    /// what a text's own level draws in with no style stated above it, as
    /// ``Color/secondary`` draws, so a `.semanticColor(_:)` cascade entry for
    /// the role reaches it.
    static func paletteTier(_ level: Int) -> Color {
        switch level {
        case 0: Color.palette.foreground
        case 1: Color.palette.foregroundSecondary
        case 2: Color.palette.foregroundTertiary
        case 3: Color.palette.foregroundQuaternary
        default: Color.palette.foregroundQuaternary.opacity(0.5)
        }
    }

    /// What a text's own content level `level` draws in: `primary`, the style
    /// the text would draw in had it stated none, at the level's strength; or
    /// `nil` for the palette's tier (``paletteTier(_:)``), where nothing is
    /// stated above it but perhaps a content level of nothing
    /// (``EnvironmentValues/levelPrimaryForegroundStyle``), or it is over a
    /// raised background, as ``HierarchicalShapeStyle`` answers there.
    ///
    /// Only `primary`: a level named by ``View/foregroundStyle(_:_:)`` is not
    /// consulted, as SwiftUI's text does not (see ``foregroundStyle(_:)-(S)``).
    static func levelPaint(_ level: Int, over primary: Paint?, in environment: EnvironmentValues) -> Paint? {
        guard let primary, environment.backgroundProminence != .increased else { return nil }
        return level == 0 ? primary : primary.faded(HierarchicalShapeStyle.opacities[level])
    }
}

@MainActor extension Text.Run {
    /// This run's own style with its ink as drawn here: a content level it
    /// stated resolved against `primary` (``Text/levelPaint(_:over:in:)``),
    /// and a style it carries (``Text/withForegroundShape(_:)``) painted, each
    /// as one colour. A run's ink is one colour; a ramp spans a whole text.
    ///
    /// A run that states neither — nearly every one — pays two checks.
    func styleResolvingInk(over primary: Paint?, in paints: inout TextShapePaints) -> TextStyle {
        if let level = style.foregroundInk.level {
            // A style the run carries is the one its level is of: written
            // after the level, it is nearer the text than any style above.
            let base = attributes?[TextForegroundShape.self].map { paints.paint(of: $0) } ?? primary
            var resolved = style
            resolved.foregroundColor = Text.levelPaint(level, over: base, in: paints.context.environment)?
                .representative ?? Text.paletteTier(level)
            return resolved
        }
        guard style.foregroundInk == .unstated, let shape = attributes?[TextForegroundShape.self] else {
            return style
        }
        var resolved = style
        resolved.foregroundColor = paints.paint(of: shape).representative
        return resolved
    }

    /// The ramp this run states for itself — a gradient or an image it
    /// carries (``Text/withForegroundShape(_:)``), and no ink of its own over
    /// it — or `nil`.
    func statedRamp(in paints: inout TextShapePaints) -> Paint? {
        guard style.foregroundInk == .unstated, let shape = attributes?[TextForegroundShape.self] else { return nil }
        let paint = paints.paint(of: shape)
        return paint.solid == nil ? paint.unshadowed : nil
    }

    /// The first ramp one of `runs` states for itself (``statedRamp(in:)``),
    /// which a text with no ramp of its own bands across its block for every
    /// run that states it: one ramp per text, as an inherited one is. A run
    /// that states another draws in its representative colour.
    ///
    /// A text whose runs carry no style of this kind — every other one — pays
    /// a nil check per run.
    static func firstStatedRamp(in runs: [Self], paints: inout TextShapePaints) -> Paint? {
        for run in runs where run.attributes != nil {
            if let ramp = run.statedRamp(in: &paints) { return ramp }
        }
        return nil
    }
}

// MARK: - Resolving a carried style where the text is drawn

/// The styles a text carries (``TextForegroundShape``), resolved where the
/// text is drawn, an image paint's pixels asked for as the view modifier asks
/// for them (``Paint/materializingImages(in:owner:)``).
///
/// Unasked, an ``ImagePaint`` has no pixels and draws nothing: the view
/// modifier asks once for everything below it, and a style kept in a text's
/// value is asked for here, where the text is drawn. Each distinct image asks
/// at a step of its own under the text's identity, numbered in the order the
/// text first carries it: two images asking at one step would each find the
/// other's the last one loaded, cancel its load and write the phase back, and
/// neither would ever paint. Runs that carry one image share its step and its
/// pixels, so their paints compare equal and take one ramp.
///
/// A style that holds no image — nearly every one — pays an enum test.
@MainActor
struct TextShapePaints {
    /// Where the text is drawn.
    let context: RenderContext
    /// Each image resolved so far, as stated and with its pixels.
    private var images: [(stated: Paint, drawn: Paint)] = []

    init(_ context: RenderContext) {
        self.context = context
    }

    /// `shape`'s style resolved here, with an image's pixels in it.
    mutating func paint(of shape: TextForegroundShape) -> Paint {
        let paint = shape.style.paint(in: context.environment)
        guard paint.hasImage else { return paint }
        if let known = images.first(where: { $0.stated == paint }) { return known.drawn }
        let step = context.withChildIdentity(erasedType: TextForegroundShape.self, index: images.count)
        let drawn = paint.materializingImages(in: step, owner: TextForegroundShape.self)
        images.append((paint, drawn))
        return drawn
    }
}

// MARK: - A style kept on a run

/// A style that is neither a colour nor a content level, which
/// `Text.foregroundStyle(_:)` keeps on a text's runs (``Text/withForegroundShape(_:)``)
/// and the text resolves where it is drawn.
///
/// An attribute of the runs, as an app's custom attributes are, so that every
/// path that carries a run's attributes — a concatenation, a live text, a
/// link's words — carries it, and a run no bigger for it: the attributes are
/// one optional dictionary already. No app can ask a renderer's run for it:
/// the type is the framework's own.
struct TextForegroundShape: TextAttribute {
    /// The style.
    let style: any ShapeStyle

    init(_ style: some ShapeStyle) {
        self.style = style
    }

    /// Equal where the styles are of one `Equatable` type and equal; unequal
    /// otherwise, which is the safe answer for a value compared by what holds
    /// it (a text compared by its memo draws again).
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let comparable = lhs.style as? any Equatable else { return false }
        return comparable.isEqual(to: rhs.style)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type(of: style)))
    }
}

// MARK: - The text's own ink

// The render's half (`Text.swift` calls these), kept beside the statements
// they resolve.
@MainActor extension Text {
    /// For a text whose one run carries a style of the whole of it
    /// (``wholeTextShape()``), the plain text and `context` with that style in
    /// force: drawn so, it is drawn as ``View/foregroundStyle(_:)-(S)`` draws
    /// its content. `nil` for every other text.
    func inWholeTextShape(_ context: RenderContext) -> (plain: Text, context: RenderContext)? {
        guard let (plain, shape) = wholeTextShape() else { return nil }
        var styled = context
        var paints = TextShapePaints(context)
        styled.environment.foregroundStyle = paints.paint(of: shape)
        styled.environment.foregroundStyleIsDefault = false
        return (plain, styled)
    }

    /// Fills in `style`'s foreground, and reports a gradient if that is what
    /// the environment supplied.
    ///
    /// Precedence: an explicit *concrete* colour on this Text wins; an explicit
    /// *semantic* colour may be remapped by a same-role `.semanticColor(role)`
    /// cascade entry; otherwise a scoped cascade colour > the broad
    /// `.foregroundStyle` environment value > the palette default.
    ///
    /// A ramp comes back separately rather than in the style, because a
    /// `TextStyle` names one colour and the whole point of a ramp is that it
    /// does not. The style still gets the ramp's representative so that
    /// anything asking for one colour has one. A shadowed environment paint
    /// comes back in `shadowing`, its shadows being the drawn letters' to cast.
    static func resolveForeground(
        into style: inout TextStyle,
        stated ink: StatedInk,
        cascade: StyleCascade,
        cascaded: StyleAttributes,
        context: RenderContext,
        shadowing: inout Paint?
    ) -> Paint? {
        var stated = ink.value
        var environmentPaint = context.environment.foregroundStyle
        // A content level the text stated for itself is the style it would
        // draw in had it stated none, at that level, drawn as that style is
        // below; or, with none stated above it, or only a content level of
        // none (``EnvironmentValues/levelPrimaryForegroundStyle``), the
        // palette's tier, drawn as a stated role colour is.
        if let level = ink.level {
            let primary = cascaded.foreground.map(Paint.color) ?? context.environment.levelPrimaryForegroundStyle
            if let paint = levelPaint(level, over: primary, in: context.environment) {
                environmentPaint = paint
            } else {
                stated = paletteTier(level)
            }
        }
        if let stated {
            if case .semantic(let role) = stated.value {
                style.foregroundColor =
                    cascade.resolve(for: [.semanticColor(role)]).foreground ?? stated
            }
            return nil
        }
        if ink.level == nil, let cascadedForeground = cascaded.foreground {
            style.foregroundColor = cascadedForeground
            return nil
        }
        guard let paint = environmentPaint else {
            style.foregroundColor = context.environment.palette.foreground
            return nil
        }
        style.foregroundColor = paint.representative
        if paint.castsAnything { shadowing = paint }
        return paint.solid == nil ? paint.unshadowed : nil
    }

    /// The colour this text states for itself, for its palette role: its own
    /// colour, or for a content level with no style above it the palette's
    /// tier, which is what it draws in there (``resolveForeground``). A level
    /// of a style above it states no role of its own.
    func explicitRoleInk(in environment: EnvironmentValues) -> Color? {
        guard let level = style.foregroundInk.level else { return style.foregroundColor }
        return environment.levelPrimaryForegroundStyle == nil ? Self.paletteTier(level) : nil
    }
}
