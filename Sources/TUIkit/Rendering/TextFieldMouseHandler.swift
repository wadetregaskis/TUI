//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldMouseHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Text Field Mouse Handler

/// Shared mouse wiring for the single-line text inputs (``TextField`` and
/// ``SecureField``).
///
/// Both fields render identically — a leading cap, the content, a trailing cap
/// — and share ``TextFieldHandler`` and ``TextFieldContentRenderer``, so they
/// share this too. A click:
/// - focuses the field,
/// - moves the caret to the clicked column (mapping the column back through
///   the field's horizontal scroll via
///   ``TextFieldHandler/characterIndex(forColumn:contentWidth:displayWidths:)``),
/// - and begins a selection anchored there; dragging extends it.
///
/// Shift-click extends the existing selection to the clicked column instead of
/// starting a new one. The hover state machine (``entered`` / ``exited``) rides
/// on the same region. Selection highlighting is handled by the content
/// renderer, which uses explicit palette colours — never a bare reverse-video
/// SGR.
@MainActor
enum TextFieldMouseHandler {
    /// Registers the field's mouse region on `buffer`. No-op while measuring or
    /// when no dispatcher is available; callers gate on `!isDisabled` first.
    ///
    /// - Parameters:
    ///   - buffer: The field's rendered buffer; a hit-test region is appended.
    ///   - context: The current render context.
    ///   - handler: The field's editing handler (caret + selection live here).
    ///   - persistedFocusID: The field's stable focus identifier.
    ///   - hoverBox: Persisted hover flag, toggled on `.entered` / `.exited`.
    ///   - contentWidth: The width of the content area between the caps.
    ///   - displayCharacter: The same character → display character mapping the
    ///     field's ``TextFieldContentRenderer`` uses; the click-to-caret math
    ///     needs the *display* cell widths (a `SecureField` bullet is one cell
    ///     however wide the hidden character is).
    ///   - leadingCapWidth: Cells occupied by the opening cap (the click column
    ///     is measured from the buffer's left edge, so this is subtracted to get
    ///     the content-relative column). Defaults to 1.
    ///   - disclosureRange: The buffer-x columns of the combo box's `▾`
    ///     disclosure, when the field has one. A click there toggles the
    ///     suggestions menu instead of positioning the caret.
    @MainActor
    static func register(
        buffer: inout FrameBuffer,
        context: RenderContext,
        handler: TextFieldHandler,
        persistedFocusID: String,
        hoverBox: StateBox<Bool>,
        contentWidth: Int,
        displayCharacter: @escaping (Character) -> Character,
        leadingCapWidth: Int = 1,
        disclosureRange: Range<Int>? = nil
    ) {
        // A buffer-local x → character index, discounting the leading cap. The
        // display widths come from the handler's LIVE text (the click may
        // arrive frames after this render).
        func index(at event: MouseEvent) -> Int {
            let widths = TextFieldContentRenderer.displayCellWidths(
                of: handler.text.wrappedValue, displayCharacter: displayCharacter)
            return handler.characterIndex(
                forColumn: event.x - leadingCapWidth, contentWidth: contentWidth,
                displayWidths: widths)
        }
        register(
            buffer: &buffer, context: context, handler: handler, persistedFocusID: persistedFocusID,
            hoverBox: hoverBox, isDisclosure: { event in disclosureRange?.contains(event.x) ?? false },
            caretOffset: index(at:))
    }

    /// Registers the field's mouse region on `buffer`, placing the caret where
    /// `caretOffset` says a press or a drag landed — the one step a vertical
    /// field's rows answer differently from a single line's.
    ///
    /// - Parameters:
    ///   - isDisclosure: Whether a press landed on the combo box's `▾`, which
    ///     toggles the suggestions menu instead of moving the caret.
    ///   - caretOffset: The character offset a press or drag at the event's
    ///     buffer-local cell puts the caret at.
    ///   - selectionEnd: The offset the event's cell is as a selection's
    ///     end — a drag's start and head, a Shift-click's end — and the row it
    ///     is on, where that differs from the caret's: a vertical field's
    ///     wrapped row's first character under `.upstream`, where no caret is
    ///     drawn, and which a head there is read on
    ///     (``TextFieldHandler/placeSelectionHead(at:onRow:)``). `nil` for a
    ///     field on one line, whose two are the same.
    @MainActor
    static func register(
        buffer: inout FrameBuffer,
        context: RenderContext,
        handler: TextFieldHandler,
        persistedFocusID: String,
        hoverBox: StateBox<Bool>,
        isDisclosure: @escaping (MouseEvent) -> Bool,
        caretOffset: @escaping (MouseEvent) -> Int,
        selectionEnd: ((MouseEvent) -> (offset: Int, row: Int))? = nil
    ) {
        guard !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }

        // Motion drives the hover machine (.entered / .exited); drag drives
        // click-and-drag selection.
        mouseDispatcher.requestFeature(.motion, in: context)
        mouseDispatcher.requestFeature(.drag, in: context)

        let focusManager = context.environment.focusManager
        let captureFocusID = persistedFocusID
        let captureHoverBox = hoverBox

        // A selection's head goes where the event's cell is as a selection's
        // end, read on the row it was found on; on one line, to the caret's.
        func placeHead(at event: MouseEvent) {
            guard let selectionEnd else {
                handler.cursorPosition = caretOffset(event)
                return
            }
            let end = selectionEnd(event)
            handler.placeSelectionHead(at: end.offset, onRow: end.row)
        }

        // Weak: the dispatcher holds this handler (see `Button`'s).
        let mouseHandlerID = mouseDispatcher.register(in: context, hoverBox: captureHoverBox) { [weak mouseDispatcher] event in
            defer { handler.publishSelection() }
            switch event.phase {
            case .pressed where event.button == .left:
                focusManager?.focus(id: captureFocusID)
                if isDisclosure(event) {
                    // The `▾` disclosure: toggle the suggestions menu; the
                    // caret stays where it was.
                    handler.toggleSuggestionsOpen()
                    if handler.suggestionsActive {
                        // Opened — so the drag and release that follow belong to
                        // the menu, not to the field. Click-and-hold, drag down
                        // the suggestions, release on one to choose it.
                        mouseDispatcher?.handOffGesture()
                        // Open as the menu draws, focus and all
                        // (`TextFieldSuggestions.prepare`): a field the press
                        // could not focus — out of the focus ring — draws no
                        // menu, and one taken for drawn had the rest of the
                        // gesture hit-tested live beneath it.
                        mouseDispatcher?.pressOpenedPopup(
                            MouseEventDispatcher.OpenedPopup(
                                isOpen: {
                                    handler.suggestionsActive
                                        && focusManager?.isFocused(id: captureFocusID) == true
                                },
                                close: { handler.suggestionsOpen = false }))
                    }
                    return true
                }
                if event.shift {
                    // Shift-click: keep the anchor, extend to the clicked column.
                    handler.pressAnchor = nil
                    handler.startOrExtendSelection()
                    placeHead(at: event)
                } else {
                    // Plain click: caret to the column and drop any selection.
                    // Don't anchor here — a drag anchors on its first .dragged
                    // event; anchoring on the press would leave a collapsed
                    // anchor that a later arrow key turns into a phantom
                    // selection. The drag anchors where the press landed as a
                    // selection's end, where that is not the caret's place.
                    handler.cursorPosition = caretOffset(event)
                    handler.rowStartHead = nil
                    handler.clearSelection()
                    handler.pressAnchor = selectionEnd?(event).offset
                }
                return true
            case .dragged:
                // The press was claimed, so this drag is bound to us: extend the
                // selection to the dragged column, anchored at the press.
                handler.startOrExtendSelection(from: handler.pressAnchor)
                placeHead(at: event)
                return true
            case .released where event.button == .left:
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: mouseHandlerID,
                focusID: persistedFocusID
            )
        )
    }
}
