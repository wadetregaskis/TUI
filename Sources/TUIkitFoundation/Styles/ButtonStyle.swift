//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ButtonStyleConfiguration

/// The properties of a button, passed to a ``ButtonStyle`` so it can
/// produce the button's appearance.
///
/// You don't create this type yourself — TUIkit constructs a configuration
/// for each ``Button`` and hands it to the active style's
/// ``ButtonStyle/makeBody(configuration:)`` method.
public struct ButtonStyleConfiguration {
    /// A type-erased label of a button — the view a style places its label
    /// with, as in SwiftUI: `configuration.label.padding(1)`.
    ///
    /// It is the button's `@ViewBuilder` label when it was built with one, and
    /// otherwise its title as a `Text`.
    public struct Label: View {
        let title: String
        let view: AnyView?

        public var body: some View {
            if let view {
                view
            } else {
                Text(verbatim: title)
            }
        }
    }

    /// A view that describes the effect of pressing the button: its label.
    public var label: Label {
        Label(title: title, view: labelView)
    }

    /// The button's label text, for a style that draws it itself.
    ///
    /// Terminal-specific: SwiftUI hands a style only the label view. TUIkit's
    /// own styles draw a string label procedurally — the caps, the padding, the
    /// focus glow — so the configuration also carries the text. Empty when the
    /// button was built with a `@ViewBuilder` label (`Button(action:label:)`);
    /// the composed view is then in ``labelView``.
    public let title: String

    /// The composed `@ViewBuilder` label, type-erased, when the button was built
    /// with `Button(action:label:)`; `nil` for a plain string label.
    ///
    /// A custom style can place this view in its body to render an arbitrary
    /// label (styled text, a glyph + text, …). The built-in styles render it
    /// inside their chrome when present.
    public let labelView: AnyView?

    /// The semantic role of the button, if any.
    ///
    /// A style may use this to adjust its appearance — for example, the
    /// built-in styles always colour a ``ButtonRole/destructive`` button
    /// with the palette's error colour.
    public let role: ButtonRole?

    /// Whether the button is currently being pressed.
    ///
    /// - Note: True for a real mouse press-and-hold — the button is down over
    ///   the button and has not yet been released or dragged off it — the same
    ///   gesture `MouseEventDispatcher.endsHeldGesture` already distinguishes
    ///   from a plain click elsewhere. A **keyboard** activation (Enter,
    ///   Space) has no such gesture — a terminal reports a key press, not a
    ///   down-then-up pair — so this stays `false` for those, as does a
    ///   `.menuTrigger(_:)` button's opening press, which fires its action and
    ///   hands the gesture off in the same instant rather than holding.
    public let isPressed: Bool

    /// Whether the button currently holds keyboard focus.
    ///
    /// - Note: Terminal-specific addition. SwiftUI styles read focus from
    ///   the environment; TUIkit surfaces it directly on the configuration
    ///   because button rendering is procedural.
    public let isFocused: Bool

    /// Whether the cursor is currently hovering over the button.
    ///
    /// - Note: Terminal-specific addition. SwiftUI surfaces hover
    ///   state via the `.onHover` modifier; TUIkit surfaces it on
    ///   the configuration because button rendering is procedural,
    ///   so styles can pick up the affordance without each one
    ///   wiring its own `.onHover`. Always `false` on a disabled
    ///   button.
    public let isHovered: Bool

    /// Whether the button is enabled.
    ///
    /// - Note: Terminal-specific addition mirroring SwiftUI's `\.isEnabled`
    ///   environment value. A disabled button renders dimmed.
    public let isEnabled: Bool

    /// The button's ``KeyboardShortcut``, already resolved for this terminal
    /// (so a `⌘` shortcut appears as whatever ``EnvironmentValues/commandKey``
    /// binds it to), or `nil` when the button has none.
    ///
    /// - Note: Terminal-specific addition. AppKit draws a menu item's key
    ///   equivalent for you; here a menu-row style has to draw it, so it needs
    ///   to know. ``KeyboardShortcut/displayString`` is the printable form.
    public let keyboardShortcut: KeyboardShortcut?

    // Configurations are produced by ``Button`` during rendering, never by
    // client code — the compiler-synthesized memberwise initializer
    // (internal access level) is exactly what's needed.
}

// MARK: - ButtonStyle

/// A type that applies a custom appearance to all buttons within a view
/// hierarchy.
///
/// To configure the button style for a view, apply the
/// ``View/buttonStyle(_:)-1qf1r`` modifier:
///
/// ```swift
/// Button("Save") { save() }
///     .buttonStyle(.destructive)
/// ```
///
/// The modifier flows through the environment, so it can also be applied to
/// a container to style every button it contains:
///
/// ```swift
/// VStack {
///     Button("One") { }
///     Button("Two") { }
/// }
/// .buttonStyle(.plain)
/// ```
///
/// ## Built-in Styles
///
/// SwiftUI's built-in styles are ``PrimitiveButtonStyle``s, and so are
/// TUIkit's under the same names — `.automatic`, `.bordered`,
/// `.borderedProminent`, `.borderless`, `.plain`, `.link`, `.accessoryBar` and
/// `.accessoryBarAction`. Two TUI-specific appearances are `ButtonStyle`s:
///
/// - ``DestructiveButtonStyle`` (``destructive``) — error-coloured.
/// - ``SuccessButtonStyle`` (``success``) — success-coloured.
///
/// ## Custom Styles
///
/// Conform to `ButtonStyle` and return a view from
/// ``makeBody(configuration:)``:
///
/// ```swift
/// struct QuietButtonStyle: ButtonStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         configuration.label
///             .foregroundStyle(configuration.isFocused ? .palette.accent
///                                                       : .palette.foregroundSecondary)
///     }
/// }
/// ```
///
/// ## Styles and the render cache
///
/// ``View/buttonStyle(_:)-1qf1r`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all.
///
/// Every built-in style is therefore `Equatable`. Without that, nothing under a
/// `.buttonStyle(...)` could be memoized — and because the modifier flows
/// through the environment, one call on a container turns the cache off for
/// everything inside it, buttons and their neighbours alike.
///
/// For the styles that hold nothing the conformance is a formality: every
/// instance styles a button identically. For the two that hold something it is
/// load-bearing, and it is what keeps this a performance fix rather than a
/// stale serve: a swatch built from a changed colour must compare unequal to
/// the one before it, or the cache would hand it the buffer painted in the old
/// colour. A custom style need not conform: one that does not simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's `DefaultButtonStyle` declares no such conformance, and
///   this is one of the places a terminal renderer has to differ. SwiftUI diffs
///   the view graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
///
/// - Note: The built-in styles draw terminal-specific flourishes (half-block
///   caps, a pulsing focus glow) that require procedural buffer rendering.
///   Custom styles compose ordinary TUIkit views and modifiers, which is
///   enough for colour and weight changes but cannot reproduce those
///   procedural effects.
public protocol ButtonStyle: Sendable {
    /// A view that represents the body of a button.
    associatedtype Body: View

    /// Creates a view that represents the body of a button.
    ///
    /// - Parameter configuration: The properties of the button being styled.
    /// - Returns: A view describing the button's appearance.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a button.
    typealias Configuration = ButtonStyleConfiguration
}

extension ButtonStyle {
    /// Renders this style's body for `configuration` into a frame buffer.
    ///
    /// Call sites hold the style as `any ButtonStyle`. This method opens the
    /// existential so ``makeBody(configuration:)`` can return its concrete
    /// ``Body`` type, which the renderer then resolves into a buffer.
    @MainActor
    func makeBuffer(
        configuration: Configuration,
        context: RenderContext
    ) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }

    /// Whether this style's body can answer its own size without being drawn.
    ///
    /// A metatype conformance check, and the whole reason ``makeSize`` is worth
    /// asking for: a `Layoutable` body has a `sizeThatFits`, so measuring it
    /// paints nothing. A procedural one (`_ButtonStyleBody`) would be rendered
    /// one level further down anyway, and asking it through the style would
    /// resolve the configuration twice for the same answer.
    var bodyCanMeasureItself: Bool { Body.self is any Layoutable.Type }

    /// The size ``makeBuffer(configuration:context:)`` would come back as,
    /// without building it.
    ///
    /// The same body, asked the same question through `measureChild` instead of
    /// `renderToBuffer` — which is what lets a structural style answer without
    /// painting a cell, and what keeps a procedural one costing exactly what it
    /// did. Here rather than at the call site so `Body` stays concrete: erasing
    /// it to `AnyView` to measure would change the answer, because a flexible
    /// child measures to the full available width through `AnyView`.
    @MainActor
    func makeSize(
        configuration: Configuration,
        proposal: ProposedSize,
        context: RenderContext
    ) -> ViewSize {
        measureChild(makeBody(configuration: configuration), proposal: proposal, context: context)
    }
}

// MARK: - Built-in Button Styles
//
// SwiftUI's built-in button styles are PRIMITIVE styles (see
// `PrimitiveButtonStyle.swift`), and so are these, under SwiftUI's names. Each
// stands for a `ButtonStyle` appearance TUIkit draws procedurally, and applying
// one installs that appearance — so a built-in costs no more than it did when
// these were appearances themselves, with no view between the button and its
// drawing. (A type cannot be both kinds of style: each protocol defines its
// own `Configuration`.) The appearances are reachable by the same names as
// `ButtonStyle`s, through ``_AppearanceButtonStyle``, which is what lets a
// `Theme` name one. Two TUI-specific appearances, `.destructive` and
// `.success`, are `ButtonStyle`s only.

/// The default button style, based on the button's context: here, the
/// bracketed, accent-tinted button — what ``BorderedButtonStyle`` draws, as on
/// macOS.
///
/// Access this style with ``PrimitiveButtonStyle/automatic``.
public struct DefaultButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates a default button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .default) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style that applies standard border artwork based on the button's
/// context: the half-block caps around an accent-tinted face, `▐ Label ▌`.
///
/// Access this style with ``PrimitiveButtonStyle/bordered``.
public struct BorderedButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates a bordered button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .default) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style that applies standard border prominent artwork: the bordered
/// button, bold and in the accent colour.
///
/// Access this style with ``PrimitiveButtonStyle/borderedProminent``.
public struct BorderedProminentButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates a bordered prominent button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .primary) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style that doesn't apply a border: the label alone, in the accent
/// colour, behind the plain button's focus marker.
///
/// Access this style with ``PrimitiveButtonStyle/borderless``.
public struct BorderlessButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates a borderless button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .borderless) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style that doesn't style or decorate its content while idle, but
/// may apply a visual effect to indicate the pressed, focused, or enabled state
/// of the button: here, a focus marker in front of the label.
///
/// Access this style with ``PrimitiveButtonStyle/plain``.
public struct PlainButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates a plain button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .plain) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style for buttons that emulate links: the label in the accent
/// colour, underlined as ``Link``'s is, with the focus shown in the words rather
/// than in front of them.
///
/// Access this style with ``PrimitiveButtonStyle/link``.
public struct LinkButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates a link button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .link) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style for the buttons of an accessory bar: the plain button.
///
/// TUIkit draws no accessory bars of its own, so this is the look such a
/// button takes anywhere: unbordered, as a scope bar's are.
///
/// Access this style with ``PrimitiveButtonStyle/accessoryBar``.
public struct AccessoryBarButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates an accessory bar button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .plain) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style for an accessory bar's action button: the bordered button.
///
/// Access this style with ``PrimitiveButtonStyle/accessoryBarAction``.
public struct AccessoryBarActionButtonStyle: BuiltInButtonStyle, Equatable {
    /// Creates an accessory bar action button style.
    public init() {}

    var appearance: any ButtonStyle { _AppearanceButtonStyle(appearance: .default) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with this style.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        builtInBody(configuration: configuration)
    }
}

/// A button style that uses the palette's error colour to signal a
/// destructive action.
///
/// TUI-specific. Access this style with ``ButtonStyle/destructive``.
public struct DestructiveButtonStyle: ButtonStyle, Equatable {
    /// Creates a destructive button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .destructive)
    }
}

/// A button style that uses the palette's success colour.
///
/// TUI-specific. Access this style with ``ButtonStyle/success``.
public struct SuccessButtonStyle: ButtonStyle, Equatable {
    /// Creates a success button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .success)
    }
}

// MARK: - Style Static Accessors
//
// On both protocols: `.buttonStyle(.plain)` resolves through the primitive
// overload (the other is disfavoured), and a `Theme(buttonStyle: .plain)`
// through `ButtonStyle`, to the appearance the primitive style installs.

extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
    /// The default button style, based on the button's context.
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
    /// A button style that applies standard border artwork based on the
    /// button's context.
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    /// A button style that applies standard border prominent artwork based on
    /// the button's context.
    public static var borderedProminent: BorderedProminentButtonStyle {
        BorderedProminentButtonStyle()
    }
}

extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    /// A button style that doesn't apply a border.
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    /// A button style that doesn't style or decorate its content while idle.
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

extension PrimitiveButtonStyle where Self == LinkButtonStyle {
    /// A button style for buttons that emulate links.
    public static var link: LinkButtonStyle { LinkButtonStyle() }
}

extension PrimitiveButtonStyle where Self == AccessoryBarButtonStyle {
    /// A button style that is typically used in the context of an accessory
    /// toolbar.
    public static var accessoryBar: AccessoryBarButtonStyle { AccessoryBarButtonStyle() }
}

extension PrimitiveButtonStyle where Self == AccessoryBarActionButtonStyle {
    /// A button style for an accessory toolbar's action button.
    public static var accessoryBarAction: AccessoryBarActionButtonStyle {
        AccessoryBarActionButtonStyle()
    }
}

/// A built-in appearance, as a ``ButtonStyle``: what a built-in
/// ``PrimitiveButtonStyle`` installs when it is applied, and what the
/// `ButtonStyle` statics of the same names return — so a ``Theme`` can name
/// one, `Theme(buttonStyle: .plain)`.
public struct _AppearanceButtonStyle: ButtonStyle, Equatable {
    let appearance: _ButtonAppearance

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(
            configuration: appearance == .link ? Self.linkLabel(configuration) : configuration,
            appearance: appearance)
    }

    /// ``LinkButtonStyle``'s label goes through the view path, the one that can
    /// carry an underline, tinted and underlined as ``Link``'s is.
    @MainActor
    private static func linkLabel(_ configuration: Configuration) -> Configuration {
        ButtonStyleConfiguration(
            title: "",
            labelView: AnyView(configuration.label.underline().foregroundStyle(.palette.accent)),
            role: configuration.role,
            isPressed: configuration.isPressed,
            isFocused: configuration.isFocused,
            isHovered: configuration.isHovered,
            isEnabled: configuration.isEnabled,
            keyboardShortcut: configuration.keyboardShortcut)
    }
}

extension ButtonStyle where Self == _AppearanceButtonStyle {
    /// The default appearance (``DefaultButtonStyle``).
    public static var automatic: Self { Self(appearance: .default) }

    /// The bordered appearance (``BorderedButtonStyle``).
    public static var bordered: Self { Self(appearance: .default) }

    /// The bordered prominent appearance (``BorderedProminentButtonStyle``).
    public static var borderedProminent: Self { Self(appearance: .primary) }

    /// The borderless appearance (``BorderlessButtonStyle``).
    public static var borderless: Self { Self(appearance: .borderless) }

    /// The plain appearance (``PlainButtonStyle``).
    public static var plain: Self { Self(appearance: .plain) }

    /// The link appearance (``LinkButtonStyle``).
    public static var link: Self { Self(appearance: .link) }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    /// A button style that uses the error colour for destructive actions.
    public static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

extension ButtonStyle where Self == SuccessButtonStyle {
    /// A button style that uses the success colour.
    public static var success: SuccessButtonStyle { SuccessButtonStyle() }
}

/// A ``Link``'s style: plain, with the focus in the text rather than in front
/// of it.
///
/// Internal on purpose. The public way to choose between the two affordances is
/// ``View/linkFocusIndicator(_:)``, and SwiftUI has no `.link`
/// button style to be source-compatible with — adding one would be a public
/// name this framework would then owe forever for the sake of an internal
/// wiring detail.
///
/// `Equatable` for the reason given under ``ButtonStyle``, and here the
/// conformance does real work rather than none: `_Link` builds the style from
/// whatever ``View/linkFocusIndicator(_:)`` is in force, so two frames can
/// genuinely hand down different values, and the synthesized `==` is what tells
/// the cache to drop the link it drew with the other affordance.
struct _LinkButtonStyle: ButtonStyle, Equatable {
    /// Which affordance the app asked for. Carried as a value rather than read
    /// from the environment inside the style, so the choice is made once, in
    /// `_Link`'s body, where the environment is legitimately readable.
    let indicator: LinkFocusIndicator

    func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(
            configuration: configuration,
            appearance: indicator == .bullet ? .borderless : .link)
    }
}

// MARK: - Button Appearance

/// The resolved visual parameters shared by the built-in button styles.
///
/// Framework infrastructure — built-in ``ButtonStyle`` types hand one of
/// these to ``_ButtonStyleBody`` for procedural rendering.
struct _ButtonAppearance: Equatable {
    /// The label colour, or `nil` to use the palette accent.
    var foregroundColor: Color?

    /// Whether the label is bold even when unfocused.
    var isBold: Bool

    /// Horizontal padding, in characters, inside the button.
    var horizontalPadding: Int

    /// Whether the button renders without brackets or background.
    var isPlain: Bool

    /// The variant token used to scope `.controlVariant(.button, …)` style
    /// entries (see ``Button/Variant``).
    var variant: String

    /// Whether focus is shown by breathing the LABEL rather than by a bullet
    /// in front of it — and therefore whether the two chrome cells the bullet
    /// needs are reserved at all.
    ///
    /// What a `Link` wants, and the reason it is a property here rather than a
    /// second plain style: a link is written INSIDE a sentence, and a control
    /// that reserves two columns cannot be. The bullet is the right affordance
    /// for a plain button sitting on its own line, where the reservation keeps
    /// a column of them aligned as the focus moves between them; it is the
    /// wrong one for four words in a paragraph.
    ///
    /// The breath goes in the text for the same reason the tab strip's does —
    /// see ``ActiveChipCycle``, which says it at more length.
    var indicatesFocusInLabel: Bool = false

    /// The default appearance — dimmed foreground, not bold.
    static let `default` = Self(
        foregroundColor: Color.palette.foregroundSecondary,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false,
        variant: "default"
    )

    /// The primary appearance — bold, accent-coloured.
    static let primary = Self(
        foregroundColor: Color.palette.accent,
        isBold: true,
        horizontalPadding: 1,
        isPlain: false,
        variant: "primary"
    )

    /// The destructive appearance — error-coloured.
    static let destructive = Self(
        foregroundColor: Color.palette.error,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false,
        variant: "destructive"
    )

    /// The success appearance — success-coloured.
    static let success = Self(
        foregroundColor: Color.palette.success,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false,
        variant: "success"
    )

    /// The borderless appearance — no brackets, no background, no padding, the
    /// label in the accent colour. What TUIkit called plain until SwiftUI's
    /// `.plain` (an undecorated label) took the name.
    ///
    /// Its variant stays `"plain"`: `.controlVariant(.button, …)` scoping
    /// treats every unbordered button alike, as it always has.
    static let borderless = Self(
        foregroundColor: nil,
        isBold: false,
        horizontalPadding: 0,
        isPlain: true,
        variant: "plain"
    )

    /// The plain appearance — no brackets, no background, no padding, and the
    /// label in the ordinary text colour: SwiftUI's plain button "doesn't
    /// style or decorate its content while idle". Focus still shows, as the
    /// bullet in front.
    static let plain = Self(
        foregroundColor: Color.palette.foreground,
        isBold: false,
        horizontalPadding: 0,
        isPlain: true,
        variant: "plain"
    )

    /// The link appearance — plain, and with the focus in the text rather than
    /// in front of it, so a link occupies exactly its own words.
    ///
    /// The variant stays `"plain"`: it is the token `.controlVariant(.button, …)`
    /// scopes on, a link IS a plain button, and an app that styled plain
    /// buttons did not ask for links to fall out of that.
    static let link = Self(
        foregroundColor: nil,
        isBold: false,
        horizontalPadding: 0,
        isPlain: true,
        variant: "plain",
        indicatesFocusInLabel: true
    )
}

// MARK: - Environment

/// Environment key for the button style.
private struct ButtonStyleKey: EnvironmentKey {
    static let defaultValue: any ButtonStyle = _AppearanceButtonStyle.automatic
}

extension EnvironmentValues {
    /// The button style for this environment.
    ///
    /// Controls how ``Button`` views render. Set via the
    /// ``View/buttonStyle(_:)-1qf1r`` modifier — directly by a ``ButtonStyle``, or to
    /// the appearance a built-in ``PrimitiveButtonStyle`` stands for. Default:
    /// the ``DefaultButtonStyle`` appearance. A custom primitive style, while it
    /// is in force, takes precedence over this.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``ButtonStyle``.
    public var buttonStyle: any ButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

// MARK: - Button Style Modifier

extension View {
    /// Sets the style for buttons within this view.
    ///
    /// Apply this modifier to a single ``Button`` or to a container to style
    /// every button it contains:
    ///
    /// ```swift
    /// Button("Delete") { delete() }
    ///     .buttonStyle(.destructive)
    /// ```
    ///
    /// - Parameter style: The button style to apply.
    /// - Returns: A view whose buttons use the specified style.
    @_disfavoredOverload
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        // Disfavoured so `.buttonStyle(.plain)` and its siblings, which name a
        // static on both protocols, resolve to the primitive style.
        //
        // The nearest `.buttonStyle(_:)` wins whichever kind of style it names,
        // so this clears a custom primitive style set further out.
        environment(\.installedButtonAppearance, style)
    }
}

// MARK: - Button Variants & Targeted Text Styling

extension Button {
    /// A built-in button visual variant, used to scope styling to a specific
    /// kind of button via ``View/buttonTextStyle(_:_:)``.
    public enum Variant: Sendable, Hashable {
        /// The default bracketed style (``DefaultButtonStyle``,
        /// ``BorderedButtonStyle``).
        case automatic
        /// The bold, accent-emphasised style (``BorderedProminentButtonStyle``).
        case borderedProminent
        /// The error-coloured style (``DestructiveButtonStyle``).
        case destructive
        /// The success-coloured style (``SuccessButtonStyle``).
        case success
        /// The unbordered styles (``PlainButtonStyle``, ``BorderlessButtonStyle``).
        case plain

        /// The type-erased token stored in `.controlVariant(.button, _)`.
        var token: String {
            switch self {
            case .automatic: return "default"
            case .borderedProminent: return "primary"
            case .destructive: return "destructive"
            case .success: return "success"
            case .plain: return "plain"
            }
        }
    }
}

extension View {
    /// Styles the *text* of every button in this view's subtree (a
    /// `.control(.button)`-scoped style entry).
    ///
    /// ```swift
    /// Sidebar().buttonTextStyle { $0.bold = true; $0.foreground = .green }
    /// ```
    ///
    /// The button's structure (brackets, background, focus glow) is unchanged;
    /// only its label colour/attributes are overridden. A `.destructive` role's
    /// error colour stays load-bearing and is not overridden by a broad entry.
    public func buttonTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.button), build)
    }

    /// Styles the text of buttons of a specific ``Button/Variant`` in this
    /// view's subtree (a `.controlVariant(.button, …)`-scoped entry).
    ///
    /// ```swift
    /// RootView().buttonTextStyle(.automatic) { $0.foreground = .blue }
    /// ```
    public func buttonTextStyle(
        _ variant: Button.Variant, _ build: (inout StyleAttributes) -> Void
    ) -> some View {
        style(.controlVariant(.button, variant.token), build)
    }
}
