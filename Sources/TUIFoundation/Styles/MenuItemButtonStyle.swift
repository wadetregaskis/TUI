//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuItemButtonStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Menu Item Style

/// Renders a `Button` as a **menu row** rather than as a button.
///
/// A `.contextMenu`'s items are `Button`s — that is SwiftUI's API and TUI
/// matches it — but they must not *look* like buttons: a pop-up menu's rows are
/// a plain label with a full-width highlight bar under the cursor, exactly like
/// the `Picker` drop-down's rows. (The drop-down itself can't be reused: it is a
/// procedural renderer over plain strings, not views, so nothing there takes a
/// `Button`.) This style is the view-composed counterpart, sharing the
/// drop-down's palette and pulse endpoints so the two menus read as one idiom.
///
/// Applied by `ContextMenuModifier` to the whole item stack, so every item
/// picks it up without the caller styling anything.
///
/// `Equatable` because it is injected into the environment around every menu
/// column, inline and pop-up alike: the render cache refuses to memoize
/// anything below a value it cannot compare, so while this style could not be
/// compared, no subtree inside a menu could be stored or served however
/// comparable everything else in force was. It holds nothing, so every instance
/// styles a row identically — see ``MenuStyle``.
struct _MenuItemButtonStyle: ButtonStyle, Equatable {
    func makeBody(configuration: Configuration) -> some View {
        _MenuItemRowBar(configuration: configuration)
    }
}

// MARK: - The breathing bar

/// Draws the focused row's highlight, and hands the run loop the whole breath
/// as finished lines rather than reading the clock (see ``AnimatedCellRun``).
///
/// This is where the row's *bar* lives, not in ``_MenuItemRow`` itself, for one
/// reason: painted here it is one persistent background over the finished line,
/// so the cycle is 16 recolourings of a line that was rendered once. Painted
/// inside the row it would be part of the row's own styling, and every step
/// would mean rendering the row again.
///
/// Why it matters: 32 rows resolving the live emphasis held the Example's main
/// menu at **35.5% of a core while idle** at 604 bytes/s — the fewest bytes and
/// the most CPU of any screen, i.e. an entire view walk ~30×/s to recolour one
/// row.
private struct _MenuItemRowBar: View, Renderable, Layoutable {
    let configuration: ButtonStyleConfiguration

    var body: Never {
        fatalError("_MenuItemRowBar renders via Renderable")
    }

    /// The row without the bar — what is measured, and what each step of the
    /// cycle is painted over.
    ///
    /// The environment values the row draws itself from are read HERE and
    /// handed over as stored properties, rather than declared as `@Environment`
    /// on the row. This view is `Renderable`, so it has the render context that
    /// a `ButtonStyle`'s body does not — and the row sits directly inside it
    /// with no modifier between, so the values are the same ones it would have
    /// resolved for itself. What it saves is the resolution, per row, on every
    /// measure and every render: a copy of the row and three `@Environment`s
    /// resolved into it (the walk is planned per type, `PropertyPlans`); its
    /// `palette` field is read where it lies instead, and the row is not
    /// copied while that holds no property. When the walk still reflected —
    /// three `EnvironmentBox` allocations, a walk over the row's fields
    /// handing each back as `Any`, three existential casts — the `menus`
    /// stress scenario measured its inner loop (`resolveEnvironmentProperties`,
    /// since replaced) at **5.9% of the frame** and `Environment.wrappedValue`
    /// at another **5.0%**, and every reflecting view on that path was this row.
    private func row(in context: RenderContext) -> _MenuItemRow {
        _MenuItemRow(
            configuration: configuration,
            palette: context.environment.palette,
            menuRowWidth: context.environment.menuRowWidth,
            menuRowInset: context.environment.menuRowInset,
            hint: hint(in: context))
    }

    /// The button's key equivalent, as the row prints it: its symbols, or
    /// their names where ``EnvironmentValues/keyNotation`` asks for those, a
    /// letter pressed alone in the ``EnvironmentValues/keyLetterCase`` in
    /// force.
    /// Formatted once here rather than on each of the row's three reads of it,
    /// and asked of the environment only by a row that has a shortcut.
    ///
    /// A row that opens a submenu prints the submenu caret there instead
    /// (``DropdownMenu/submenuCaret``), as a desktop menu draws its chevron.
    private func hint(in context: RenderContext) -> String {
        // Spelled as the `Text` that draws it will spell it, so the column the
        // row reserves for it is the width it is drawn at.
        if context.environment.menuRowOpensSubmenu { return context.spelled(DropdownMenu.submenuCaret) }
        guard let symbols = configuration.keyboardShortcut?.displayString else { return "" }
        let environment = context.environment
        return context.spelled(environment.keyNotation.spelling(environment.keyLetterCase.spelling(symbols)))
    }

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(row(in: context), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let row = row(in: context)
        let buffer = TUIView.renderToBuffer(row, context: context)
        guard configuration.isFocused else { return buffer }

        let palette = context.environment.palette
        // `emphasisFill()`, not a hand-rolled pair: this bar is a FILL that a
        // label is drawn on, and that is exactly the distinction the two pulse
        // functions carry (`accentPulse` reaches the accent, a fill's bright end
        // stops at `focusPulseMax` so the content stays readable). Spelled out here,
        // the two ends also disagreed about a translucent accent — the dim end spent
        // its alpha and the bright end was written from `palette.accent` again. See
        // `Documentation/Colour and styling/Opacity as composition.md` §21. And where the accent or the
        // page has no RGB there is nothing between them to breathe (§75), so the bar
        // reverses the palette's own pair rather than hold a colour nobody can check
        // the label against (§88) — the same answer `RowBackground` gives a cursor row.
        // And where the window has lost the terminal's focus, the bar stays, still,
        // in the tint a `List` gives a selection it does not hold the keys for: the
        // row is still the one the keys will reach when it comes back, and hiding it
        // read as the focus having been lost. That rule is the palette's, asked by
        // every highlighted row, so a menu's row and a list's cursor row agree.
        // A breath with reverse video in it (16 colours, where the palette's picks run
        // out; without colour, by weight) is drawn as a list's cursor row draws it.
        let emphasis = palette.highlightedRowFill(appearsActive: context.environment.appearsActive, reversing: true)
        // Drawn by the one painter of a highlight behind a finished label, which a
        // focused `.focusable()` view's tint shares (`FrameBuffer.onHighlight`).
        return buffer.onHighlight(
            emphasis, wakeToken: "menu-row-dropped-run-\(context.identity.path)", context: context)
    }
}

// MARK: - Row

/// One menu row. A separate view because `ButtonStyle.makeBody` composes views
/// and has no render context — but ``_MenuItemRowBar``, which builds this, is
/// `Renderable` and does, so the values arrive as stored properties instead of
/// being resolved here. (The gradient editor's `_StopChipStyle` is the same
/// shape and still reads the environment, because nothing between it and the
/// style has a context.)
private struct _MenuItemRow: View {
    let configuration: ButtonStyleConfiguration

    /// The palette in force where the row sits.
    ///
    /// Passed in by ``_MenuItemRowBar`` rather than declared `@Environment`
    /// here — see the note on its `row(in:)`. The doc comment above still holds
    /// for a style's *body*: this row is one level below that, inside a
    /// `Renderable` that has the context.
    let palette: any Palette

    /// The width the highlight bar should span, injected by the menu once it
    /// knows it. See ``EnvironmentValues/menuRowWidth``.
    let menuRowWidth: Int?
    let menuRowInset: Int

    /// The button's key equivalent, printed at the trailing edge the way a
    /// menu item's key equivalent is on every desktop platform; empty for a
    /// button without one. Formatted by ``_MenuItemRowBar``, which has the
    /// key notation in its context.
    let hint: String

    @ViewBuilder
    var body: some View {
        // Inside the background, so the highlight covers the breathing room
        // rather than leaving gutters the eye reads as part of the bar and the
        // pointer cannot hit. An INLINE menu leaves this 0 and takes its
        // margin from the column's own padding, which is outside the row.
        let content = columns.padding(.horizontal, menuRowInset)
        // The focused row draws no background of its own: ``_MenuItemRowBar``
        // paints its bar over the finished line, and a background here would
        // sit *inside* that paint — the inner code wins for the cells it
        // covers — leaving the bar showing only in the gaps.
        if let background {
            content.background(background)
        } else {
            content
        }
    }

    private var columns: some View {
        // The bar spans the menu's interior — but ONLY once the menu has
        // measured itself. Filling with `.frame(maxWidth: .infinity)` instead
        // would make every row measure as flexible, the stack would measure at
        // whatever it was offered, and the menu would go back to spanning the
        // screen (the same trap `Divider` sprang). A fixed width measures as
        // itself, and it is absent during the sizing pass, so the rows hug
        // while the menu is being measured and fill once it is being drawn.
        HStack(spacing: 0) {
            row.frame(width: labelWidth, alignment: .leading)
            if !hint.isEmpty {
                // The gap before the hint is the frame's, not a leading space
                // in the string: the frame is what right-aligns the hint into
                // a column of its own, and it keeps the gap out of the string
                // the row would otherwise have to measure and draw identically.
                Text(hint)
                    .foregroundStyle(hintForeground)
                    .frame(width: hintWidth, alignment: .trailing)
            }
        }
    }

    private var row: some View {
        label.foregroundStyle(foreground)
    }

    /// The label's share of the row: everything the hint doesn't take. The
    /// hints line up in a column because every row is the same total width and
    /// each pads its own label to leave room for its own hint. `nil` while the
    /// menu is still measuring, so the label hugs and the natural width comes
    /// out as label + gap + hint.
    private var labelWidth: Int? {
        guard let menuRowWidth else { return nil }
        return max(1, menuRowWidth - hintWidth - 2 * menuRowInset)
    }

    /// The hint's column, gap included. Known without ``menuRowWidth``, so the
    /// measuring pass reserves exactly what the render draws.
    private var hintWidth: Int {
        hint.isEmpty ? 0 : hint.strippedLength + 1
    }

    /// The hint is secondary information — dimmed, except on the highlight bar
    /// where it comes up to full strength alongside the label.
    private var hintForeground: Color {
        guard configuration.isEnabled, !configuration.isFocused else { return foreground }
        return palette.foregroundSecondary
    }

    /// The row's label — the string one, or the caller's `@ViewBuilder` one.
    ///
    /// No leading space of its own: the menu's border and its one cell of
    /// padding already inset every row, and a `@ViewBuilder` label would not
    /// get the extra space anyway, so adding it here would only make the two
    /// kinds of row disagree. (It used to be written `Text(" \(label)")`, which
    /// drew nothing at all until `Text` stopped swallowing leading spaces.)
    private var label: some View {
        configuration.label
    }

    /// The row's text colour. A destructive role keeps its error tint whatever
    /// the row's state — matching SwiftUI, where the role overrides the style.
    ///
    /// The focused row keeps the ordinary foreground rather than picking a
    /// colour against the bar. Two reasons, and the first is the real one: the
    /// bar MOVES, so a colour chosen against it moves too, and text that
    /// changes colour mid-breath reads as a glitch. (It could also flip from
    /// the light end of the palette to the dark one partway through a cycle.)
    /// And the pair is already measured — `PaletteContrastAuditTests` holds
    /// `foreground` over both pulse endpoints, for every shipped palette,
    /// which is exactly what bounds ``ViewConstants/focusPulseMax``. It is
    /// what the `Picker` drop-down and `List`'s focused row do as well.
    private var foreground: Color {
        if !configuration.isEnabled {
            return palette.foreground.opacity(ViewConstants.disabledForeground, over: palette.background)
        }
        let ink = configuration.role == .destructive ? palette.error : palette.foreground
        // Under the pointer the row's wash is an accent tint, which is the page where it
        // cannot be measured, so the label lifts instead (Opacity as composition §82).
        // Not on the keyboard cursor's row, whose bar is drawn over it.
        guard configuration.isHovered, !configuration.isFocused else { return ink }
        return palette.hoveredLabel(ink)
    }

    /// The row's own background: a quiet tint under the pointer, the page
    /// colour otherwise — and *nothing* under the keyboard cursor, whose
    /// breathing bar ``_MenuItemRowBar`` paints over the finished line.
    private var background: Color? {
        if configuration.isFocused { return nil }
        guard configuration.isHovered else { return palette.background }
        // A tint of the accent over the page — and where either has no RGB there is
        // nothing between them, so every share of the blend is one end or the other
        // (Opacity as composition §75). Below half that end is the page, which says
        // nothing at all; the label's ink lifts instead (§82, `hoveredLabel` above).
        // Asked of the colours rather than left to `hoverBackground` happening to sit
        // below half: raised above it, the same blend would be a solid accent under a
        // label nobody can check for contrast.
        let wash = palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
        guard case .fill(let tint) = palette.highlightFill(wash, tint: palette.accent) else {
            return palette.background
        }
        return tint
    }
}

// MARK: - Environment

private struct MenuRowInsetKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct MenuRowWidthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The width a menu row's highlight bar should span, or `nil` while the menu
    /// is still measuring itself (rows hug then, so the measure yields the
    /// menu's natural width rather than whatever it was offered).
    ///
    /// Set by `ContextMenuModifier` between its measure and its render.
    /// How many cells of breathing room a menu row keeps INSIDE its highlight.
    ///
    /// A pop-up sets 1: its rows are placed straight into the drop-down's
    /// interior, so the margin has to be part of the row or the highlight bar
    /// runs edge to edge. An inline menu leaves it 0 — its column is padded as
    /// a whole, outside the rows.
    var menuRowInset: Int {
        get { self[MenuRowInsetKey.self] }
        set { self[MenuRowInsetKey.self] = newValue }
    }

    var menuRowWidth: Int? {
        get { self[MenuRowWidthKey.self] }
        set { self[MenuRowWidthKey.self] = newValue }
    }
}
