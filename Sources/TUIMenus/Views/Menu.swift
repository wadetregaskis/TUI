//  🖥️ TUI — A Terminal UI framework for Swift
//  Menu.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIFoundation

/// A control for presenting a menu of actions — mirrors SwiftUI's `Menu`.
///
/// The items are ordinary `Button`s (and `Divider`s and `Toggle`s), exactly as
/// in SwiftUI, so they carry their own actions, roles and keyboard shortcuts:
///
/// ```swift
/// Menu("Actions") {
///     Button("Rename") { rename() }
///     Button("Duplicate") { duplicate() }
///     Divider()
///     Button("Delete", role: .destructive) { delete() }
/// }
/// ```
///
/// By default the label is a collapsed control that opens the items as a
/// floating menu — Enter or a click opens it, Escape or a click outside closes
/// it, and choosing an item runs its action and closes it. Apply
/// ``View/menuStyle(_:)`` with ``MenuStyle/inline`` to show the
/// items expanded in place under the label instead, which is what a terminal
/// app's landing screen usually wants:
///
/// ```swift
/// Menu("Demos") {
///     Button("Text Styles") { page = .textStyles }
///         .keyboardShortcut("1", modifiers: [])
///     Button("Colors") { page = .colors }
///         .keyboardShortcut("2", modifiers: [])
/// }
/// .menuStyle(.inline)
/// ```
///
/// A row prints its button's key equivalent at its trailing edge, the way a
/// menu item's is drawn on every desktop platform — see
/// ``KeyboardShortcut/displayString``.
///
/// A ``Toggle`` is a row too, drawn as a menu item carrying its own on/off mark
/// rather than as a checkbox sitting in a menu — SwiftUI's shape, and the one a
/// pop-up's row model can hold. Pair it with
/// ``View/menuActionDismissBehavior(_:)`` set to `.disabled` for a menu of
/// SETTINGS, which stays up to be flipped again. See ``Toggle``.
///
/// A `Menu` written in a menu is a SUBMENU of it, as is a `Picker`, as in
/// SwiftUI: a row with the submenu caret (▸) that opens its items beside it.
/// Right or Return opens it, Left or Escape closes it, and the pointer opens
/// it by resting on the row:
///
/// ```swift
/// Menu("Actions") {
///     Button("Duplicate") { duplicate() }
///     Menu("Copy") {
///         Button("Copy") { copy() }
///         Button("Copy Formatted") { copyFormatted() }
///     }
///     Picker("Sort By", selection: $sort) {
///         Text("Name").tag(Sort.name)
///         Text("Date").tag(Sort.date)
///     }
/// }
/// ```
///
/// A `Picker`'s submenu is its options, the selected one checked; written
/// `.pickerStyle(.inline)` it puts them in the menu itself, under its label.
///
/// Typing a row's first characters in an open menu highlights it (type
/// select), as in a `List`: the first character of a prefix gives way to a
/// row's own key equivalent on it.
///
/// A menu with a `primaryAction:` splits its control: the label performs the
/// action, and the menu opens from the caret beside it or by the Down arrow —
/// see ``init(content:label:primaryAction:)``.
nonisolated public struct Menu<Label: View, Content: View>: View {
    let content: Content
    let label: Label

    /// The configuration this menu was made from, by ``init(_:)`` — passed on
    /// whole, its items' child resolution included — or `nil`.
    private var configuration: MenuStyleConfiguration?

    /// What a primary interaction does, from a `primaryAction:` initialiser.
    var primaryAction: (() -> Void)?

    /// Creates a menu with a custom label.
    ///
    /// - Parameters:
    ///   - content: The menu's items — `Button`s, `Toggle`s and `Divider`s,
    ///     and `Menu`s and `Picker`s, which are submenus.
    ///   - label: A view describing the menu.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    @MainActor public var body: some View {
        _MenuStyleBody(
            configuration: configuration ?? MenuStyleConfiguration(
                label: MenuStyleConfiguration.Label(content: AnyView(label)),
                content: MenuStyleConfiguration.Content(
                    content: AnyView(content),
                    // Captured here, where `Content` is still concrete, so the
                    // items can flatten into the style's column — see the
                    // `ChildViewProvider` conformance on the configuration.
                    children: { resolveChildViews(from: content, context: $0) }),
                primaryAction: primaryAction))
    }
}

extension Menu where Label == Text {
    /// Creates a menu that generates its label from a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the menu's title.
    ///   - content: The menu's items — `Button`s, `Toggle`s and `Divider`s.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    /// Creates a menu that generates its label from a string, shown as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The menu's title.
    ///   - content: The menu's items — `Button`s, `Toggle`s and `Divider`s.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(String(title)) }
    }
}

// MARK: - Primary action

extension Menu {
    /// Creates a menu with a custom label and a primary action.
    ///
    /// The label performs `primaryAction` — Return, Space or a click — and the
    /// menu opens from the caret beside it (a click) or from the label by the
    /// Down arrow. Under ``View/menuIndicator(_:)`` `.hidden` the caret goes and
    /// the arrow remains. The menu stays one focus stop.
    ///
    /// ```swift
    /// Menu {
    ///     Button("PDF") { export(.pdf) }
    ///     Button("PNG") { export(.png) }
    /// } label: {
    ///     Text("Export")
    /// } primaryAction: {
    ///     exportAgain()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - content: The menu's items — `Button`s, `Toggle`s and `Divider`s.
    ///   - label: A view describing the menu.
    ///   - primaryAction: The action to perform on primary interaction with
    ///     the menu.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        primaryAction: @escaping () -> Void
    ) {
        self.init(content: content, label: label)
        self.primaryAction = primaryAction
    }
}

extension Menu where Label == Text {
    /// Creates a menu with a localized title and a primary action — see
    /// ``init(content:label:primaryAction:)``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the menu's title.
    ///   - content: The menu's items.
    ///   - primaryAction: The action to perform on primary interaction.
    public init(
        _ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content,
        primaryAction: @escaping () -> Void
    ) {
        self.init(content: content, label: { Text(titleKey) }, primaryAction: primaryAction)
    }

    /// Creates a menu with a title, shown as written, and a primary action —
    /// see ``init(content:label:primaryAction:)``.
    ///
    /// - Parameters:
    ///   - title: The menu's title.
    ///   - content: The menu's items.
    ///   - primaryAction: The action to perform on primary interaction.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void
    ) {
        self.init(content: content, label: { Text(title) }, primaryAction: primaryAction)
    }
}

// MARK: - A title and an SF Symbol

extension Menu where Label == TUIFoundation.Label<Text, _SymbolIcon> {
    /// Creates a menu whose label is a localized title and an SF Symbol.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the menu's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - content: The menu's items.
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { TUIFoundation.Label(titleKey, systemImage: systemImage) }
    }

    /// Creates a menu whose label is a title, shown as written, and an SF
    /// Symbol.
    ///
    /// - Parameters:
    ///   - title: The menu's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - content: The menu's items.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { TUIFoundation.Label(title, systemImage: systemImage) }
    }

    /// Creates a menu whose label is a localized title and an SF Symbol, with a
    /// primary action — see ``init(content:label:primaryAction:)``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the menu's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - content: The menu's items.
    ///   - primaryAction: The action to perform on primary interaction.
    public init(
        _ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content,
        primaryAction: @escaping () -> Void
    ) {
        self.init(
            content: content, label: { TUIFoundation.Label(titleKey, systemImage: systemImage) },
            primaryAction: primaryAction)
    }
}

extension Menu where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
    /// Creates a menu based on a style configuration.
    ///
    /// Use it inside a ``MenuStyle``'s ``MenuStyle/makeBody(configuration:)``
    /// to draw the menu as the style outside the custom one would, and add to
    /// it:
    ///
    /// ```swift
    /// struct RedBorderMenuStyle: MenuStyle {
    ///     func makeBody(configuration: Configuration) -> some View {
    ///         Menu(configuration)
    ///             .border(.red)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter configuration: The menu's label and items.
    public init(_ configuration: MenuStyleConfiguration) {
        self.label = configuration.label
        self.content = configuration.content
        self.configuration = configuration
    }
}

// MARK: - Style bridge

/// Renders whichever ``MenuStyle`` is in force.
///
/// `Renderable` because the style is held as an existential: opening it to call
/// ``MenuStyle/makeBody(configuration:)`` needs the buffer-returning bridge, the
/// same shape `Button` uses for `ButtonStyle`.
private struct _MenuStyleBody: View, Renderable, Layoutable {
    let configuration: MenuStyleConfiguration

    var body: Never {
        fatalError("_MenuStyleBody renders via Renderable")
    }

    /// Measured through the style's own body rather than by rendering this menu
    /// and discarding the buffer — the same trade ``Button`` makes, and sound
    /// for the same reason: ``MenuStyle/makeBuffer(configuration:context:)`` is
    /// `renderToBuffer(makeBody(configuration:))` and lives in an extension, not
    /// a protocol requirement, so every style's buffer is its body's buffer.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let style = context.environment.menuStyle
        // A body that cannot size itself is going to be drawn to be measured
        // whichever way it is asked; going through the style would only build
        // it twice for the same answer.
        guard style.bodyCanMeasureItself else {
            return measureFixedByRendering(self, proposal: proposal, context: context)
        }
        return style.makeSize(configuration: configuration, proposal: proposal, context: bodyContext(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.environment.menuStyle.makeBuffer(configuration: configuration, context: bodyContext(context))
    }

    /// The context the style's body draws in: one that sees the style outside
    /// it, so a `Menu(configuration)` in a custom style's body draws as that
    /// style would rather than recursing into this one.
    private func bodyContext(_ context: RenderContext) -> RenderContext {
        var body = context
        body.environment.menuStyleChain = context.environment.menuStyleChain.inside
        return body
    }
}
