//  🖥️ TUI — A Terminal UI framework for Swift
//  Link.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Link

/// A control that opens a URL when activated.
///
/// Mirrors SwiftUI's `Link`. In a terminal a link is focusable like a button:
/// Tab to it and press Enter/Space, or click it, to activate it — the
/// destination goes to the environment's ``OpenURLAction`` and a popover shows
/// it to read or copy. By default that action launches NOTHING: the system
/// opener is off unless the session is declared local (see ``OpenURLAction``
/// for why), so the popover, and the OSC 8 hyperlink the label carries for a
/// terminal that honours one, are what the user gets. The
/// label is tinted with the accent colour and underlined so it reads as a link
/// — regardless of the label form. Turn the underline off for a subtree with
/// ``View/linkUnderline(_:)``.
///
/// A right-click on the link — or Shift+F10 while it holds the focus — opens
/// its context menu: Show Link, which raises the popover, Copy Link, Copy
/// Label where the words it shows are not its address, and Copy as Markdown;
/// a right-click on the destination's popover offers Copy Link. A link that
/// writes its URL on the row has the same menu less Show Link, on a
/// right-click. ``View/linkActivation(_:)`` makes
/// activating a link copy its destination instead. TUI-specific: SwiftUI's
/// `Link` has none, but a Mac's text view offers Copy Link on a
/// link in it, and a terminal's user has no browser's address bar to copy
/// from.
///
/// That is the default ``LinkDisplay/popover`` mode. In the two modes that
/// write the URL onto the row — ``LinkDisplay/urlOnly`` and
/// ``LinkDisplay/urlInParentheses`` — the link is **not a control**: it takes
/// no place in the Tab order and no click, because activation would have
/// nothing left to do that the row does not already do. It is a tinted,
/// underlined, hyperlinked label, and any interaction it should have is the
/// caller's to add — `.focusable()`, `.onTapGesture`, `.onKeyEvent` — the way
/// it would be added to any other text.
///
/// ```swift
/// Link("Documentation", destination: URL(string: "https://example.com")!)
///
/// Link(destination: URL(string: "https://example.com")!) {
///     Label("Docs", systemImage: "book")
/// }
/// ```
///
/// > Note: SwiftUI's `Link` is accent-coloured but **not** underlined by
/// > default. Underlining by default is an intentional terminal-readability
/// > deviation — a hyperlink in a terminal has no hover/pointer affordance, so
/// > the underline is what marks it as a link. Opt out with `.linkUnderline(false)`.
///
/// > Note: On a terminal measured to honour them, the label also carries a real
/// > **OSC 8 hyperlink** (see `TerminalHyperlink`), which tells the
/// > terminal where those cells point — so the URL can be shown on hover and
/// > copied, even though the label says "Documentation" and the destination is
/// > nowhere on screen. That is the part keyboard and mouse activation cannot
/// > give a link. Whether the terminal will also OPEN it on a modified click
/// > depends on the host, because a TUI app holds mouse reporting open and
/// > iTerm2 is measured to forward ⌘-click to the application instead — see
/// > `TerminalHyperlink`. Everything else still works everywhere,
/// > Terminal.app included. Turn the escape off with
/// > ``View/terminalHyperlinks(_:)``, which an app that intercepts its own URL
/// > scheme in ``OpenURLAction`` may well want.
public struct Link<Label: View>: View {
    let destination: URL
    let label: Label

    /// Creates a link with a custom label.
    ///
    /// - Parameters:
    ///   - destination: The URL to open when the link is activated.
    ///   - label: A view builder producing the link's label.
    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: some View {
        _Link(destination: destination, label: label)
    }
}

// MARK: - String-titled convenience

extension Link where Label == Text {
    /// Creates a link with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title shown for the link.
    ///   - destination: The URL to open when the link is activated.
    public init(_ titleKey: LocalizedStringKey, destination: URL) {
        self.destination = destination
        self.label = Text(titleKey)
    }

    /// Creates a link with a string title, shown as written.
    ///
    /// - Parameters:
    ///   - title: The title shown for the link.
    ///   - destination: The URL to open when the link is activated.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.destination = destination
        // The underline is applied uniformly in `_Link` from the environment,
        // so string- and view-labelled links look the same and both honour
        // `.linkUnderline(_:)`.
        self.label = Text(String(title))
    }
}

// MARK: - Underline styling

private struct LinkUnderlineKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether ``Link`` labels are underlined. Set via
    /// ``View/linkUnderline(_:)``. Default: `true` — an intentional
    /// deviation from SwiftUI (whose links are accent-coloured only) so links
    /// read as links without a pointer/hover affordance.
    public var linkUnderline: Bool {
        get { self[LinkUnderlineKey.self] }
        set { self[LinkUnderlineKey.self] = newValue }
    }
}

extension View {
    /// Sets whether ``Link`` labels within this view are underlined.
    ///
    /// TUI underlines links by default so they read as links in a terminal.
    /// Turn it off for a whole subtree:
    ///
    /// ```swift
    /// VStack {
    ///     Link("Home", destination: home)
    ///     Link("Docs", destination: docs)
    /// }
    /// .linkUnderline(false)
    /// ```
    ///
    /// - Parameter enabled: Whether links are underlined (default `true`).
    /// - Returns: A view whose links honour the underline setting.
    public func linkUnderline(_ enabled: Bool = true) -> some View {
        environment(\.linkUnderline, enabled)
    }
}

// MARK: - Terminal hyperlinks

/// How a focused ``Link`` shows that it holds the focus.
///
/// See ``View/linkFocusIndicator(_:)``.
public enum LinkFocusIndicator: Sendable, Equatable, CaseIterable {
    /// The label's own words breathe in the accent, and nothing is reserved
    /// beside them — so a link occupies exactly its own text and sits inside a
    /// sentence like any other words. The default.
    case text

    /// A pulsing `●` in two reserved cells before the label — the affordance
    /// every other plain button uses, and what keeps a COLUMN of links aligned
    /// as the focus moves down it.
    case bullet
}

private struct LinkFocusIndicatorKey: EnvironmentKey {
    static let defaultValue = LinkFocusIndicator.text
}

private struct TerminalHyperlinksKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether ``Link`` also emits an OSC 8 terminal hyperlink. Set via
    /// ``View/terminalHyperlinks(_:)``. Default: `true` — which still emits
    /// nothing on a host not measured to honour them, because the two
    /// conditions are ANDed (see `TerminalHyperlink/isSupported`).
    public var terminalHyperlinks: Bool {
        get { self[TerminalHyperlinksKey.self] }
        set { self[TerminalHyperlinksKey.self] = newValue }
    }

    /// How a focused ``Link`` says so — see
    /// ``View/linkFocusIndicator(_:)``.
    public var linkFocusIndicator: LinkFocusIndicator {
        get { self[LinkFocusIndicatorKey.self] }
        set { self[LinkFocusIndicatorKey.self] = newValue }
    }
}

extension View {
    /// Sets whether ``Link`` views within this view attach a real terminal
    /// hyperlink to their labels.
    ///
    /// The escape tells the TERMINAL where a label points, which is how a URL
    /// nobody can see becomes one anybody can copy — and the reason an app
    /// might still want it off is the other half: wherever the terminal opens
    /// a link itself, it does so over the top of ``OpenURLAction``, so an app
    /// that intercepts its own URL scheme would find those links handled by
    /// somebody else:
    ///
    /// ```swift
    /// VStack {
    ///     Link("Open ticket", destination: URL(string: "myapp://ticket/42")!)
    /// }
    /// .terminalHyperlinks(false)   // this scheme is ours to open
    /// ```
    ///
    /// - Parameter enabled: Whether links carry the escape (default `true`).
    /// - Returns: A view whose links honour the setting.
    public func terminalHyperlinks(_ enabled: Bool = true) -> some View {
        environment(\.terminalHyperlinks, enabled)
    }

    /// How a focused ``Link`` says so.
    ///
    /// The default is ``LinkFocusIndicator/text`` — the words themselves
    /// breathe in the accent — because a link is written inside a sentence and
    /// a control that reserves two columns for a bullet cannot be. It is the
    /// same clock and the same frames as every other focus affordance in the
    /// framework; only the cells differ.
    ///
    /// ``LinkFocusIndicator/bullet`` is the plain-button affordance: a pulsing
    /// `●` in two reserved cells before the label. Right for a column of links
    /// on their own lines, where the reservation is what keeps them aligned as
    /// the focus moves; wrong for four words in a paragraph.
    ///
    /// ```swift
    /// VStack(alignment: .leading) {
    ///     Link("swift.org", destination: swiftOrg)
    ///     Link("apple/swift", destination: repo)
    /// }
    /// .linkFocusIndicator(.bullet)
    /// ```
    ///
    /// TUI-specific: SwiftUI draws focus rings the terminal has no equivalent
    /// for, so there is no signature to match.
    public func linkFocusIndicator(_ indicator: LinkFocusIndicator) -> some View {
        environment(\.linkFocusIndicator, indicator)
    }
}

/// Attaches an OSC 8 hyperlink to every line of the content's rendered buffer.
///
/// **One balanced pair per LINE**, rather than one spanning the whole buffer,
/// and that is the load-bearing choice. A hyperlink is a property of cells,
/// and a buffer's lines are laid out and clipped independently — so a pair
/// that opened on the first row and closed on the last would be split by any
/// container that clipped between them, leaving the link open at a row's end
/// and running under everything drawn after it. Per line, every row is
/// self-contained: the pair survives compositing, padding and alignment
/// because none of those can put anything between an opening sequence and its
/// close on the same row, and the clip walks close it at the cut
/// (`HyperlinkScan`).
///
/// The cost is that a label spanning several rows becomes several links, which
/// is what the `id` parameter is for — a host that implements it treats runs
/// sharing an id as one link and highlights them together. It is emitted only
/// when there IS more than one row: a single-run link needs no identity, and
/// the parameter is bytes on every frame.
private struct TerminalHyperlinkModifier: BufferModifier {
    /// Its content stays where it is laid out — a hyperlink marks the cells its label drew, where they are — so a guide inside it
    /// passes unmoved (``BufferModifier/_keepsContentGeometry``).
    static var _keepsContentGeometry: Bool { true }

    let destination: URL
    let enabled: Bool

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        // `isEnabled` too: a disabled link is skipped by Tab, registers no hit
        // region and never runs its action — and a terminal that honours OSC 8
        // opens a linked cell on its OWN gesture, past every one of those. The
        // dimmed label must carry no destination for it to open.
        guard enabled, context.environment.isEnabled, TerminalHyperlink.isSupported,
            !buffer.lines.isEmpty
        else { return buffer }
        let link = TerminalHyperlink(
            destination: destination.absoluteString,
            id: buffer.lines.count > 1 ? context.identity.path : nil,
            localHostName: TerminalClient.localHostName)
        // `nil` for a destination too long for a terminal to keep: the label
        // draws as it is, and activating it still raises the destination.
        guard let opening = link.opening else { return buffer }
        func linked(_ line: String) -> String {
            // An empty row has no cells to carry the link, so it gets no
            // sequences: they would be bytes on every frame saying nothing.
            line.isEmpty ? line : opening + line + TerminalHyperlink.closing
        }
        // The widths are unchanged by construction — every scan in this
        // framework counts an escape as the zero cells it paints — so they are
        // carried across rather than re-measured.
        var result = buffer.replacingLines(
            buffer.lines.map(linked), width: buffer.width,
            uniformWidth: buffer.linesAreUniformWidth, lineWidths: buffer.lineWidths)
        // The run frames too, not only the lines. A focused link breathes by
        // REPLACING its cells with pre-rendered frames, and the splice closes
        // whatever link is open at the cut — so a frame without its own pair
        // stripped the hyperlink from exactly the link the user had selected,
        // on the first tick, until focus moved away and a full render repainted
        // the row.
        //
        // The per-frame alpha comes along unchanged: the escapes cost no cells and
        // its spans are run-relative, so it is still true of the linked frames. It
        // is also the only statement of what those cells owe, so rebuilt without
        // it, a caret over a faded well inside a link replayed at full strength.
        result.animatedCells = result.animatedCells.map { run in
            run.replacingFrames(run.frames.map(linked), alpha: run.alpha)
        }
        return result
    }
}

// MARK: - Internal

/// Swallows the repeats a held Enter produces on a link.
///
/// A held key auto-repeats in the terminal, and in a legacy encoding the
/// application receives a stream of Enter presses with nothing to tell a
/// repeat from a press, so every one of them is a real activation. A `Button`
/// takes them all there — holding Return on a `+` keeps counting — and where
/// the terminal reports repeats (the kitty keyboard protocol) acts on them as
/// its `buttonRepeatBehavior` says, once under `.automatic`. Every repeat is
/// exactly wrong for a link, where each is another browser window, or under a
/// custom `OpenURLAction` another request. So a link swallows them on every
/// terminal, and only a link: nothing here reaches `Button`.
///
/// A window rather than a count, because the two cases differ in TIMING and in
/// nothing else — a key repeat arrives every few tens of milliseconds, and two
/// deliberate presses do not. 700 ms is the figure `AutoRepeatTimer` and
/// `ScrollbarRenderer` already agree on for "one gesture, not two", measured
/// against a careful click on a one-cell arrow; the same question deserves the
/// same answer.
final class LinkActivationGate {
    private var lastNanos: UInt64 = 0

    /// Milliseconds within which a second activation is a key repeat rather
    /// than a second press — ``AutoRepeatTimer/defaultInitialDelayMs``,
    /// because a link and a stepper arrow must not disagree about where one
    /// gesture ends.
    static var windowMs: Int { AutoRepeatTimer.defaultInitialDelayMs }

    func allows(nowNanos: UInt64) -> Bool {
        let window = UInt64(Self.windowMs) * 1_000_000
        // `lastNanos == 0` is the first activation of this link's life, which
        // must always pass however early in the process it lands.
        guard lastNanos != 0, nowNanos &- lastNanos < window else {
            lastNanos = nowNanos
            return true
        }
        // A swallowed repeat moves the anchor too, so the window SLIDES with
        // the hold: a held key is one activation however long it is held, not
        // one every 700 ms. (What that costs: a deliberate second press must
        // come 700 ms after the last REPEAT rather than the last accepted
        // press — which is what "one gesture" means everywhere else here.)
        lastNanos = nowNanos
        return false
    }
}

/// Reads ``OpenURLAction`` from the environment and drives a plain, accent-tinted
/// button — reusing all of `Button`'s focus, keyboard, mouse, and disabled
/// handling — whose action opens the destination.
private struct _Link<Label: View>: View {
    let destination: URL
    let label: Label

    /// Persisted across frames, because the whole question is what happened on
    /// the PREVIOUS activation — a gate rebuilt each render would let every
    /// repeat through.
    @State private var gate = LinkActivationGate()

    /// Whether the destination popover is up. Activating the link raises it,
    /// which is what activation DOES now — see the comment on `body`.
    @State private var showingDestination = false

    /// The words the label drew last, for the context menu's copies.
    @State private var labelText = LinkLabelText()

    @Environment(\.openURL) private var openURL
    @Environment(\.clipboardAccess) private var clipboard
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.linkActivation) private var activation
    @Environment(\.linkUnderline) private var underline
    @Environment(\.terminalHyperlinks) private var terminalHyperlinks
    @Environment(\.linkFocusIndicator) private var focusIndicator
    @Environment(\.linkDisplay) private var display

    var body: some View {
        // Resolve the action and destination NOW, during render, and capture the
        // resolved values into the action closure. Reading `@Environment` inside
        // the closure — which fires later, on activation — would read it outside
        // a render pass, where it is invalid.
        let open = openURL
        let destination = self.destination
        // `.underline(_:)` cascades to every Text in the label subtree, so a
        // string title, a `Label`, or an SF-Symbol label all underline together.
        //
        // The accent arrives through the button's own text style rather than as
        // a `.foregroundStyle` on the label. Both put the same colour on screen,
        // but a colour written on the label wins over the one the style hands
        // down — and it is the STYLE that knows whether the pointer is over the
        // link. Routed this way, `.plain`'s hover lift applies to a link like
        // any other plain button, which is the whole affordance a link has.
        // The appearance breathes the words and reserves nothing, or falls back
        // to the plain button's bullet in two cells before them. Resolved here,
        // where the environment is readable, and carried into the style as a
        // value — a `ButtonStyle` is chosen at build time and cannot branch on
        // an environment it does not have.
        let gate = self.gate
        let showing = $showingDestination
        // Activation opens the URL **and** raises the destination popover, and
        // the second half is not a convenience: `open` runs the system opener
        // on the machine the app is running on, which over ssh is the server.
        // If it declines — or spawns nothing, which is the usual shape of that
        // failure — the popover is the only thing that tells the user where
        // the link went. It is raised whether or not `open` "worked" because
        // "did the browser open" is not a question this process can answer:
        // the child is not waited on, and on a headless box there is no child.
        // …and only in that mode is the link a control at all. With the URL on
        // the row, activating would open a destination the user can already
        // read and copy, on a machine that may not be theirs — so the two URL
        // modes draw the label as text: tinted, underlined, hyperlinked for a
        // host that honours OSC 8, and taking no focus and no click. A caller
        // who wants one of those adds it the way they would to any text —
        // `.focusable()`, `.onTapGesture`, `.onKeyEvent` — and the wrapper,
        // not the link, is what registers.
        let clipboard = self.clipboard
        guard display == .popover else {
            let text = resolvedLabel
                // Beneath the label's own colour, as the button style's tint
                // sits beneath it in the control form: a label that names
                // a colour keeps it either way.
                .foregroundStyle(.palette.accent)
                .modifier(
                    TerminalHyperlinkModifier(destination: destination, enabled: terminalHyperlinks))
            guard isEnabled else { return AnyView(text) }
            // The copies are offered here too, on a right-click: the URL is on
            // the row, but selecting it by hand is a drag, and Copy as Markdown
            // is not on the row at all. Show Link is not: the URL is shown.
            // The text takes no focus, so no keyboard opens this menu.
            return AnyView(
                ContextMenuModifier(
                    content: text,
                    menuItems: LinkContextMenu(
                        destination: destination, label: display == .urlOnly ? nil : labelText,
                        clipboard: clipboard, show: nil),
                    keyboardRoute: .contentStops))
        }
        let activation = self.activation
        // Activating opens or copies, as `.linkActivation(_:)` says, and
        // either way raises the popover, which shows what was copied.
        let activate = {
            guard gate.allows(nowNanos: MonotonicClock.nowNanoseconds) else { return }
            switch activation {
            case .open: open(destination)
            case .copy: _ = clipboard.write(destination.absoluteString, announcingSuccess: true)
            }
            showing.wrappedValue = true
        }
        let control = PopoverPresentationModifier(
            content: linkControl(activate: activate),
            isPresented: $showingDestination,
            // `verbatim`, because a URL is content and not a lookup key. A
            // right-click on it offers Copy Link, as on the link: the popover
            // holds no focus stop, so the link's own menu is the keyboard's
            // way to the same copy.
            popover: ContextMenuModifier(
                content: Text(verbatim: destination.absoluteString),
                menuItems: Button(localized: LocalizationKey.Menu.copyLink) { [clipboard] in
                    _ = clipboard.write(destination.absoluteString, announcingSuccess: true)
                },
                keyboardRoute: .contentStops),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom)
        // A disabled link offers nothing: it carries no destination for the
        // terminal either (`TerminalHyperlinkModifier`).
        guard isEnabled else { return AnyView(control) }
        // Its menu opens on the link's own focus stop, so Tab crosses a link
        // once, menu or not.
        return AnyView(
            ContextMenuModifier(
                content: control,
                // Show Link raises the popover and opens nothing: "Open" is
                // kept for opening the destination in the browser of the
                // machine the terminal is on, which nothing yet can.
                menuItems: LinkContextMenu(
                    destination: destination, label: labelText, clipboard: clipboard,
                    show: { showing.wrappedValue = true }),
                keyboardRoute: .contentStops))
    }

    /// The link as a control, which the destination's popover is anchored to.
    /// That popover is built here rather than through `View.popover`, which
    /// adapts to the size classes (`TUIPresentation`): the destination is a
    /// note beside the link at any size, not a presentation of its own.
    private func linkControl(activate: @escaping () -> Void) -> some View {
        Button(action: activate, label: { resolvedLabel })
        .buttonStyle(_LinkButtonStyle(indicator: focusIndicator))
        .buttonTextStyle { $0.foreground = .palette.accent }
        // Outermost, so the link covers everything the button style drew —
        // its hover prefix included. The control IS the link; a hyperlink over
        // only the letters would leave the cells beside them inert while
        // looking identical.
        .modifier(
            TerminalHyperlinkModifier(destination: destination, enabled: terminalHyperlinks))
        // The destination, where the user can read and copy it, is the
        // popover the caller anchors to this. Anchored to the link rather
        // than shown in the status bar: a URL is long, the status bar is a
        // row shared with every shortcut, and a destination that shoved
        // those aside — or was truncated to fit, which would make it
        // unusable — every time focus moved would be worse than not showing
        // it at all.
    }

    /// The link's visible text, which the display mode decides.
    ///
    /// `.popover` leaves the caller's label alone — the destination lives in
    /// the popover, and in the OSC 8 escape where the host honours one. The
    /// two URL modes rewrite it, and rewrite it with `Text(verbatim:)`: a URL
    /// is content, and a plain `Text(_:)` would treat it as a localization
    /// key.
    @ViewBuilder
    private var resolvedLabel: some View {
        switch display {
        case .urlOnly:
            Text(verbatim: destination.absoluteString).underline(underline)
        case .urlInParentheses:
            // `spacing: 0` and the space written into the second `Text`: an
            // HStack's spacing is layout, and this one is part of the sentence.
            HStack(spacing: 0) {
                label.underline(underline).modifier(RecordsLinkLabelText(record: labelText))
                Text(verbatim: " (\(destination.absoluteString))").underline(underline)
            }
        case .popover:
            label.underline(underline).modifier(RecordsLinkLabelText(record: labelText))
        }
    }
}

// MARK: - Environment without reflection

extension _Link: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _openURL.resolveEnvironment(environment)
        _clipboard.resolveEnvironment(environment)
        _isEnabled.resolveEnvironment(environment)
        _activation.resolveEnvironment(environment)
        _underline.resolveEnvironment(environment)
        _terminalHyperlinks.resolveEnvironment(environment)
        _focusIndicator.resolveEnvironment(environment)
        _display.resolveEnvironment(environment)
    }
}
