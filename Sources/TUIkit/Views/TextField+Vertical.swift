//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextField+Vertical.swift
//
//  A text field on the vertical axis: its text wraps over rows that grow as
//  it is typed, within the line limit, and then scroll to keep the caret in
//  view.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _TextFieldCore {
    /// The rows a vertical field occupies: as many as its text wraps into, held
    /// between the line limit's floor and cap, and within `available`.
    ///
    /// SwiftUI's vertical field does the same, measured on macOS 15.8: it grows
    /// a row at a time with no limit, stops at `lineLimit(2)`, keeps three rows
    /// under `lineLimit(3, reservesSpace: true)` and two under `2...4`, and a
    /// field on one line ignores the limit.
    static func verticalRowCount(textRows: Int, limit: LineLimit, available: Int) -> Int {
        var rows = textRows
        if let cap = limit.rowCount { rows = min(rows, cap) }
        if let floor = limit.reservedLines { rows = max(rows, floor) }
        return max(1, min(rows, max(1, available)))
    }

    /// Whether the field draws the combo box's `▾`: exactly when its suggestion
    /// menu is prepared — enabled, with a suggestion it can take — so the
    /// measure, which may not prepare it, narrows the text just as the render
    /// does.
    private func drawsDisclosure(isDisabled: Bool, context: RenderContext) -> Bool {
        !isDisabled && context.environment.textInputSuggestions.offersChoice
    }

    /// The characters a vertical field lays out: its text, or — while the text
    /// is empty — its prompt, which the field grows to fit as SwiftUI's does.
    private var verticalSource: (characters: [Character], isPrompt: Bool) {
        let string = text.wrappedValue
        guard string.isEmpty, prompt != nil else { return (Array(string), false) }
        return (Array(TextFieldContentRenderer.promptParagraphs(prompt)), true)
    }

    /// The layout of `source` in a field `contentWidth` cells wide inside its
    /// caps, less the `▾` when it draws one.
    private func verticalLayout(
        _ source: [Character], contentWidth: Int, hasDisclosure: Bool
    ) -> SoftWrapLayout {
        let textWidth = hasDisclosure ? max(minContentWidth, contentWidth - 2) : contentWidth
        return SoftWrapLayout(source, width: textWidth, cellWidth: TextFieldHandler.verticalCellWidth)
    }

    /// A vertical field's size: as wide as a field on one line, and as tall as
    /// ``verticalRowCount(textRows:limit:available:)`` says for its text
    /// wrapped where the render will wrap it.
    ///
    /// That is the proposed width, or with none the available width, as a
    /// ``Text`` measures — not the field's ideal width, which a parent asking
    /// with no proposal (a stack's render pass does) never draws it at: the
    /// field fills the width it is given, and its rows are that width's.
    func verticalSize(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let capWidth = FieldChrome.width(for: context.environment.textFieldStyle)
        let width = max(minContentWidth + capWidth, proposal.width ?? (defaultContentWidth + capWidth))
        let drawnWidth = proposal.width ?? context.availableWidth
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let layout = verticalLayout(
            verticalSource.characters, contentWidth: max(minContentWidth, drawnWidth - capWidth),
            hasDisclosure: drawsDisclosure(isDisabled: isDisabled, context: context))
        let height = Self.verticalRowCount(
            textRows: layout.rows.count, limit: context.environment.lineLimit,
            available: proposal.height ?? context.availableHeight)
        return ViewSize(width: width, height: height, isWidthFlexible: true, isHeightFlexible: false)
    }

    /// The first row to draw: the one shown last frame, moved just enough to
    /// show the caret's row. An unfocused field, and a placeholder, show their
    /// first rows.
    private static func firstRow(
        handler: TextFieldHandler, layout: SoftWrapLayout, rowCount: Int, follows: Bool
    ) -> Int {
        guard follows else { return 0 }
        let caretRow = layout.row(of: handler.cursorPosition, affinity: handler.selectionAffinity)
        var first = handler.scrollRow
        if caretRow < first {
            first = caretRow
        } else if caretRow >= first + rowCount {
            first = caretRow - rowCount + 1
        }
        return min(max(0, first), max(0, layout.rows.count - rowCount))
    }

    /// Draws a vertical field: a field line per row, each between the style's
    /// caps, the `▾` of a combo box on the first.
    func renderVertical(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette
        let chrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: false, on: context.environment.surfaceBackground)
        let contentWidth = max(minContentWidth, context.availableWidth - chrome.width)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "textfield", propertyIndex: StateIndex.focusID)
        let handler = resolveHandler(
            persistedFocusID: persistedFocusID, stateStorage: stateStorage,
            isDisabled: isDisabled, context: context)
        FocusRegistration.register(context: context, handler: handler, focusID: persistedFocusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        FocusRegistration.publishActivationLabel(submitVerb, context: context, isFocused: isFocused)

        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.isHovered),
            default: false)
        let suggestionMenu = TextFieldSuggestions.prepare(
            isDisabled: isDisabled, handler: handler, currentText: text.wrappedValue,
            isFocused: isFocused, context: context)

        let source = verticalSource
        let layout = verticalLayout(
            source.characters, contentWidth: contentWidth, hasDisclosure: suggestionMenu != nil)
        // The width Up and Down move by: the one drawn, never a measure's
        // probe, which would leave the keys between frames moving by rows at
        // a width nobody sees.
        if !context.isMeasuring { handler.wrapWidth = layout.width }
        let rowCount = Self.verticalRowCount(
            textRows: layout.rows.count, limit: context.environment.lineLimit,
            available: context.availableHeight)
        let firstRow = Self.firstRow(
            handler: handler, layout: layout, rowCount: rowCount, follows: isFocused && !source.isPrompt)
        // Scroll state is the render pass's to keep, never a measure's.
        if !context.isMeasuring { handler.scrollRow = firstRow }

        let cascaded = context.environment.styleCascade.resolve(for: [.all, .text, .control(.textField)])
        let renderer = TextFieldContentRenderer(
            prompt: prompt, isDisabled: isDisabled,
            displayCharacter: TextFieldHandler.verticalDisplayCharacter, surface: chrome.surface,
            contentForeground: cascaded.foreground,
            cursorSpeed: context.environment.indicatorAnimationSpeeds.speed(for: .textCursor),
            appearsActive: context.environment.appearsActive)
        let rows = renderer.buildRows(
            TextFieldContentRenderer.Rows(
                layout: layout, characters: source.characters, isPrompt: source.isPrompt,
                caret: handler.cursorPosition, selection: handler.selectionRange,
                affinity: handler.selectionAffinity, firstRow: firstRow, count: rowCount),
            isFocused: isFocused, palette: palette, cursorStyle: context.environment.textCursorStyle,
            cursorTimer: context.environment.cursorTimer, cursorTiming: context.environment.indicatorCycleTiming)

        var buffer = assembleVertical(
            rows, chrome: FieldChrome(
                style: context.environment.textFieldStyle, palette: palette,
                isHovered: !isDisabled && hoverBox.value, on: context.environment.surfaceBackground),
            suggestionsOpen: suggestionMenu?.isOpen, palette: palette, textWidth: layout.width,
            isMeasuring: context.isMeasuring)

        if !isDisabled {
            attachVerticalMouse(
                to: &buffer, context: context, handler: handler, persistedFocusID: persistedFocusID,
                hoverBox: hoverBox, drawn: (leading: chrome.leadingCells, firstRow: firstRow, rowCount: rowCount),
                disclosure: suggestionMenu == nil ? nil : (chrome.leadingCells + layout.width)..<buffer.width)
        }
        if let suggestionMenu, suggestionMenu.isOpen {
            TextFieldSuggestions.attach(menu: suggestionMenu, to: &buffer, handler: handler, context: context)
        }
        return buffer
    }

    /// The rows between their caps, with every row's caret run and claims moved
    /// to where the row landed. The `▾` goes on the first row, and the rows
    /// under it are padded with the field's surface.
    private func assembleVertical(
        _ rows: [TextFieldContentRenderer.FieldContent], chrome: FieldChrome, suggestionsOpen: Bool?,
        palette: any Palette, textWidth: Int, isMeasuring: Bool
    ) -> FrameBuffer {
        let contentStart = chrome.leadingCells
        let lineWidth = chrome.width + textWidth + (suggestionsOpen == nil ? 0 : 2)
        var lines: [String] = []
        var claims: [OpacityRegion] = []
        var carets: [AnimatedCellRun] = []
        for (index, row) in rows.enumerated() {
            var disclosure = ClaimingRow()
            if index == 0 {
                disclosure = Self.disclosureGlyph(isOpen: suggestionsOpen, palette: palette, surface: chrome.surface)
            } else if suggestionsOpen != nil {
                disclosure.append("  ", cells: 2, ink: nil, field: chrome.surface)
            }
            let line = chrome.open + row.line + disclosure.text + chrome.close
            lines.append(line)
            claims += row.claims.map { $0.shifted(byX: contentStart, y: index) }
            claims += chrome.claims(lineWidth: lineWidth).map { $0.shifted(byX: 0, y: index) }
            claims += disclosure.claims.map { $0.shifted(byX: contentStart + textWidth, y: index) }
            if let caret = row.caret { carets.append(caret.shifted(byX: contentStart, y: index)) }
        }
        var buffer = FrameBuffer(lines: lines)
        buffer.opacityRegions += claims
        // Never from a measure pass: a run outliving its cells repaints, on a
        // clock, over whatever took their place.
        if !isMeasuring { buffer.animatedCells += carets }
        return buffer
    }

    /// The field's pointer region: a press or a drag puts the caret at the row
    /// and column it landed on, through the rows this frame drew; a press on
    /// the first row's `▾` toggles the suggestions.
    ///
    /// - Parameter drawn: Where this frame drew the text: the cells before it,
    ///   and the window of rows it showed.
    private func attachVerticalMouse(
        to buffer: inout FrameBuffer, context: RenderContext, handler: TextFieldHandler,
        persistedFocusID: String, hoverBox: StateBox<Bool>,
        drawn: (leading: Int, firstRow: Int, rowCount: Int), disclosure: Range<Int>?
    ) {
        let (leading, firstRow, rowCount) = drawn
        TextFieldMouseHandler.register(
            buffer: &buffer, context: context, handler: handler, persistedFocusID: persistedFocusID,
            hoverBox: hoverBox,
            isDisclosure: { event in event.y == 0 && (disclosure?.contains(event.x) ?? false) },
            caretOffset: { event in
                // The live text, laid out as the field's keys lay it out: the
                // event may arrive frames after this render.
                guard let layout = handler.softWrapLayout() else { return handler.cursorPosition }
                let row = min(firstRow + max(0, min(event.y, rowCount - 1)), layout.rows.count - 1)
                let column = max(0, min(event.x - leading, layout.width - 1))
                return layout.offset(inRow: row, atColumn: column, affinity: handler.selectionAffinity)
            })
    }
}
