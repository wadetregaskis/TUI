//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelection.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Screen selection

/// TUIkit's own selection of what is drawn on the screen — the selection a
/// terminal would make, if the app were not reporting the mouse.
///
/// A TUIkit app reports the mouse, so the terminal's own selection needs a
/// modifier held (or none works at all: Apple Terminal has no bypass). So
/// TUIkit selects by itself. A drag that no control uses — over the page's
/// background, over plain text, over a scroll view's content — selects the
/// cells it crosses, in reading order as a terminal does, clipped to the pane
/// it started in (a scroll view, a split view's column, else the content
/// area). A double-click selects a word, a triple-click the row. A drag with
/// Option (or ⌘ in iTerm2, which reports it the same way) selects a
/// rectangle, as both terminals' own block selection does. The status bar and
/// the app header are never selected.
///
/// What is selected is CHARACTERS, read from the page as drawn, not views:
/// wide characters once, trailing blanks dropped, rows joined with line
/// breaks. The text is fixed when the drag ends; the highlight goes as soon as
/// the cells under it no longer read that text, and with it the selection's
/// keys — for good, unless the page itself moved, when both come back with it.
///
/// **Copying** is Ctrl-C — the app's ⌘C, resolved through `commandKey` — while
/// a selection is drawn, through the app's ``ClipboardWriter``, whose status-bar
/// line says what became of it. ⌘C itself never reaches an app: the terminal
/// takes it for its own (here empty) selection. A scene can opt into copying
/// on release (``Scene/textSelectionCopiesOnRelease(_:)``). Escape, any click
/// and a resize clear the selection.
///
/// Costs nothing per frame while nothing is selected but keeping a reference
/// to the frame's lines (the array is shared, not copied).
final class ScreenSelection: @unchecked Sendable {
    // Touched from the main actor only: the dispatcher's events, the input
    // chain's keys and the run loop's frame all run there.

    /// A cell. The pointer's and the hit regions' are the screen's; a
    /// selection keeps its own in the content area's, the page's, so it stays
    /// on the text it selected when the bar above the page changes height.
    struct Point: Equatable {
        var x: Int
        var y: Int
    }

    /// A rectangle of cells, in the coordinates its ``Point``s are in.
    struct Rect: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int

        func clamping(_ point: Point) -> Point {
            Point(
                x: min(max(point.x, x), x + max(0, width - 1)),
                y: min(max(point.y, y), y + max(0, height - 1)))
        }

        func contains(_ point: Point) -> Bool {
            point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
        }

        func intersection(_ other: Self) -> Self? {
            let left = max(x, other.x)
            let top = max(y, other.y)
            let right = min(x + width, other.x + other.width)
            let bottom = min(y + height, other.y + other.height)
            guard right > left, bottom > top else { return nil }
            return Self(x: left, y: top, width: right - left, height: bottom - top)
        }
    }

    /// How the selection grows from its anchor.
    enum Shape: Equatable {
        /// From the anchor to the head in reading order, whole rows between —
        /// a terminal's ordinary selection.
        case stream
        /// The rectangle with the anchor and the head at opposite corners —
        /// a terminal's block selection.
        case rectangle
    }

    /// What the ends snap to: a drag's cells, a double-click's words, a
    /// triple-click's rows.
    enum Unit: Equatable {
        case character
        case word
        case row
    }

    /// One selection.
    struct Selection: Equatable {
        var anchor: Point
        var head: Point
        var clip: Rect
        var shape: Shape
        var unit: Unit
        /// The text selected, as last read.
        var text: String
        /// Whether the highlight is drawn: while the cells under it read
        /// ``text``.
        var isHighlighted = true
        /// The content area the highlight was last drawn in, the screen's —
        /// what a highlight that went may come back in; `nil` once it is gone
        /// for good (``ScreenSelection/takeFrame(_:width:palette:top:underPresentation:)``).
        var shownIn: Rect?
        /// Whether a drag is still making it.
        var isMaking = true
    }

    /// The selection, if there is one.
    private(set) var current: Selection?

    /// The last frame's composited content, each line as written: what a
    /// selection reads. A reference to the frame's own array, kept every frame.
    private(set) var frameLines: [String] = []

    /// The last frame's content width.
    private(set) var frameWidth = 0

    /// The screen row the last frame's content area starts at: the rows the
    /// window's top bar takes above it. What turns the screen's coordinates,
    /// which the pointer reports, into the page's.
    private(set) var frameTop = 0

    /// Whether a drag's release copies the selection — the scene's
    /// ``Scene/textSelectionCopiesOnRelease(_:)``.
    var copiesOnRelease = false

    /// The key that copies: the app's ⌘C, resolved through the scene's
    /// `commandKey` (``adopt(commandKey:copiesOnRelease:)``). `nil` where the
    /// scene's ⌘ stand-in is `.unavailable`.
    var copyTrigger: KeyboardShortcut.Trigger? = KeyboardShortcut("c", modifiers: .control).trigger

    /// The binding ``copyTrigger`` was resolved through.
    var adoptedCommandKey: CommandKeyBinding?

    /// The open menu's highlight, kept across its frames; made when it first
    /// opens (``presentMenu(over:context:)``).
    var menuController: MenuPopupController?

    /// Whether the menu presented since its section was last taken down.
    var menuNeedsTeardown = false

    /// The menu, as the press that opens it hands it to the dispatcher for the
    /// rest of its gesture (``MouseEventDispatcher/pressOpenedPopup(_:)``):
    /// open while it is anchored, which is while the window draws it, and
    /// closed as Escape and its backdrop close it. Built once, weakly, as
    /// ``MenuPopupState/openedPopup`` is.
    private(set) lazy var openedPopup = MouseEventDispatcher.OpenedPopup(
        isOpen: { [weak self] in self?.menuAnchor != nil },
        close: { [weak self] in self?.closeMenu() })

    /// Copies text: the app's ``ClipboardWriter``, announcing the result.
    var copy: (String) -> Void = { _ in }

    /// Where the selection's context menu was opened — the cell right-clicked
    /// inside the selection — while it is open; `nil` when it is not.
    private(set) var menuAnchor: Point?

    /// Whether anything is selected.
    var hasSelection: Bool { current != nil }

    /// The content area of the last frame, in the screen's coordinates.
    var contentArea: Rect { Rect(x: 0, y: frameTop, width: frameWidth, height: frameLines.count) }

    /// `point`, a cell of the screen, as a cell of the page.
    private func onPage(_ point: Point) -> Point { Point(x: point.x, y: point.y - frameTop) }
}

// MARK: - Making a selection

extension ScreenSelection {
    /// Starts a selection at `point`, clipped to `clip` — both the screen's.
    func begin(at point: Point, clip: Rect, shape: Shape, unit: Unit) {
        guard var clip = clip.intersection(contentArea), clip.contains(point) else { return }
        let point = onPage(point)
        clip.y -= frameTop
        current = Selection(
            anchor: point, head: point, clip: clip, shape: shape, unit: unit, text: "",
            shownIn: contentArea)
        refreshText()
    }

    /// Moves the head of the selection being made to `point`, a cell of the
    /// screen, clamped to its clip.
    ///
    /// A stream dragged past the clip's bottom runs to the end of its last row,
    /// and past its top to the start of its first, as a terminal's selection
    /// does at the edge of the screen and a Mac's does past the end of a text.
    func extend(to point: Point) {
        guard var selection = current, selection.isMaking else { return }
        let point = onPage(point)
        let clip = selection.clip
        if selection.shape == .stream, point.y >= clip.y + clip.height {
            selection.head = Point(x: clip.x + clip.width - 1, y: clip.y + clip.height - 1)
        } else if selection.shape == .stream, point.y < clip.y {
            selection.head = Point(x: clip.x, y: clip.y)
        } else {
            selection.head = clip.clamping(point)
        }
        current = selection
        refreshText()
    }

    /// Ends the drag making the selection, and copies it if the scene asks.
    func finish() {
        guard var selection = current, selection.isMaking else { return }
        selection.isMaking = false
        current = selection
        refreshText()
        if copiesOnRelease, let text = current?.text, !text.isEmpty { copy(text) }
    }

    /// Drops the selection, and its menu with it.
    func clear() {
        current = nil
        menuAnchor = nil
    }

    /// Whether `point`, a cell of the screen, is one of the cells the highlight
    /// is drawn on.
    func highlights(_ point: Point) -> Bool {
        let point = onPage(point)
        guard let selection = current, selection.isHighlighted, !selection.isMaking,
            point.y >= 0, point.y < frameLines.count
        else { return false }
        let cells = Self.cells(of: frameLines[point.y])
        var resolved = selection
        (resolved.anchor, resolved.head) = Self.ends(of: selection) { row in
            row >= 0 && row < frameLines.count ? Self.cells(of: frameLines[row]) : []
        }
        resolved.unit = .character
        return Self.columns(of: resolved, onRow: point.y, cells: cells)?.contains(point.x) ?? false
    }

    /// Opens the selection's context menu at `point`, if `point` is on the
    /// highlight: a right-click there offers Copy, as a Mac's text does.
    /// Elsewhere the press is someone else's — an app's own `.contextMenu`.
    func openMenu(at point: Point) -> Bool {
        guard highlights(point) else { return false }
        menuAnchor = onPage(point)
        return true
    }

    /// What a left press does to the selection: ends it, as a click does on
    /// a Mac — unless its menu is open, whose rows and dismiss backdrop take
    /// the press, and which keeps the selection it is about.
    func notePress() {
        if menuAnchor == nil { clear() }
    }

    /// Closes the selection's context menu, keeping the selection.
    func closeMenu() {
        menuAnchor = nil
    }

    /// Copies the selection's text, as Ctrl-C does. `false` with nothing
    /// selected, so the key goes on.
    func copySelection() -> Bool {
        guard let text = current?.text else { return false }
        copy(text)
        return true
    }

    /// Re-reads the selection's text from the last frame.
    private func refreshText() {
        guard var selection = current else { return }
        selection.text = Self.text(of: selection, in: frameLines)
        current = selection
    }
}

// MARK: - The frame

extension ScreenSelection {
    /// Takes in the frame's page, before the layers over it are composited:
    /// keeps its lines for the next selection, and, while there is one,
    /// follows it and draws its highlight.
    ///
    /// - A resize clears the selection: the cells it named are gone. Only the
    ///   width says so; the content area's height also moves with the status
    ///   bar's rows, which is no reason to lose a selection.
    /// - A selection being made follows the screen, as a terminal's does.
    /// - A finished one keeps its text, and its highlight goes when the cells
    ///   under it no longer read that text. Where the content area is where
    ///   the highlight was last drawn, the cells themselves changed — a log
    ///   scrolled on, a spinner turned — and it is gone for good: a highlight
    ///   that came back whenever they read the text again blinked over a
    ///   cycling line, its keys with it, and an equal line scrolling into
    ///   place revived a selection long gone. Where the content area moved —
    ///   a status-bar tooltip's row, a copy's line, taking a row from a
    ///   centred page — the page moved under it, and it comes back, keys and
    ///   all, when the area is back and the cells read the text again.
    /// - A presentation over the page — a sheet, an alert, an open menu —
    ///   clears it too: what is under a modal's backdrop is not the user's to
    ///   copy, and its keys are the presentation's. The selection's own menu
    ///   is the exception.
    ///
    /// `top` is the screen row the page is drawn from, below the window's top
    /// bar.
    @MainActor
    func takeFrame(
        _ buffer: FrameBuffer, width: Int, palette: any Palette, top: Int = 0,
        underPresentation: Bool = false
    ) -> FrameBuffer {
        let resized = width != frameWidth
        frameLines = buffer.lines
        frameWidth = width
        frameTop = top
        guard var selection = current else { return buffer }
        if resized || (underPresentation && menuAnchor == nil) {
            clear()
            return buffer
        }
        let drawn = Self.text(of: selection, in: frameLines)
        let area = contentArea
        if selection.isMaking {
            selection.text = drawn
            selection.shownIn = area
        } else if let shownIn = selection.shownIn {
            if drawn == selection.text, selection.isHighlighted || area == shownIn {
                selection.isHighlighted = true
                selection.shownIn = area
            } else {
                selection.isHighlighted = false
                // The page did not move: the cells changed under it.
                if area == shownIn { selection.shownIn = nil }
            }
        }
        current = selection
        guard selection.isHighlighted else { return buffer }
        return Self.highlighting(selection, in: buffer, palette: palette)
    }
}

// MARK: - Reading cells

extension ScreenSelection {
    /// A line taken apart into cells: each cell's character, `nil` for the
    /// second cell of a wide one. A picture's placeholder cells read as blanks.
    static func cells(of line: String) -> [Character?] {
        var cells: [Character?] = []
        line.forEachANSISegment { segment in
            guard case .visible(let character) = segment else { return true }
            let width = character.terminalWidth
            guard width > 0 else { return true }
            let isPicture =
                character.unicodeScalars.first == Unicode.Scalar.terminalImagePlaceholder
            cells.append(isPicture ? " " : character)
            for _ in 1..<width { cells.append(nil) }
            return true
        }
        return cells
    }

    /// Whether the cell at `point`, a cell of the screen, of the last frame
    /// shows text: a character that is not a blank, and not one of the
    /// box-drawing characters a border or a rule is drawn with. A press there
    /// on a list row is the text's.
    func isText(at point: Point) -> Bool {
        let point = onPage(point)
        guard point.y >= 0, point.y < frameLines.count, point.x >= 0 else { return false }
        let cells = Self.cells(of: frameLines[point.y])
        guard point.x < cells.count else { return false }
        var column = point.x
        // A wide character's second cell is the character's.
        while column > 0, cells[column] == nil { column -= 1 }
        guard let character = cells[column], !character.isWhitespace else { return false }
        let scalar = character.unicodeScalars.first?.value ?? 0
        return !(0x2500...0x259F).contains(scalar)
    }

    /// The columns `selection` covers on row `row`, snapped outwards to whole
    /// wide characters, or `nil` for a row it does not reach.
    static func columns(of selection: Selection, onRow row: Int, cells: [Character?]) -> Range<Int>? {
        let (start, end) = ends(of: selection, cells: { _ in cells })
        let clip = selection.clip
        guard row >= start.y, row <= end.y else { return nil }
        let clipEnd = clip.x + clip.width
        var range: Range<Int>
        switch selection.shape {
        case .rectangle:
            range = min(start.x, end.x)..<(max(start.x, end.x) + 1)
        case .stream:
            let left = row == start.y ? start.x : clip.x
            let right = row == end.y ? end.x + 1 : clipEnd
            range = left..<max(left, right)
        }
        range = max(range.lowerBound, clip.x)..<min(range.upperBound, clipEnd)
        // A wide character's second cell takes its first with it, and the
        // first takes the second.
        var lower = range.lowerBound
        while lower > 0, lower < cells.count, cells[lower] == nil { lower -= 1 }
        var upper = range.upperBound
        while upper < cells.count, upper > 0, cells[upper] == nil { upper += 1 }
        return lower < upper ? lower..<upper : nil
    }

    /// The selection's two ends in reading order — or, for a rectangle, its
    /// top and bottom rows — with its unit applied.
    static func ends(of selection: Selection, cells: (Int) -> [Character?]) -> (Point, Point) {
        var (start, end) = (selection.anchor, selection.head)
        if selection.shape == .stream, (end.y, end.x) < (start.y, start.x) { swap(&start, &end) }
        if selection.shape == .rectangle, end.y < start.y { swap(&start.y, &end.y) }
        switch selection.unit {
        case .character:
            break
        case .row:
            start.x = selection.clip.x
            end.x = selection.clip.x + selection.clip.width - 1
        case .word:
            start.x = wordBounds(at: start.x, in: cells(start.y), clip: selection.clip).lowerBound
            end.x = wordBounds(at: end.x, in: cells(end.y), clip: selection.clip).upperBound - 1
        }
        return (start, end)
    }

    /// The run of cells around `column` of one kind — a word, the blanks
    /// between words, or a run of other marks — within the clip: what a
    /// double-click selects.
    static func wordBounds(at column: Int, in cells: [Character?], clip: Rect) -> Range<Int> {
        let lower = clip.x
        let upper = min(clip.x + clip.width, cells.count)
        guard column >= lower, column < upper else { return column..<(column + 1) }
        func kind(_ index: Int) -> Int {
            // A wide character's second cell is the character's.
            var index = index
            while index > lower, cells[index] == nil { index -= 1 }
            guard let character = cells[index] else { return 2 }
            if WordBoundary.isWordCharacter(character) { return 0 }
            return character.isWhitespace ? 1 : 2
        }
        let wanted = kind(column)
        var start = column
        while start > lower, kind(start - 1) == wanted { start -= 1 }
        var end = column + 1
        while end < upper, kind(end) == wanted { end += 1 }
        return start..<end
    }

    /// The text `selection` covers in `lines`: wide characters once, each
    /// row's trailing blanks dropped, rows joined with line breaks.
    static func text(of selection: Selection, in lines: [String]) -> String {
        var cache: [Int: [Character?]] = [:]
        func cellsOf(_ row: Int) -> [Character?] {
            if let cached = cache[row] { return cached }
            let cells = row >= 0 && row < lines.count ? Self.cells(of: lines[row]) : []
            cache[row] = cells
            return cells
        }
        let (start, end) = ends(of: selection, cells: cellsOf)
        var rows: [String] = []
        for row in start.y...max(start.y, end.y) {
            var resolved = selection
            (resolved.anchor, resolved.head) = (start, end)
            resolved.unit = .character
            let cells = cellsOf(row)
            guard let columns = Self.columns(of: resolved, onRow: row, cells: cells) else { continue }
            var text = ""
            for column in columns where column < cells.count {
                if let character = cells[column] { text.append(character) }
            }
            while text.last == " " { text.removeLast() }
            rows.append(text)
        }
        return rows.joined(separator: "\n")
    }
}

// MARK: - Drawing the highlight

extension ScreenSelection {
    /// `buffer` with `selection`'s cells drawn in the selection colours of the
    /// text inputs (`TextFieldContentRenderer.selectionColors`), reverse video
    /// where the palette leaves the colours to the terminal.
    ///
    /// Composited as a painted layer over the page, so the cells
    /// under it give up what they claimed there: an opacity region stops
    /// fading them, and an animated run stops redrawing them, as under a menu.
    @MainActor
    static func highlighting(_ selection: Selection, in buffer: FrameBuffer, palette: any Palette)
        -> FrameBuffer
    {
        let colors = TextFieldContentRenderer.selectionColors(palette: palette, background: nil)
            .resolved(with: palette)
        var style = TextStyle()
        style.foregroundColor = colors.isReversed ? colors.background : colors.foreground
        style.backgroundColor = colors.isReversed ? colors.foreground : colors.background
        style.isInverted = colors.isReversed
        let introducer = ANSIRenderer.styleSequence(for: style)

        var cache: [Int: [Character?]] = [:]
        func cellsOf(_ row: Int) -> [Character?] {
            if let cached = cache[row] { return cached }
            let cells = row >= 0 && row < buffer.lines.count ? Self.cells(of: buffer.lines[row]) : []
            cache[row] = cells
            return cells
        }
        let (start, end) = ends(of: selection, cells: cellsOf)
        var resolved = selection
        (resolved.anchor, resolved.head) = (start, end)
        resolved.unit = .character

        // Rows with the same columns go in one layer: a stream selection is at
        // most three, a rectangle one.
        var result = buffer
        var band: (columns: Range<Int>, top: Int, lines: [String])?
        func flush() {
            guard let finished = band else { return }
            result = result.compositedResolvingOpacity(
                with: FrameBuffer(lines: finished.lines), at: (x: finished.columns.lowerBound, y: finished.top),
                palette: palette, overlayIsPainted: true)
            band = nil
        }
        for row in start.y...max(start.y, end.y) where row < buffer.lines.count {
            let cells = cellsOf(row)
            guard let columns = Self.columns(of: resolved, onRow: row, cells: cells) else {
                flush()
                continue
            }
            var text = ""
            for column in columns {
                if column < cells.count {
                    if let character = cells[column] { text.append(character) }
                } else {
                    text.append(" ")
                }
            }
            let line = ANSIRenderer.wrap(text, in: introducer)
            if let open = band, open.columns == columns, open.top + open.lines.count == row {
                band?.lines.append(line)
            } else {
                flush()
                band = (columns, row, [line])
            }
        }
        flush()
        return result
    }
}
