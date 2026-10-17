//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditor.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - TextEditor

/// A control for editing multi-line text, mirroring SwiftUI's `TextEditor`.
///
/// It fills the space it is given and edits the bound string in place. When
/// focused it shows a block cursor. The key bindings follow the macOS text
/// system (Cocoa's `StandardKeyBinding.dict`), so the usual navigation,
/// Emacs-style control chords, and word-wise Option chords all apply:
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert at the cursor |
/// | Enter | Split the line (insert a newline) |
/// | Backspace / Delete | Delete before / at the cursor (join lines at edges) |
/// | Left / Right | Move by a character, wrapping across lines |
/// | Up / Down | Move by a row, keeping the column where possible; from the first row to the start, from the last to the end |
/// | Home / End | Start / end of the whole field (the document) |
/// | Page Up / Down | Move a screenful up / down |
/// | Ctrl-A / Ctrl-E | Start / end of the current line (the whole paragraph, however many rows it wraps over) |
/// | Option-Ctrl-A | Select the whole document |
/// | Ctrl-B / Ctrl-F | Back / forward one character |
/// | Ctrl-P / Ctrl-N | Previous / next row |
/// | Ctrl-D | Delete forward |
/// | Ctrl-K | Kill to end of line (yank with Ctrl-Y) |
/// | Ctrl-Y | Yank the last kill |
/// | Ctrl-T | Transpose the two characters around the cursor |
/// | Ctrl-O | Open a new line after the cursor |
/// | Ctrl-V | Paste |
/// | Ctrl-C / Ctrl-X | Copy / cut the selection (with nothing selected, the key passes on) |
/// | Ctrl-Z | Undo the last change |
/// | Ctrl-Shift-Z | Redo, where the terminal tells it from Ctrl-Z (the kitty keyboard protocol) |
/// | Option-← / → | Move by a word |
/// | Option-B / F | Move by a word (Emacs) |
/// | Option-Backspace / Delete | Delete the word before / after the cursor |
/// | Option-Tab | Insert a literal tab (plain Tab moves focus) |
///
/// ``TextField`` and ``SecureField`` read the Emacs chords from the same
/// table, and they differ where a field is one line with a keyboard selection.
/// There, Ctrl-U erases the field, and Ctrl-O, Ctrl-P and Ctrl-N do nothing. Ctrl-D
/// deletes a field's selection and Ctrl-Y replaces it, where the editor drops
/// its selection before any Emacs chord and acts at the cursor. A field
/// reads Option first, so Option-Ctrl-B and F move by a word in a field and by
/// a character here.
///
/// Ctrl-C, Ctrl-X, Ctrl-V and Ctrl-Z stand in for ⌘C, ⌘X, ⌘V and ⌘Z, which a
/// terminal app never receives, as they do in a field. Copy and cut act on the
/// selection; with nothing selected they pass the key on, so an app's ⌘C or ⌘X
/// fires, or `QuitShortcut.ctrlC` quits. Ctrl-V pastes the clipboard over the
/// selection, and the terminal's own paste arrives as well. Each change is registered with the app's
/// undo manager (``EnvironmentValues/undoManager``), so Ctrl-minus and the
/// status bar's "undo" take it back from anywhere, and Ctrl-Z is the app's
/// undo, as ⌘Z is a window's on macOS. Each event's changes are one step there;
/// outside a running app Ctrl-Z takes back one key's change at a time from the
/// editor's own history, from the last 50. It never brings back text the editor
/// did not produce: when the app replaces the bound text, loading another
/// document, the editor forgets its history.
///
/// An app's own keyboard shortcut beats most of the Emacs chords. Under the
/// default ``EnvironmentValues/commandKey`` a SwiftUI ⌘ shortcut arrives as a
/// Control chord, so `.keyboardShortcut("f")` (Find) is Ctrl-F, and the editor
/// gives the chord up: the shortcut fires and the editor does nothing. The same
/// goes for Option-B and Option-F, where ⌘B and ⌘F arrive under
/// `.commandKey(.option)`. Ctrl-A and Ctrl-E keep the key, because Home and End
/// go to the ends of the document here and leave them the only keys for the
/// ends of a line, and so does Option-Ctrl-A, the only way to select
/// everything, and so do copy, cut and undo. See <doc:KeyboardShortcuts>.
///
/// Literal tabs are laid out against tab *stops* — by default every 4 columns
/// (a tab advances to the next multiple of 4, so its visual width varies),
/// matching how the macOS text system, terminals and code editors treat tabs.
/// Configure the interval, or switch to a constant advance, for a subtree with
/// ``View/tabWidth(_:)``:
///
/// ```swift
/// TextEditor(text: $source)
///     .tabWidth(.periodic(8))   // classic terminal stops
/// // or .tabWidth(.fixed(2))    // every tab exactly two cells
/// ```
///
/// > Note: Option chords require the terminal to *send* Option as Meta
/// > (`ESC` + key). Terminal.app ships with **Use Option as Meta Key**
/// > disabled — enable it in Settings → Profiles → Keyboard (iTerm2: set the
/// > Option key to "Esc+"). Without it the terminal sends the plain key —
/// > Option-Tab arrives byte-identical to Tab, so focus moves; TUIkit never
/// > sees the modifier.
///
/// ```swift
/// @State private var notes = ""
/// TextEditor(text: $notes)
///     .frame(height: 6)
/// ```
///
/// It renders with a subtle field background by default so it reads as a text
/// field (like ``TextField``), not a box; add `.border()` for a boxed look. A
/// vertical scroll indicator appears in the trailing column when the text is
/// taller than the view, so it's clear there's content out of view.
///
/// Long lines **wrap** at the editor's width, as SwiftUI's do, by the macOS
/// text system's rules (measured on an `NSTextView`, macOS 15.8): a row breaks
/// after a run of spaces or a tab, which hangs at the end of the row it breaks,
/// or between the characters of a word too long for a row, and a tab's stop is
/// counted from the start of its row. The last cell of a row is kept for the
/// caret, so text wraps one cell short of the edge — a vertical ``TextField``
/// wraps the same way. Up and Down, Ctrl-P and Ctrl-N, and Page Up and Page
/// Down move by rows, keeping the caret's column through short ones; Up from
/// the first row goes to the start of the text and Down from the last to its
/// end, as an `NSTextView`'s do. The view scrolls vertically, by rows, to follow
/// the caret. Where a wrap would break up columns — code, a log, a table in
/// plain text — ``View/textEditorWrapsLines(_:)`` with `false` keeps each line
/// on one row and scrolls sideways to follow the caret instead, as many terminal
/// editors do; Up and Down then move by lines and stop at the first and last.
///
/// ## The selection and the caret where the terminal decides the colours
///
/// A selection is a tint of the palette's accent over the editor's well, and a
/// block caret is the caret's own colour with the character punched out of it.
/// Where the palette names colours the terminal decides — its own foreground or
/// background, or one of its sixteen slots — and the terminal has not said what
/// it paints for them, there is no tint between them to draw. Selected cells
/// then draw in **reverse video**, exchanging the cell's own ink and field, and
/// a block caret flips whatever the cell under it does: a plain cell is
/// reversed, a cell already reversed by the selection is drawn plain. A
/// blinking caret alternates the two; a pulsing one holds. A bar or underscore
/// caret is unaffected, as is a palette that states ordinary colours, on any
/// terminal. ``TextField`` draws the same way.
public struct TextEditor: View {
    let text: Binding<String>
    var focusID: String?
    var isDisabled: Bool

    /// The app's selection binding, as the editor reads and writes it, or
    /// `nil` for none.
    var selection: _TextSelectionChannel?

    /// Creates a text editor over a string binding.
    ///
    /// - Parameter text: The multi-line text to edit.
    public init(text: Binding<String>) {
        self.text = text
        self.focusID = nil
        self.isDisabled = false
    }

    /// Creates a plain text editor that captures the current selection —
    /// mirrors SwiftUI's `init(text:selection:)`.
    ///
    /// The editor writes its caret and selection to `selection` as they move,
    /// and a selection the app writes moves them. An editor selects one range,
    /// so a multiple selection selects its first.
    ///
    /// - Parameters:
    ///   - text: The multi-line text to edit.
    ///   - selection: The current selection.
    @available(macOS 15, *)
    public init(text: Binding<String>, selection: Binding<TextSelection?>) {
        self.init(text: text)
        self.selection = _TextSelectionChannel(selection, text: text)
    }

    @Environment(\.textEditorStyle) private var style
    @Environment(\.findNavigator) private var find

    /// Whether the find bar is up when no ``View/findNavigator(isPresented:)``
    /// says: the editor's own Ctrl-G presents it.
    @State private var isFindShownLocally = false
    @State private var findQuery = ""
    @State private var findReplacement = ""
    @State private var findMatch = 0
    /// The match the find bar last selected, as character offsets, for an
    /// editor with no selection binding of the app's to steer.
    @State private var findSelection: Range<Int>?
    /// Where the editor's context menu finds its handler — see ``TextField``.
    @State private var menuTarget = TextEditingMenuTarget()

    @ViewBuilder public var body: some View {
        // The two built-in styles are drawn by the core, which reads which one
        // is in force; a custom style draws its body in the editor's place.
        if style is AutomaticTextEditorStyle || style is PlainTextEditorStyle {
            let presented = isFindPresented
            VStack(alignment: .leading, spacing: 0) {
                if presented {
                    _FindBar(
                        text: text, query: $findQuery, replacement: $findReplacement, current: $findMatch,
                        supportsReplace: !find.isReplaceDisabled && !isDisabled,
                        select: { selectMatch($0) }, close: { setFindPresented(false) })
                }
                _TextEditorCore(
                    text: text, focusID: focusID, isDisabled: isDisabled,
                    selection: presented ? findChannel : selection, menuTarget: menuTarget
                ).textEditingMenu(menuTarget)
            }
            .onKeyPress(keys: ["g", "G"]) { press in
                // Ctrl-G presents the find bar: Ctrl-F is the editor's own
                // "forward a character", as on macOS.
                guard press.modifiers.contains(.control), !find.isFindDisabled else { return .ignored }
                setFindPresented(true)
                return .handled
            }
            .paintingScrollContentBackground()
        } else {
            style.makeAnyBody(configuration: TextEditorStyleConfiguration())
        }
    }
}

// MARK: - Find

extension TextEditor {
    /// Whether the find bar is up: as the app's binding says, or as Ctrl-G and
    /// Done left it.
    private var isFindPresented: Bool {
        guard !find.isFindDisabled else { return false }
        return find.isPresented?.wrappedValue ?? isFindShownLocally
    }

    private func setFindPresented(_ presented: Bool) {
        if let binding = find.isPresented {
            binding.wrappedValue = presented
        } else {
            isFindShownLocally = presented
        }
    }

    /// The selection the editor reads while the bar is up: the app's own,
    /// which the bar writes its matches into, or the bar's.
    private var findChannel: _TextSelectionChannel {
        if let selection { return selection }
        let box = $findSelection
        return _TextSelectionChannel(
            read: { box.wrappedValue },
            write: { offsets, _, _ in if box.wrappedValue != offsets { box.wrappedValue = offsets } })
    }

    private func selectMatch(_ offsets: Range<Int>) {
        findChannel.write(offsets, text.wrappedValue, .automatic)
    }
}

// MARK: - Modifiers

extension TextEditor {
    /// Disables editing. Disabled once, it stays disabled: as with
    /// `View.disabled(_:)`, a later `.disabled(false)` does not enable it again.
    public func disabled(_ disabled: Bool = true) -> TextEditor {
        var copy = self
        copy.isDisabled = isDisabled || disabled
        return copy
    }

    /// Sets a custom focus identifier.
    public func focusID(_ id: String) -> TextEditor {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core

private enum TextEditorStateIndex {
    static let handler = 0
    static let focusID = 1
}

/// Renders the editor: a windowed view of the text with a block cursor,
/// scrolling to follow the cursor. Greedy on both axes.
struct _TextEditorCore: View, Renderable, Layoutable {
    let text: Binding<String>
    let focusID: String?
    let isDisabled: Bool
    var selection: _TextSelectionChannel?
    /// Where the editor's context menu finds the handler.
    let menuTarget: TextEditingMenuTarget

    private typealias StateIndex = TextEditorStateIndex

    var body: Never {
        fatalError("_TextEditorCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let width = context.fillingWidth(proposal: proposal)
        // A wrapping editor is as tall as its rows at the width it is given.
        // Given no width — the ideal-width ask, whose answer is 0 as SwiftUI's
        // editor's is — it is as tall as its lines: wrapping at one cell would
        // lay out a row per character to answer a question about nothing.
        let layout = layout(context: context)
        let contentHeight = max(
            1,
            context.environment.textEditorWrapsLines && width > 0
                ? layout.wrapped(width: width, tabWidth: context.environment.tabWidth).rowCount
                : layout.lines.count)
        let height = proposal.height ?? min(contentHeight, max(1, context.availableHeight))
        return ViewSize(width: width, height: height, isWidthFlexible: true, isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.stateStorage!
        let width = max(1, context.availableWidth)
        let height = max(1, context.availableHeight)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "texteditor", propertyIndex: StateIndex.focusID)

        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<TextEditorHandler> = stateStorage.storage(
            for: handlerKey,
            default: TextEditorHandler(
                focusID: persistedFocusID, text: text, canBeFocused: !isDisabled,
                clipboard: context.environment.clipboardAccess))
        let handler = handlerBox.value
        handler.text = text
        handler.canBeFocused = !isDisabled
        menuTarget.handler = handler
        // The app's undo manager, which the editor's edits are registered with,
        // and where the editor leaves them when it goes away; and the steps of
        // text the app has replaced since, taken out of it.
        handler.undoManager = context.environment.undoManager
        handler.departedUndoSteps = context.environment.departedUndoSteps
        if !context.isMeasuring {
            handler.forgetHistoryIfReplaced()
            // The first render pass is when the editor appeared, where a flash
            // of its bar on appearing starts.
            if handler.indicatorFlash.appearedAtNanos == nil {
                handler.indicatorFlash.noteAppearance(atNanos: context.environment.frameNowNanos)
            }
        }
        // The height a page key steps by is the one drawn, never a measure's
        // probe (as the wrap width and the scroll are, in `window`): a
        // container that measures by rendering, after the editor's real
        // render, left Page Down stepping by the probe's rows.
        if !context.isMeasuring { handler.viewportHeight = height }
        // Synced each render so the handler's vertical motion preserves the
        // same *visual* column the renderer draws the caret at.
        let tabWidth = context.environment.tabWidth
        handler.tabWidth = tabWidth
        handler.clampCursor()
        handler.selectionChannel = selection
        handler.selectionAffinity = context.environment.textSelectionAffinity
        // The app's selection is taken by the render that draws it: a measure
        // moves no caret.
        if !context.isMeasuring { handler.adoptSelectionFromApp() }

        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let displayLines = handler.readLines()
        let window = window(
            handler, lines: displayLines, width: width, height: height, tabWidth: tabWidth,
            wraps: context.environment.textEditorWrapsLines, follows: !context.isMeasuring,
            barWidth: context.environment.scrollbarWidth)
        let contentWidth = window.contentWidth
        // The widths this frame asked for are the ones to keep (see
        // `EditorLayout.endFrame()`); a measure is not the end of a frame.
        // And where the caret is, for the run loop to park the terminal's cursor on.
        if !context.isMeasuring {
            handler.layout().endFrame()
            handler.insertionPoint = handler.drawnInsertionPoint(column: window.caretColumn, rows: window.rows, width: window.contentWidth, height: height)
        }

        // A subtle field background so the editor reads as a text field (like
        // TextField's chrome) rather than plain text — no full box. Opt into the
        // boxed look with `.border()`. The palette's field surface keeps it
        // readable on light and dark palettes alike (the old fixed accent-dim
        // tint multiplied toward black — dark grey behind black text on Basic).
        // `.textEditorStyle(.plain)` draws no surface: the text sits on whatever
        // is behind the editor, as a plain text field's does.
        let fieldBackground: Color? = isDisabled || context.environment.textEditorStyle is PlainTextEditorStyle
            ? nil
            : (context.environment.surfaceBackground.map { palette.fieldBackground(on: $0) }
                ?? palette.fieldBackground).resolve(with: palette)

        let styling = RowStyling(palette: palette, isDisabled: isDisabled, background: fieldBackground)

        // The caret honours `.textCursor(_:)` exactly like TextField: same
        // shape, same blink/pulse animation, same speed — one setting styles
        // every text input. And through the same `caretSetup`, so both carets
        // agree about what a faded palette's caret SPENDS: the editor built its
        // own colours and handed the translucent well and text to the emitter.
        //
        // The whole cycle, not this tick's frame. A caret that sampled the live
        // clock re-rendered the WHOLE screen 20 times a second to blink one
        // cell — 6.7% of a core on the Example's Text Input page against 0.2%
        // for the TextField two screens above it, which had already been
        // converted. Computed only while focused: even reading the cycle's
        // `step` is pointless work for an editor with no caret to draw.
        let cursorStyle = context.environment.textCursorStyle
        var caret: RowCaret?
        if isFocused {
            let setup = TextFieldContentRenderer.caretSetup(
                palette: palette, background: fieldBackground, textForeground: styling.text,
                selection: styling.selection, cursorStyle: cursorStyle,
                speed: context.environment.indicatorAnimationSpeeds.speed(for: .textCursor),
                cursorTimer: context.environment.cursorTimer,
                timing: context.environment.indicatorCycleTiming,
                appearsActive: context.environment.appearsActive)
            caret = RowCaret(
                column: window.caretColumn,
                cycle: .init(shape: cursorStyle.shape, cursor: setup.cycle, colors: setup.colors))
        }

        let rows =
            window.rows.map {
                renderWrappedRows(
                    $0, lines: displayLines, handler: handler, height: height, tabWidth: tabWidth,
                    caret: caret, styling: styling)
            }
            ?? renderRows(
                displayLines, handler: handler, width: contentWidth, height: height,
                tabWidth: tabWidth, caret: caret, styling: styling)
        // Under a bold legibility weight the text is a tier heavier, as a
        // field's is (`TextFieldContentRenderer.weighted(_:)`): the rows and
        // the caret's frames, before the bar, which is not text, joins them.
        let drawsBold = context.environment.legibilityWeight.drawsPlainBold
        var output = drawsBold ? rows.lines.map(ANSIRenderer.applyPersistentBold) : rows.lines
        let caretRun = drawsBold ? rows.caret?.drawnBold() : rows.caret

        var bar: (runs: [AnimatedCellRun], claims: [OpacityRegion]) = ([], [])
        if window.hasVerticalOverflow {
            // Drawing only — see `RenderContext.indicatesFocus(_:)`. The bar's
            // breath is a focus indication and goes with the effect; the caret
            // above is the insertion point and reads the raw `isFocused`.
            bar = appendScrollbar(
                to: &output, height: height, extent: window.extent,
                offset: window.offset, barColumn: contentWidth,
                isFocused: context.indicatesFocus(isFocused),
                flash: handler.indicatorFlash.strength(context: context), context: context)
        }

        var buffer = FrameBuffer(lines: output)
        // Disjoint by construction: every row stops at `contentWidth`, the bar's
        // column — so concatenated rather than merged.
        buffer.opacityRegions += rows.claims + bar.claims
        // Never from a measure pass: its buffer describes a size being tried
        // on, not cells on screen, and a run outliving its cells repaints — on
        // a clock — over whatever took their place.
        if !context.isMeasuring {
            buffer.animatedCells += bar.runs
            if let caretRun { buffer.animatedCells.append(caretRun) }
        }
        registerMouse(
            context: context, buffer: &buffer, handler: handler,
            contentWidth: contentWidth, height: height,
            focusID: persistedFocusID, isDisabled: isDisabled)
        return buffer
    }

    /// Appends a vertical scroll indicator — one column, or two for a
    /// double-width bar (`View.scrollbarWidth(_:)`) — to each row, and returns
    /// the animation runs its cells earn and the claims its colours owe.
    ///
    /// Converted WITH the caret rather than after it. The bar's pulse and the
    /// caret's blink shared one cause — a frame that read the live clock — so
    /// converting only the caret would have left the editor still re-rendering
    /// for the bar, and converting only the bar would have left the bar's runs
    /// replaying over a screen the caret was still repainting. Either half
    /// alone looks correct in a screenshot and is wrong over time.
    private func appendScrollbar(
        to output: inout [String], height: Int, extent: Int, offset: Int,
        barColumn: Int, isFocused: Bool, flash: Double?, context: RenderContext
    ) -> (runs: [AnimatedCellRun], claims: [OpacityRegion]) {
        // Pulses the accent while the editor is focused — the shared
        // focus-indicator convention (ScrollbarColors.focusIndicating). The
        // editor's bar is not a mouse target (it registers no region of its
        // own), so there is no hovered cell to answer.
        let colors = ScrollbarColors.focusIndicating(isFocused: isFocused, hoveredCell: nil, context: context)
        var bar = ScrollbarRenderer.verticalScrollbar(
            height: height, extent: extent, viewport: height, offset: offset,
            arrows: .none, proportional: true,
            colors: flash.map { colors.flashing($0, in: context.environment.palette) } ?? colors,
            width: context.environment.scrollbarWidth)
        // One cell per row the editor drew — an unpainted space past the bar's
        // end, as it always was — so no claim outlives the row it was for.
        let rows = min(height, output.count)
        bar.fit(toCount: rows, field: nil)
        for index in 0..<rows { output[index] += bar.lines[index] }
        let claims = bar.claims(atColumn: barColumn)
        // A flashing bar is still: the breath's runs would paint over the flash.
        guard flash == nil,
            let pulse = ScrollbarColors.focusPulse(
                isFocused: isFocused, hoveredCell: nil, context: context)
        else { return ([], claims) }
        return (
            ScrollbarRenderer.verticalScrollbarRuns(
                height: height, extent: extent, viewport: height, offset: offset,
                arrows: .none, proportional: true, pulse: pulse, width: context.environment.scrollbarWidth
            ).map { $0.shifted(byX: barColumn, y: 0) },
            claims)
    }

    /// What a frame draws its rows from: how wide they are, whether a scroll
    /// bar takes the last column, the bar's extent and offset (in lines, or in
    /// rows where the editor wraps), the caret's column in its line or row, and
    /// the rows themselves where it wraps.
    private struct Window {
        let contentWidth: Int
        let hasVerticalOverflow: Bool
        let extent: Int
        let offset: Int
        let caretColumn: Int
        let rows: WrappedRows?
    }

    /// The frame's window onto the document, its scroll moved to follow the
    /// caret — in lines and display columns where the editor scrolls sideways,
    /// in rows where it wraps. Moving the scroll is persistent state, so it is
    /// done only in a render pass (`follows`), never while measuring.
    ///
    /// When the text is taller than the view, the trailing column is reserved
    /// for a scroll indicator, so the user can see there is content out of
    /// view — the total width is unchanged, so measure == render still holds.
    /// A wrapping editor then lays its text out again a cell narrower, as a
    /// scroll view lays out its content once a bar arrives; both widths stay
    /// in the layout, so neither is laid out again the next frame.
    private func window(
        _ handler: TextEditorHandler, lines: [[Character]], width: Int, height: Int, tabWidth: TabWidth,
        wraps: Bool, follows: Bool, barWidth: Int
    ) -> Window {
        guard wraps else {
            if follows { handler.wrapWidth = nil }
            let overflows = lines.count > height
            let contentWidth = overflows ? max(1, width - barWidth) : width
            // In DISPLAY columns, the space the scroll window and the caret cell
            // live in (a tab makes the display column run ahead of the index).
            let caretColumn = TabLayout.displayColumn(
                ofCharIndex: handler.cursorColumn, in: lines[min(handler.cursorLine, lines.count - 1)],
                tabWidth: tabWidth)
            if follows {
                followCursor(
                    handler, cursorDisplayColumn: caretColumn, lineCount: lines.count, width: contentWidth,
                    height: height)
            }
            return Window(
                contentWidth: contentWidth, hasVerticalOverflow: overflows, extent: lines.count,
                offset: handler.scrollLine, caretColumn: caretColumn, rows: nil)
        }
        let layout = handler.layout()
        var rows = layout.wrapped(width: width, tabWidth: tabWidth)
        let overflows = rows.rowCount > height
        let contentWidth = overflows ? max(1, width - barWidth) : width
        if overflows { rows = layout.wrapped(width: contentWidth, tabWidth: tabWidth) }
        // The width the keys move by: the one drawn, never a measure's probe,
        // which would leave the keys between frames moving by rows at a width
        // nobody sees.
        if follows {
            handler.wrapWidth = contentWidth
            handler.followCaretRow(in: rows, height: height)
        }
        return Window(
            contentWidth: contentWidth, hasVerticalOverflow: overflows, extent: rows.rowCount,
            offset: handler.topRow(in: rows), caretColumn: handler.caretColumnInRow(in: rows), rows: rows)
    }

    /// The layout of the text THIS view's binding holds, kept by the editor's
    /// handler where it has one — a measure before the first render has not
    /// made it yet.
    ///
    /// Never the handler's own binding: that is the one the LAST render handed
    /// it (`handler.text = text`), and a measure runs before this frame's
    /// render. A binding that is not a live reference — `$notes[selected]`,
    /// whose index was captured when it was made, a `.constant`, a
    /// `Binding(get:)` over a loop's element — measured last frame's document:
    /// switching `selected` from a one-line note to a six-line one sized the
    /// editor one row and drew six lines into it.
    private func layout(context: RenderContext) -> EditorLayout {
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.handler)
        let box: StateBox<TextEditorHandler>? = context.stateStorage?.existingStorage(for: key)
        let current = text.wrappedValue
        return box?.value.layout(of: current) ?? EditorLayout(text: current)
    }

    /// Advances the handler's scroll offsets so the cursor stays visible.
    /// Horizontal scrolling is in display columns (`cursorDisplayColumn` —
    /// the caret's on-screen cell, which runs ahead of the character index
    /// on tab-bearing lines).
    private func followCursor(
        _ handler: TextEditorHandler, cursorDisplayColumn: Int,
        lineCount: Int, width: Int, height: Int
    ) {
        if handler.cursorLine < handler.scrollLine {
            handler.scrollLine = handler.cursorLine
        } else if handler.cursorLine >= handler.scrollLine + height {
            handler.scrollLine = handler.cursorLine - height + 1
        }
        handler.scrollLine = max(0, min(handler.scrollLine, max(0, lineCount - height)))

        if cursorDisplayColumn < handler.scrollColumn {
            handler.scrollColumn = cursorDisplayColumn
        } else if cursorDisplayColumn >= handler.scrollColumn + width {
            handler.scrollColumn = cursorDisplayColumn - width + 1
        }
        handler.scrollColumn = max(0, handler.scrollColumn)
    }

    /// A single wide region: a left-click focuses the editor and drops the
    /// caret at the clicked line/column (mapping the click through the current
    /// scroll offsets), and dragging extends a selection from the press point.
    /// Shift-click extends the existing selection instead of starting a new one.
    /// A double-click selects the word clicked and a triple-click the line,
    /// with its line break (``TextEditorHandler/range(of:around:)``), and a
    /// drag after either extends by words or lines.
    @MainActor
    private func registerMouse(
        context: RenderContext, buffer: inout FrameBuffer, handler: TextEditorHandler,
        contentWidth: Int, height: Int, focusID: String, isDisabled: Bool
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        // Drag reporting is needed for click-and-drag selection.
        mouseDispatcher.requestFeature(.drag, in: context)
        let focusManager = context.environment.focusManager

        // Map a buffer-local (x, y) to a text position through the scroll
        // offsets in effect for the displayed frame. The trailing scrollbar
        // column (when present) clamps into the last content column. The click
        // lands in DISPLAY space; the handler's cursor is a character index,
        // so translate through the clicked line's tab layout (a click anywhere
        // in a tab's span puts the caret on the tab).
        let tabWidth = context.environment.tabWidth
        //
        // `asSelectionEnd`: the event ends a selection — a drag's head, a
        // Shift-click — whose end may be a wrapped row's first character
        // under `.upstream`, where a caret cannot be.
        func placeCursor(at event: MouseEvent, asSelectionEnd: Bool = false) {
            let row = max(0, min(event.y, height - 1))
            handler.rowStartHead = nil
            // Wrapping, a click lands in a ROW: on the character whose cells
            // hold it, or past the row's text on its last caret position.
            if let rows = handler.wrappedRows() {
                let column = max(0, min(event.x, contentWidth - 1))
                if asSelectionEnd {
                    handler.placeSelectionHead(atScreenRow: row, column: column, in: rows)
                } else {
                    let position = handler.position(atScreenRow: row, column: column, in: rows)
                    handler.moveCursor(toLine: position.line, column: position.column)
                }
                return
            }
            // Valid content columns are 0..<contentWidth: clamping to
            // `contentWidth` put a scrollbar-column click one display column
            // PAST the window's right edge, so on a long line the caret
            // landed on the first off-screen character and followCursor
            // immediately scrolled the text one column right — a scrollbar
            // click that horizontally scrolled the editor.
            let displayColumn =
                handler.scrollColumn + max(0, min(event.x, contentWidth - 1))
            let line = handler.scrollLine + row
            let allLines = handler.readLines()
            let lineChars = allLines.indices.contains(line) ? allLines[line] : []
            let column = TabLayout.charIndex(
                forDisplayColumn: displayColumn, in: lineChars, tabWidth: tabWidth)
            handler.moveCursor(toLine: line, column: column)
        }

        let handlerID = mouseDispatcher.register(in: context) { event in
            defer { handler.publishSelection() }
            switch event.phase {
            // Ctrl-click is a secondary click, the editor's context menu's.
            case .pressed where event.button == .left && !event.ctrl:
                focusManager?.focus(id: focusID)
                handler.multiClickRun = nil
                if event.shift {
                    handler.pressAnchor = nil
                    handler.startOrExtendSelection()
                    placeCursor(at: event, asSelectionEnd: true)
                } else if let granularity = TextSelectionGranularity(clickCount: event.clickCount) {
                    // A double-click selects the word clicked, a triple-click
                    // the line; a drag after either extends by them.
                    placeCursor(at: event)
                    handler.selectRun(granularity, around: handler.cursor)
                } else {
                    // Plain click: place the caret and drop any selection. Do
                    // NOT anchor here — a collapsed anchor (anchor == cursor)
                    // shows no highlight but survives into a phantom one-char
                    // selection on the next arrow key. A drag anchors itself on
                    // its first .dragged event (startOrExtendSelection below),
                    // where the press landed as a selection's end: wrapping,
                    // that can be a row's first character the caret is not on.
                    placeCursor(at: event)
                    handler.clearSelection()
                    handler.pressAnchor = handler.wrappedRows().map { rows in
                        handler.selectionPosition(
                            atScreenRow: max(0, min(event.y, height - 1)),
                            column: max(0, min(event.x, contentWidth - 1)), in: rows)
                    }
                }
                return true
            case .dragged:
                if handler.multiClickRun != nil {
                    placeCursor(at: event)
                    _ = handler.extendRun(to: handler.cursor)
                    return true
                }
                handler.startOrExtendSelection(from: handler.pressAnchor)
                placeCursor(at: event, asSelectionEnd: true)
                return true
            case .released where event.button == .left:
                // A drag or a Shift-click that ends on its own anchor leaves no
                // selection, and its head is a caret. Where the head is a
                // wrapped row's first character (`rowStartHead`, drawn at that
                // row's first cell while it ended a selection), the caret goes
                // where a click there puts it, read by the editor's affinity
                // like every caret, rather than staying drawn where no caret
                // can be.
                if handler.selectionRange == nil, handler.rowStartHead == handler.cursor {
                    placeCursor(at: event)
                    handler.clearSelection()
                }
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID, focusID: focusID))
    }
}

// MARK: - Environment without reflection

extension TextEditor: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _style.resolveEnvironment(environment)
        _find.resolveEnvironment(environment)
    }
}

// MARK: - Inside a border

/// Its field reaches its edges, so `.border()` draws on them, with no blank
/// cell of page between.
extension TextEditor: PaintsToItsEdges {}
