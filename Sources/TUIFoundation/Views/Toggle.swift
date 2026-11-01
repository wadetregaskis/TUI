//  🖥️ TUI — A Terminal UI framework for Swift
//  Toggle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ToggleStyle Protocol

/// The appearance and behavior of a toggle.
///
/// To configure the style for a single `Toggle` or for all toggle instances
/// in a view hierarchy, use the `toggleStyle(_:)` modifier.
///
/// ## Built-in Styles
///
/// | Style | Description |
/// |-------|-------------|
/// | `.automatic` | Platform default (checkbox in TUI) |
/// | `.checkbox` | Classic checkbox |
/// | `.switch` | A two-position switch — a coloured track with a knob |
///
/// > Note: `.automatic` and `.checkbox` both draw a checkbox. `.switch` does
/// > NOT — it draws a two-position switch: a coloured track with a two-cell
/// > knob on the side it points to, over a distinct background. `_ToggleCore`
/// > branches on `is SwitchToggleStyle` to pick it. The *glyphs* of the
/// > checkbox (■/□ or ⬛︎/⬜︎ or `[x]`/`[ ]` — see `ToggleCharacterSet`) are a separate,
/// > TUI-specific choice — see ``ToggleCharacterSet`` and
/// > ``View/toggleCharacterSet(_:)``.
///
/// ## Control size
///
/// A checkbox is a glyph and a gap, and a switch a three-cell track: neither
/// has padding to trim at `.small` or caps to drop at `.mini`, and a gap or a
/// track grown at `.large` would say nothing more, so both draw alike at every
/// ``ControlSize`` — SwiftUI changes only their size, which a terminal's cell
/// fixes. ``ButtonToggleStyle`` draws a bordered button's face, and follows the
/// button's table.
///
/// ## Custom styles
///
/// Conform to `ToggleStyle` and implement ``makeBody(configuration:)`` to draw a
/// toggle however you like (a different glyph, an `ON`/`OFF` word, …). The
/// built-in styles above don't implement `makeBody` — they render procedurally
/// (with the focus glow and ``ToggleCharacterSet`` glyphs); only custom styles use it.
///
/// ## Styles and the render cache
///
/// ``View/toggleStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all.
///
/// All three built-in styles are therefore `Equatable`. Without that, a single
/// `.toggleStyle(...)` turned the cache off for everything below it — the
/// toggle's label, and whatever ``Toggle/toggleContent(_:)`` puts under it. None
/// of them holds anything, so `==` within a type is vacuously true and every
/// instance of one styles a toggle identically. Between types it is the
/// downcast in the comparison that answers, which is what a toggle needs: the
/// style's dynamic type is the whole of what it contributes to the drawing, so
/// a checkbox replaced by a switch must read as a change, and does.
///
/// A custom style need not conform: one that does not simply turns memoization
/// off below itself, which costs render time rather than correctness.
///
/// - Note: SwiftUI's toggle styles declare no such conformance, and this is one
///   of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUI re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol ToggleStyle: Sendable {
    /// A view representing the toggle's appearance.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a toggle.
    ///
    /// - Parameter configuration: The properties of the toggle being styled.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a toggle.
    typealias Configuration = ToggleStyleConfiguration
}

extension ToggleStyle {
    /// Default body for the built-in marker styles, which TUI renders
    /// procedurally rather than through `makeBody`. A custom style overrides it.
    @MainActor public func makeBody(configuration: Configuration) -> EmptyView {
        EmptyView()
    }

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any ToggleStyle` existential so ``makeBody(configuration:)`` can
    /// return its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(
            observingStyleBody(of: Self.self, kind: .styleRender, context: context) {
                makeBody(configuration: configuration)
            }, context: context)
    }
}

/// The properties of a toggle, passed to a ``ToggleStyle`` so it can produce the
/// toggle's appearance.
///
/// You don't create this — TUI builds one per ``Toggle`` and hands it to a
/// custom style's ``ToggleStyle/makeBody(configuration:)``. Mirrors SwiftUI's
/// `ToggleStyleConfiguration` (`label`, `isOn`) plus terminal-specific focus /
/// hover / enabled flags, exactly as ``ButtonStyleConfiguration`` does, because
/// toggle rendering is procedural.
public struct ToggleStyleConfiguration {
    /// A type-erased label of a toggle.
    public typealias Label = AnyView

    /// A view that describes the effect of switching the toggle between states.
    public let label: Label

    /// Whether the toggle is currently on — and, through `$isOn`, a binding to
    /// it, as in SwiftUI: `configuration.isOn.toggle()` flips the toggle.
    @Binding public var isOn: Bool

    /// Whether the toggle is in a mixed state: one standing for several values
    /// that disagree. `false` for a toggle bound to one value.
    public var isMixed: Bool

    /// Whether the toggle currently holds keyboard focus. (Terminal-specific
    /// addition, like ``ButtonStyleConfiguration/isFocused``.)
    public let isFocused: Bool

    /// Whether the cursor is hovering over the toggle. (Terminal-specific.)
    public let isHovered: Bool

    /// Whether the toggle is enabled. (Terminal-specific.)
    public let isEnabled: Bool

    init(
        label: Label, isOn: Binding<Bool>, isMixed: Bool = false,
        isFocused: Bool, isHovered: Bool, isEnabled: Bool
    ) {
        self.label = label
        self._isOn = isOn
        self.isMixed = isMixed
        self.isFocused = isFocused
        self.isHovered = isHovered
        self.isEnabled = isEnabled
    }
}

/// What a toggle built with ``Toggle/init(_:)`` was told about the toggle it
/// draws for: that it is such a stand-in, and the state of the real one. One
/// byte, so `Toggle` stays free of padding (`ControlLayoutPaddingTests`).
struct ToggleProxy: OptionSet, Sendable {
    let rawValue: UInt8

    /// This toggle draws for another, which holds the focus, keys and click.
    static let isProxy = Self(rawValue: 1 << 0)
    static let isFocused = Self(rawValue: 1 << 1)
    static let isHovered = Self(rawValue: 1 << 2)
    static let isEnabled = Self(rawValue: 1 << 3)
    /// On for some of what the toggle stands for and off for the rest: a
    /// configuration that says so, or `Toggle(sources:isOn:)` over mixed values.
    static let isMixed = Self(rawValue: 1 << 4)
}

// MARK: - Built-in Toggle Styles

/// The default toggle style.
///
/// In TUI this is a checkbox; its glyphs come from ``ToggleCharacterSet`` (■/□ by default; ⬛︎/⬜︎ under Terminal.app
/// by default).
///
/// `Equatable` for the reason given under ``ToggleStyle``: a memo below a value
/// the render cache cannot compare declines to cache. It holds nothing, so
/// every instance styles a toggle identically.
public struct DefaultToggleStyle: ToggleStyle, Equatable {
    public init() {}

    /// The toggle in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(self)
    }
}

/// A toggle style that displays a checkbox followed by its label.
///
/// ```
/// □ Label     (OFF)
/// ■ Label     (ON)
/// ```
///
/// The checkbox glyphs are configurable via ``ToggleCharacterSet`` (e.g.
/// `.toggleCharacterSet(.ascii)` for `[ ]` / `[x]`).
///
/// `Equatable` on the same terms as ``DefaultToggleStyle``, and the two draw the
/// same checkbox, so the worst a comparison between them can do is drop a cache
/// entry that would have been good.
public struct CheckboxToggleStyle: ToggleStyle, Equatable {
    public init() {}

    /// The toggle in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(self)
    }
}

/// A toggle style that displays the toggle as a two-position switch.
///
/// In TUI this renders a coloured track with a two-cell knob on the side the
/// switch points to — left for off, right for on — over a distinct background
/// (the accent colour when on), so it reads as a switch rather than a checkbox.
///
/// Off, the track is the palette's tertiary foreground tone, moved as little as it
/// takes to stand off both the page, which the knob is drawn in, and the accent. A
/// disabled switch fades that track halfway toward the page.
///
/// That is the switch where controls are filled, the default. Under
/// `.controlStyle(.lines)` it is a knob between the caps of the
/// ``ButtonBorderShape`` in force, four cells in every shape: `(○ )` / `( ●)` in
/// a capsule, `⦗● ⦘` / `⦗ ●⦘` in a rounded rectangle, `│● │` / `│ ●│` with
/// square corners. The caps breathe the accent while it holds the focus, and the
/// knob is the accent when on. Under Braille it takes the shape's dotted ends,
/// and under `.blank` it is the knob alone.
///
/// `Equatable` on the same terms as ``DefaultToggleStyle``, and this is the one
/// whose type changes what gets drawn: `_ToggleCore` picks the track over the
/// checkbox on `is SwitchToggleStyle` alone. A frame that swaps a checkbox style
/// for this one is a change, and the comparison's downcast is what says so.
public struct SwitchToggleStyle: ToggleStyle, Equatable {
    public init() {}

    /// The toggle in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(self)
    }
}

/// A toggle style that displays as a button with its label as the title: the
/// bracketed button, drawn bold and in the accent colour while the toggle is on.
public struct ButtonToggleStyle: ToggleStyle, Equatable {
    /// Creates a button toggle style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // Bold as well as accented while on: a view label takes the colour of
        // the prominent appearance but not its weight, and colour alone is a
        // faint way to say a button is pressed in.
        _ButtonStyleBody(
            configuration: ButtonStyleConfiguration(
                title: "",
                labelView: configuration.isOn ? AnyView(configuration.label.bold()) : configuration.label,
                role: nil, isPressed: false,
                isFocused: configuration.isFocused, isHovered: configuration.isHovered,
                isEnabled: configuration.isEnabled, keyboardShortcut: nil),
            appearance: configuration.isOn ? .primary : .default)
    }
}

// MARK: - ToggleStyle Static Extensions

extension ToggleStyle where Self == ButtonToggleStyle {
    /// A toggle style that displays as a button with its label as the title.
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

extension ToggleStyle where Self == DefaultToggleStyle {
    /// The default toggle style.
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    /// A toggle style that displays a checkbox followed by its label.
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    /// A toggle style that displays a leading label and a trailing switch.
    ///
    /// > Note: In TUI this draws a coloured track with a two-cell knob, not
    /// > a checkbox.
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

// MARK: - Environment Key

/// Environment key for toggle style.
private struct ToggleStyleKey: EnvironmentKey {
    static var defaultValue: StyleChain<any ToggleStyle> { StyleChain(DefaultToggleStyle()) }
}

extension EnvironmentValues {
    /// The toggle style for this environment.
    ///
    /// Setting it puts a style in force over the one before, which a custom
    /// style's ``Toggle/init(_:)`` then draws with.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``ToggleStyle``.
    public var toggleStyle: any ToggleStyle {
        get { self[ToggleStyleKey.self].style }
        set { self[ToggleStyleKey.self] = self[ToggleStyleKey.self].pushing(newValue) }
    }

    /// The style in force and the ones outside it — what ``Toggle/init(_:)``
    /// inside a custom style's body draws with. See ``StyleChain``.
    var toggleStyleChain: StyleChain<any ToggleStyle> {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }
}

// MARK: - Toggle Style Modifier

extension View {
    /// Sets the style for toggles within this view.
    ///
    /// Use this modifier to set a specific style for all toggles within a view:
    ///
    /// ```swift
    /// VStack {
    ///     Toggle("Option 1", isOn: $option1)
    ///     Toggle("Option 2", isOn: $option2)
    /// }
    /// .toggleStyle(.checkbox)
    /// ```
    ///
    /// > Note: `.automatic` and `.checkbox` draw a checkbox, whose glyphs are set
    /// > separately via ``ToggleCharacterSet``; `.switch` draws a two-position
    /// > switch, a coloured track with a knob on the side it points to.
    ///
    /// - Parameter style: The toggle style to use.
    /// - Returns: A view with the toggle style set.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        environment(\.toggleStyle, style)
    }

    /// Styles the *label* text of every toggle in this view's subtree (a
    /// `.control(.toggle)`-scoped style entry). The checkbox indicator is
    /// unaffected.
    ///
    /// ```swift
    /// SettingsForm().toggleTextStyle { $0.italic = true }
    /// ```
    public func toggleTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.toggle), build)
    }
}

// MARK: - Toggle

/// A control that toggles between on and off states.
///
/// You create a toggle by providing an `isOn` binding and a label:
///
/// ```swift
/// @State private var isEnabled = false
///
/// Toggle("Enable notifications", isOn: $isEnabled)
/// ```
///
/// ## Rendering
///
/// ```
/// □ Label     (OFF - dimmed)
/// ■ Label     (ON - accent color)
/// ```
///
/// The checkbox glyphs are configurable — see ``ToggleCharacterSet``.
///
/// When focused, the brackets pulse in the accent color.
///
/// ## Styling
///
/// Use the `toggleStyle(_:)` modifier to customize appearance:
///
/// ```swift
/// Toggle("Option", isOn: $isOn)
///     .toggleStyle(.checkbox)
/// ```
///
/// Available styles: `.automatic`, `.checkbox`, `.switch`
///
/// > Note: In TUI `.automatic` and `.checkbox` draw a checkbox; `.switch`
/// > draws a two-position switch.
///
/// ## Inside a pop-up menu
///
/// A toggle written inside a pop-up ``Menu`` or a `.contextMenu` is a menu ROW,
/// not a checkbox drawn in a column of rows: it takes the row's own look — the
/// highlight bar spanning the menu's interior, the key-equivalent column at the
/// trailing edge, the hover wash — with its on/off mark where a `Button` row has
/// nothing. That is SwiftUI's shape as well, and it is what makes it reachable:
/// a pop-up's rows are not focus stops, they are ordinals claimed from the menu,
/// and a control that does not claim one draws on a line the arrows and the
/// click map both walk past. Choosing the row flips the binding and closes the
/// menu; ``View/menuActionDismissBehavior(_:)`` set to `.disabled` is what makes
/// it a sticky toggle instead.
///
/// Two things have no row to draw into and so do not apply there: a custom
/// ``ToggleStyle`` (a menu draws menu items, as SwiftUI's does) and
/// ``Toggle/toggleContent(_:)`` (a menu row is one row; put the controls it
/// governs on the page). An INLINE menu is unaffected — its rows really are page
/// focus stops, so a toggle in one is the ordinary control.
public struct Toggle<Label: View>: View {
    // Declared so a toggle titled with a string has no padding: the per-pass
    // memos key a view by a hash of its bytes, and padding is whatever the
    // memory held before — skipped by the hash, where a type with none is
    // plain words. The two word-sized fields, then the label, then the
    // binding, and the one-byte flags last: none over a `Text`, whose 56 bytes
    // end on a word boundary (208 → 198 bytes; `ControlLayoutPaddingTests`).
    // The flag sat between the label and the binding while a `Text` was 55
    // bytes, filling the byte it ended one short of. Another label's size can
    // still leave a gap before the binding.

    /// The unique focus identifier.
    var focusID: String?

    /// Builds the controls this toggle governs, drawn under it — `nil` for a
    /// toggle that governs nothing but its own value. See
    /// ``Toggle/toggleContent(_:)``.
    var content: (@MainActor () -> AnyView)?

    /// The label view.
    let label: Label

    /// The binding to the toggle's boolean state.
    let isOn: Binding<Bool>

    /// Whether the toggle is disabled.
    var isDisabled: Bool

    /// Set by ``init(_:)``: this toggle only draws, for the one whose style's
    /// body it is in. Last, and one byte, so the layout above keeps no padding.
    var proxy: ToggleProxy = []

    public var body: some View {
        _ToggleCore(
            focusID: focusID,
            content: content,
            label: label,
            isDisabled: isDisabled,
            isOn: isOn,
            proxy: proxy
        )
    }
}

// MARK: - Toggle Initializer (Configuration)

extension Toggle where Label == ToggleStyleConfiguration.Label {
    /// Creates a toggle based on a toggle style configuration.
    ///
    /// Use it inside a ``ToggleStyle``'s ``ToggleStyle/makeBody(configuration:)``
    /// to draw the toggle the style was applied over — the style in force
    /// outside it, not the style itself — and add to it:
    ///
    /// ```swift
    /// struct RedBorderToggleStyle: ToggleStyle {
    ///     func makeBody(configuration: Configuration) -> some View {
    ///         Toggle(configuration)
    ///             .border(.red)
    ///     }
    /// }
    /// ```
    ///
    /// It draws the toggle as the configuration describes it — on or off,
    /// focused or not — and takes no focus, keys or click of its own: those
    /// belong to the toggle whose style this is, which is still one control.
    ///
    /// - Parameter configuration: The properties of the toggle being styled.
    public init(_ configuration: ToggleStyleConfiguration) {
        self.isOn = configuration.$isOn
        self.label = configuration.label
        self.focusID = nil
        self.isDisabled = !configuration.isEnabled
        self.content = nil
        var proxy: ToggleProxy = [.isProxy]
        if configuration.isFocused { proxy.insert(.isFocused) }
        if configuration.isHovered { proxy.insert(.isHovered) }
        if configuration.isEnabled { proxy.insert(.isEnabled) }
        if configuration.isMixed { proxy.insert(.isMixed) }
        self.proxy = proxy
    }
}

// MARK: - Toggle Initializers (String Label)

extension Toggle where Label == Text {
    /// Creates a toggle with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the toggle's label.
    ///   - isOn: A binding to the toggle's boolean state.
    public init(
        _ titleKey: LocalizedStringKey,
        isOn: Binding<Bool>
    ) {
        self.isOn = isOn
        self.label = Text(titleKey)
        self.focusID = nil
        self.isDisabled = false
        self.content = nil
    }

    /// Creates a toggle with a string label, displayed as written.
    ///
    /// - Parameters:
    ///   - title: The toggle's label text.
    ///   - isOn: A binding to the toggle's boolean state.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        isOn: Binding<Bool>
    ) {
        self.isOn = isOn
        self.label = Text(String(title))
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.content = nil
    }
}

// MARK: - Toggle Initializers (ViewBuilder Label)

extension Toggle {
    /// Creates a toggle with a custom label.
    ///
    /// - Parameters:
    ///   - isOn: A binding to the toggle's boolean state.
    ///   - label: A view that describes the purpose of the toggle.
    public init(
        isOn: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) {
        self.isOn = isOn
        self.label = label()
        self.focusID = nil
        self.isDisabled = false
        self.content = nil
    }
}

// MARK: - Toggle Modifiers

extension Toggle {
    /// Creates a disabled version of this toggle.
    ///
    /// - Parameter disabled: Whether the toggle is disabled.
    /// - Returns: A new toggle with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Toggle {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// The controls this toggle governs, drawn under it and live only while it
    /// is on.
    ///
    /// ```swift
    /// Toggle("Edge lines", isOn: $edgeLines)
    ///     .toggleContent {
    ///         Slider(value: $threshold, in: 0.3...2.0, step: 0.1) { Text("Threshold") }
    ///     }
    /// ```
    ///
    /// ```
    ///   ■ Edge lines
    ///     Threshold ◀ ━━━━━━●──────── ▶ 0.9
    /// ```
    ///
    /// A switch that turns something on nearly always has that something's
    /// settings beside it, and stacking them by hand gets the two things this
    /// does right wrong: the indent has to be the INDICATOR's width, which is
    /// a `ToggleCharacterSet` resolved against the terminal at render time
    /// (`■` is one cell, `⬛︎` two, `[x]` three) — a hardcoded two lines the
    /// content up under the box on some terminals and under the label on
    /// others. And the content has to be disabled while the toggle is off, or
    /// the keyboard walks into settings for something that is not happening.
    ///
    /// The content is always DRAWN, on or off, so the rows below the toggle do
    /// not move as it is flipped. What changes is whether it is live — and a
    /// disabled control is not a focus stop, so **Tab** from the toggle reaches
    /// its content exactly when that content applies. Same shape, and the same
    /// reasoning, as ``RadioButtonItem``'s per-option content.
    ///
    /// - Note: A custom ``ToggleStyle`` draws its own indicator, and there is
    ///   nothing there for this to measure, so content under one is not
    ///   indented.
    ///
    /// - Parameter content: The controls this toggle governs.
    /// - Returns: A toggle that carries `content` beneath it.
    @MainActor
    public func toggleContent<Content: View>(
        @ViewBuilder _ content: @escaping () -> Content
    ) -> Toggle {
        var copy = self
        copy.content = { AnyView(content()) }
        return copy
    }

    /// Sets a custom focus identifier for this toggle.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A toggle with the specified focus identifier.
    public func focusID(_ id: String) -> Toggle {
        var copy = self
        copy.focusID = id
        return copy
    }
}
