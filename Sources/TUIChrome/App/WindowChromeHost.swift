//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowChromeHost.swift
//
//  The window's chrome — a toolbar above the page, a toolbar below
//  it — drawn by the scene, as views, into one buffer with the page.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The Chrome Host

/// The scene-level host that lays the window out: the menu bar, the top bar,
/// the content, and the bottom bar, stacked into one buffer the size of the
/// terminal.
///
/// Every bar is opt-in. A bar exists while a `.toolbar` places something in it
/// (``ToolbarItemPlacement``), and an app that places nothing draws on every
/// row of the terminal. The line of key hints is a view the app places in the
/// bottom bar, ``StatusBar``'s `init()`; the keys it names work with no bar at
/// all. The menu bar is the scene's: it exists while the scene declares
/// commands (TUICommands), on the top row (``WindowChromeState/menuBar``).
///
/// The chrome is drawn here, in the tree, rather than by the run loop around
/// it. The run loop once built a header and a status bar outside the tree and
/// wrote each as a region of its own, and everything that crosses between a
/// bar and the page had to be forwarded by hand: pointer coordinates translated
/// below the header, the bars' hit regions shifted onto the screen, a header
/// menu's drop-down lifted onto the page, each bar's opacity resolved against
/// its own surface, the bars' animated runs kept apart because the replay
/// could not patch them. Here the bars are rows of the frame like any other,
/// so the frame is one coordinate space — the screen's.
///
/// What it does, per walk of the scene:
///
/// 1. Reserves the rows the bars take: LAST frame's answer, from
///    ``WindowChromeState`` (see there for why it cannot be this walk's), and
///    for the bottom bar this frame's tooltip row, whose triggers all land
///    between frames.
/// 2. Draws the content in what is left, at the content's own identity — this
///    view stores nothing of its own, so no `@State` or focus ID moves — less
///    the rows a sheet docked live at the bottom takes, which last frame's
///    presenters said (``FocusManager/presentationDock(in:storage:)``): the page is
///    laid out in the rows above it.
/// 3. Draws each bar's items after the content, so their focus sections follow
///    the page's, and composites the content's overlay layers — with the bars'
///    anchored ones lifted onto them — inside the content area, so a modal's
///    dimming stops at the chrome. The menu bar is drawn last, after the
///    toolbars, so a command reading the focused view's `@FocusedValue` reads
///    what this walk published; its open menu hangs over the whole window.
/// 4. Frames each bar in its style, on its own surface, fitted to the rows it
///    reserved, and stacks the three.
/// 5. Settles the reservations against what the content declared this walk,
///    asking for the frame that adopts a change.
///
/// A measuring walk (the run loop's first-frame walk, which seeds the
/// reservations) draws the content and nothing else. A walk with no
/// ``WindowChromeState`` in its environment — a scene rendered outside an app,
/// which has no frames to adopt anything in — draws the content with its
/// overlays composited, and no chrome.
package struct _WindowChromeHost<Content: View>: View, Renderable {
    /// The window's content.
    let content: Content

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and `WindowGroup` (TUIApp) makes these.
    package init(content: Content) {
        self.content = content
    }

    package var body: Never { fatalError("_WindowChromeHost renders via Renderable") }

    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        let chrome = context.environment.windowChrome
        // A split view whose bar button for its sidebar has gone draws its ▶
        // edge column again (`WindowChromeState.hasBarToggle(for:)`).
        if let chrome, !context.isMeasuring {
            for owner in chrome.takeDroppedBarToggles() { context.renderCache?.invalidateRender(for: owner) }
        }
        // This frame's tooltip rows — not the line about a copy while it stands
        // in for the line of key hints' items, in their row
        // (`StatusBarState.linesAboveItems`).
        let hints = chrome == nil ? nil : context.environment.statusBar
        let tooltip = hints?.linesAboveItems ?? []
        // Last frame's rows, in this frame's styles — and, below, this frame's
        // tooltip.
        let rows = chrome.map { reservedRows($0, tooltipRows: tooltip.count, height: height) } ?? Rows()
        let contentHeight = contentAreaHeight(
            terminalHeight: height, statusBarHeight: rows.bottom, headerHeight: rows.menu + rows.top)
        // A sheet docked live at the bottom of the content area takes its rows
        // from the page, which is laid out in the rows above it: last frame's
        // answer, asked before the walk (`FocusManager.notePresentationDock`).
        let focusManager = context.environment.focusManager
        let dock = focusManager?.presentationDock(in: contentHeight, storage: context.stateStorage) ?? 0

        // Placed below the menu bar's and the top bar's rows, which a reader
        // in the content is told (the carried geometry origin,
        // `RenderContext.placingChild`).
        var contentContext = context.placingChild(gradient: nil, x: 0, y: rows.menu + rows.top)
        contentContext.availableHeight = contentHeight - dock
        // Anchored overlays (a Picker drop-down) size to the area the
        // compositor will clamp them to — between the bars — rather than to
        // the full terminal height, which would shave their bottom rows off
        // against the bottom bar. The whole of it, dock included: the docked
        // sheet is one of them, and a page's drop-down may draw over it.
        contentContext.environment.overlayContentHeight = contentHeight
        // The content offers the window its title as it draws — on the seeding
        // walk too, although it measures, since the title sizes the top bar
        // (`PreferenceModifier.offerToWindowChrome`).
        var page = placeContent(context: contentContext, rowsAbove: rows.menu + rows.top)
        guard !context.isMeasuring else {
            if let chrome, context.environment.seedsWindowChrome {
                for edge in WindowChromeState.Edge.allCases {
                    chrome.seed(edge, rows: toolbarContentRows(edge, chrome: chrome, width: width, context: context))
                }
            }
            return page
        }
        // The rows the tooltip took from the page, which a pointer resting on
        // one of them still rests on for the tooltip's own view
        // (`WindowChromeState.tooltipRows`).
        if let chrome, !tooltip.isEmpty {
            let barAlone = min(height, Self.toolbarHeight(contentRows: chrome.rows(.bottom), style: chrome.style))
            chrome.tooltipRows = (height - rows.bottom)..<max(height - rows.bottom, height - barAlone)
        }
        // The dock's rows, blank under the sheet composited onto them.
        if dock > 0 { page = page.placedVertically(inHeight: contentHeight, topPadding: 0) }

        let palette = context.environment.palette
        let isModal = context.environment.focusManager?.activeSectionIsModal == true
        // The toolbars, after the content, so their sections follow the page's
        // in the Tab ring. Their anchored layers (a `Menu`'s drop-down) go onto
        // the page, to be composited with its own. Their items are laid out in
        // the rows of each bar the frame shows (`itemRowsShown`).
        let itemRows = chrome.map { itemRowsShown($0, in: rows, tooltipRows: tooltip.count) } ?? Rows()
        // What each bar is filled with: stated by the page as it drew, so this
        // frame's (`.toolbarBackground(_:for:)`).
        let topGround = chrome.map { barGround(.top, chrome: $0, context: context) }
        let bottomGround = chrome.map { barGround(.bottom, chrome: $0, context: context) }
        // Each bar's rows as this walk declared them: drawn now, in the rows
        // last frame reserved, and settled below as the next frame's.
        let topRows = chrome.map { barRows(.top, chrome: $0, width: width, context: context) } ?? []
        let bottomRows = chrome.map { barRows(.bottom, chrome: $0, width: width, context: context) } ?? []
        var drawn = Set<ViewIdentity>()
        // A customizable toolbar's context menu and panel hang from the top
        // bar's first row, or the bottom bar's where there is no top bar.
        let customizable = !(chrome?.customizableToolbars.isEmpty ?? true)
        var top = chrome.flatMap { chrome in
            topGround.flatMap {
                toolbarBuffer(
                    BarDrawing(
                        edge: .top, rows: topRows, contentRows: chrome.rows(.top), itemRows: itemRows.top, ground: $0,
                        hostsCustomization: customizable),
                    chrome: chrome, width: width, isModal: isModal, drawn: &drawn, context: context)
            }
        }
        var bottom = chrome.flatMap { chrome in
            bottomGround.flatMap {
                toolbarBuffer(
                    BarDrawing(
                        edge: .bottom, rows: bottomRows, contentRows: chrome.rows(.bottom), itemRows: itemRows.bottom,
                        tooltip: tooltip, ground: $0, hostsCustomization: customizable && topRows.isEmpty),
                    chrome: chrome, width: width, isModal: isModal, drawn: &drawn, context: context)
            }
        }
        if let chrome { retainUndrawnItems(chrome, drawn: drawn, context: context) }
        // The menu bar, after both toolbars: the last thing drawn, so the
        // commands it renders read this walk's focused values.
        let menu = rows.menu > 0 ? chrome?.menuBar.map {
            menuBarBuffer($0, width: width, height: height, isModal: isModal, context: context)
        } : nil
        // After the toolbars, whose items present sheets too: a dock one of
        // them posts is compared with the page's like any other.
        if let focusManager { settleDock(dock, focusManager: focusManager, contentHeight: contentHeight, context: context) }
        top = top?.liftingOverlays(shiftingBy: -rows.top, onto: &page)
        bottom = bottom?.liftingOverlays(shiftingBy: contentHeight, onto: &page)
        // The screen selection reads the page and draws its highlight on it,
        // before the layers over the page — so a menu opened over it draws
        // over the highlight rather than through it. Nothing but a reference
        // to the lines while nothing is selected (`ScreenSelection`). An app's
        // frames only: a scene drawn outside one selects nothing.
        if chrome != nil, let selection = context.environment.screenSelection {
            page = selection.takeFrame(
                page, width: width, palette: palette, top: rows.menu + rows.top, underPresentation: isModal)
        }
        // Composite every free-floating overlay layer (Picker drop-downs,
        // popovers, …) emitted during rendering onto the content area only:
        // that is what keeps the chrome out from under a modal's dimming.
        if !page.overlays.isEmpty {
            // What is presented over the page, counted before the layers are
            // spent (`WindowChromeState.presentationsOverPage`).
            chrome?.presentationsOverPage = Self.presentations(in: page.overlays)
            page = page.compositingOverlays(
                maxWidth: width, maxHeight: contentHeight, palette: palette,
                images: context.environment.terminalImageStore)
        }
        guard let chrome else { return page }

        let frame = stacked(
            Bars(
                menu: menu, top: top, bottom: bottom, topBackground: topGround?.code ?? "",
                bottomBackground: bottomGround?.code ?? ""),
            around: page, in: rows, width: width, height: height,
            chrome: chrome, palette: palette)

        // What the content declared this walk becomes the next frame's rows.
        let now = context.environment.frameNowNanos
        for edge in WindowChromeState.Edge.allCases {
            let wanted = Self.contentRows(of: edge == .top ? topRows : bottomRows)
            settle(chrome.settle(edge, wanting: wanted, nowNanos: now), context: context)
        }
        return frame
    }

    /// The surfaces among `layers` presented over the page, those riding in
    /// another's content too (an alert presented from a sheet): a panel
    /// placed over the content area — a sheet, docked or not, a cover, an
    /// alert (``OverlayLayer/isScreenLevel``) — or a layer holding the input
    /// — a popover, a menu, a drop-down (``OverlayLayer/holdsInput``). Not a
    /// tooltip's panel, a toast, a dragged row's picture or a view's own
    /// displaced drawing.
    static func presentations(in layers: [OverlayLayer]) -> [PresentedSurface] {
        layers.flatMap { layer in
            let own =
                layer.isScreenLevel || layer.holdsInput
                ? [
                    PresentedSurface(
                        isScreenLevel: layer.isScreenLevel, holdsInput: layer.holdsInput,
                        identity: layer.surfaceIdentity)
                ] : []
            return own + presentations(in: layer.content.overlays)
        }
    }

    /// The rows each bar takes this frame, framing included.
    struct Rows {
        /// The menu bar's row, above the top bar: 1 while the scene declares
        /// commands, if the terminal has a row to spare.
        var menu = 0
        /// The top bar's rows, above the content.
        var top = 0
        /// The rows below the content.
        var bottom = 0
    }

    /// Last frame's rows for each toolbar, in this frame's styles, with
    /// `tooltipRows` added to the bottom bar's: a tooltip with no bottom bar
    /// takes a bar of its own while it shows. And this frame's row for the
    /// menu bar, which the scene states.
    ///
    /// In a terminal of `height` rows too short for every bar, the bottom bar
    /// keeps its rows, the menu bar its one, and the top bar gets what is
    /// left, cut from its end. The line of key hints lives in the bottom bar
    /// and is how a person finds the keys, so it is the one that stays whole —
    /// as it did when the run loop wrote it last, over the header, at the foot
    /// of the screen. Stacked uncut, the frame was taller than the screen and
    /// the writer dropped its last rows: the bottom bar's. The menu bar is the
    /// keyboard's way to the commands that have no key of their own, so it
    /// gives way only to the bottom bar.
    private func reservedRows(_ chrome: WindowChromeState, tooltipRows: Int, height: Int) -> Rows {
        let bottom = min(
            height, Self.toolbarHeight(contentRows: chrome.rows(.bottom) + tooltipRows, style: chrome.style))
        let menu = chrome.menuBar == nil ? 0 : min(height - bottom, 1)
        let top = min(height - bottom - menu, Self.toolbarHeight(contentRows: chrome.rows(.top), style: chrome.style))
        return Rows(menu: menu, top: top, bottom: bottom)
    }

    /// How many rows of each bar's content its items are laid out in: all of
    /// them, or, in a terminal too short to show the whole bar
    /// (``reservedRows(_:tooltipRows:height:)`` cuts it from its end), as
    /// many as the frame `shown` shows — none, if it shows only the bar's
    /// frame.
    ///
    /// An item on a row the frame cut off was still drawn, live: in the Tab
    /// ring, its shortcut firing, a button nobody could see. Laid out in the
    /// rows that show, every item drawn is one the person can see, and a bar
    /// that shows none of its rows draws no item (keeping their `@State`, as
    /// a hidden bar's).
    private func itemRowsShown(_ chrome: WindowChromeState, in shown: Rows, tooltipRows: Int) -> Rows {
        func rows(_ edge: WindowChromeState.Edge, shown: Int, before: Int) -> Int {
            let style = chrome.style(edge)
            let above = Self.framedRowsAbove(style: style, ruleAbove: edge == .bottom) + before
            return min(chrome.rows(edge), max(0, shown - above))
        }
        return Rows(
            top: rows(.top, shown: shown.top, before: 0),
            bottom: rows(.bottom, shown: shown.bottom, before: tooltipRows))
    }

    /// Asks for the frame a settlement owes: the next one, through the
    /// scheduler, so a still screen still adopts the change; or one at the
    /// instant an oscillation's pin lapses.
    private func settle(_ settlement: WindowChromeState.Settlement, context: RenderContext) {
        switch settlement {
        case .settled:
            break
        case .nextFrame:
            context.requestAnimation(
                token: "window-chrome-adoption", frameTicks: AnimationClock.standardFrameTicks)
        case .frame(let instant):
            context.requestWake(token: "window-chrome-pin", atNanos: instant)
        }
    }

    /// Asks for the next frame when the docks this walk posted ask for
    /// another height than the `dock` it was laid out short by — a dock
    /// learnt late (``FocusManager/postedPresentationDock(in:)``). The frame
    /// drawn is honest at the old height, the sheet over the page's bottom
    /// rows, and the next adopts the new one, as a bar's rows are adopted.
    private func settleDock(_ dock: Int, focusManager: FocusManager, contentHeight: Int, context: RenderContext) {
        guard
            focusManager.settlePresentationDock(laidOutBy: dock, in: contentHeight, storage: context.stateStorage)
        else { return }
        context.requestAnimation(token: "presentation-dock-adoption", frameTicks: AnimationClock.standardFrameTicks)
    }

    // MARK: The content

    /// The content, drawn into the area the bars leave and centred in it — over
    /// the window background, when the content set one — with the drag preview
    /// riding above it.
    private func placeContent(context: RenderContext, rowsAbove: Int) -> FrameBuffer {
        // Drop targets re-register as the tree renders (like focus), so the
        // drag session's per-frame registry resets here, before the pass.
        let dragSession = context.environment.dragAndDropSession
        dragSession?.beginFrame()

        // The content's preferences in a scope of their own, so a
        // `containerBackground(for: .window)` inside it can be read here; the
        // pop merges them into the root's as before.
        let preferences = context.environment.preferenceStorage
        preferences?.push()
        // The content area is the window's `containerRelativeFrame` container.
        let buffer = TUIView.renderToBuffer(
            content,
            context: context.publishingContainerSize(
                CellSize(width: max(0, context.availableWidth), height: max(0, context.availableHeight))))
        let background = preferences?.pop()[ContainerBackgroundKey.self]

        var centered =
            if let background {
                windowContent(buffer, over: background, context: context)
            } else {
                Self.centerBuffer(buffer, inWidth: context.availableWidth, height: context.availableHeight)
            }

        // The screen selection's context menu, over the page it selected from:
        // anchored at the right-clicked cell, which the selection keeps in
        // these same content-area coordinates once the content is centred.
        context.environment.screenSelection?.presentMenu(over: &centered, context: context)

        // The floating drag preview rides above everything. Its frame is in
        // the screen's coordinates, which are the pointer's, so it is moved up
        // by the rows above the content to sit on the content's; where it sits
        // relative to the cursor is the drag's ``DragPreviewAnchor`` (grab-point
        // by default — the pressed cell stays under the cursor, macOS-style),
        // resolved by the session so drops report the same frame.
        //
        // The LIFTED frame: for the first ~120 ms the picture is still on its
        // way out of the row it came from. See `liftedPreviewFrame()` for why
        // that blend lives at the draw site rather than in the anchor math.
        //
        // It wears a badge in its top-right cell naming the operation a drop
        // there would be, macOS's pointer badge (decisions B10, B-BITEMS1-1).
        if let frame = dragSession?.liftedPreviewFrame(),
            let preview = dragSession?.liftedPreviewContent()
        {
            let palette = context.environment.palette
            // Option held on the keyboard flips the operation, where the
            // terminal reports it held alone: read here, as the badge draws,
            // which asks for a frame when it changes, so the badge follows
            // the key with the pointer still (B-BITEMS1-1).
            if let monitor = context.environment.modifierKeyMonitor {
                if !context.isMeasuring { monitor.noteDrawnFrom(.option) }
                dragSession?.keyboardFlipsOperation = monitor.current.contains(.option)
            }
            centered.overlays.append(
                OverlayLayer(
                    offsetX: frame.x,
                    offsetY: frame.y - rowsAbove,
                    content: DragAndDropSession.badged(
                        Self.card(preview, palette: palette), operation: dragSession?.proposedOperation,
                        palette: palette),
                    level: .notification,
                    // Pinned to the pointer: clipped at the screen edge, never
                    // slid back onto it. Sliding is what made a wide preview
                    // stop following the cursor a few cells in.
                    clampsToScreen: false,
                    // A lifted row is a card over the page, not a stencil: it
                    // covers what is under it. Stated rather than defaulted so
                    // the choice is visible where the layer is made.
                    isOpaque: true
                )
            )
        } else if let step = dragSession?.returnFlightFrame {
            // A cancelled drag on its way home: the same overlay, walking back
            // to where the row started. The render loop advances it and keeps
            // asking for frames; this draws wherever it has got to.
            centered.overlays.append(
                OverlayLayer(
                    offsetX: step.x, offsetY: step.y - rowsAbove,
                    content: Self.card(step.preview, palette: context.environment.palette),
                    level: .notification, clampsToScreen: false,
                    isOpaque: true))  // the same card, on its way home
        }
        return centered
    }

    /// `preview` as the card it is lifted as: on the page's colour, which the
    /// compositor paints under its blanks (``OverlayLayer/isOpaque``), and with every
    /// fade inside it spent against that — the card is behind them.
    ///
    /// Here, where the card is made, because the compositor cannot: it spends a
    /// layer's fades against its surface only for a centred one, since an anchored
    /// layer may carry its presenter's fade, which has to take the surface with it
    /// (`Opacity as composition.md` §96.2). A drag preview has no presenter — it is
    /// made here, at the root, from what a row or a view drew — so every fade it
    /// carries is its content's own. Left to the compositor they were resolved
    /// against the page BEHIND the card: below one half the page's glyphs won the
    /// faded cells, through the card (§106). Nothing to spend, nothing built.
    private static func card(_ preview: FrameBuffer, palette: any Palette) -> FrameBuffer {
        guard preview.hasFadeOnWhatIsBehind else { return preview }
        return preview.paintedOver(background: ANSIRenderer.backgroundCode(for: palette.background.resolve(with: palette)))
            .resolvingOpacity(onOpaqueFill: { nil }, surface: palette.background, palette: palette)
    }

    /// Centers a buffer within the target dimensions.
    private static func centerBuffer(_ buffer: FrameBuffer, inWidth targetWidth: Int, height targetHeight: Int) -> FrameBuffer {
        // If buffer already fills the space exactly, return as-is
        if buffer.width == targetWidth && buffer.height == targetHeight {
            return buffer
        }

        // Total for ANY target, not just a sane one. The content area is
        // clamped at zero, but this must not *depend* on that: a negative
        // target used to reach the row loop below as `0..<negative` and trap
        // ("Range requires lowerBound <= upperBound") — the app died on launch in
        // a terminal shorter than its own bars. Clamping at
        // the source fixes the bug; clamping here keeps it fixed.
        let targetWidth = max(0, targetWidth)
        let targetHeight = max(0, targetHeight)

        var result: [String] = []
        result.reserveCapacity(targetHeight)

        // Calculate offsets for centering
        let verticalOffset = max(0, (targetHeight - buffer.height) / 2)
        let horizontalOffset = max(0, (targetWidth - buffer.width) / 2)

        // The full-width blank rows are identical, so build one and reuse it.
        let blankRow = String(asciiSpaces(targetWidth))

        // Add top padding (empty lines)
        for _ in 0..<verticalOffset {
            result.append(blankRow)
        }

        // Add content lines with horizontal centering. Each centred line is built
        // in place — reserve once, then append the leading spaces, the line, and
        // the trailing spaces as borrowed runs. Byte-identical to
        // `leftPadding + line + String(repeating:)` without the temporaries.
        for row in 0..<min(buffer.height, targetHeight - verticalOffset) {
            let line = buffer.lines[row]
            let rightPadding = max(0, targetWidth - horizontalOffset - line.strippedLength)
            var centered = ""
            centered.reserveCapacity(line.utf8.count + horizontalOffset + rightPadding)
            if horizontalOffset > 0 { centered += asciiSpaces(horizontalOffset) }
            centered += line
            if rightPadding > 0 { centered += asciiSpaces(rightPadding) }
            result.append(centered)
        }

        // Add bottom padding (empty lines)
        let bottomPadding = max(0, targetHeight - verticalOffset - buffer.height)
        for _ in 0..<bottomPadding {
            result.append(blankRow)
        }

        // The content shifted right by `horizontalOffset` and down by
        // `verticalOffset`; carry overlay layers AND hit-test regions
        // by the same amount so they stay anchored to the content
        // they were emitted alongside. Using the bare
        // FrameBuffer(lines:) initializer here would silently discard
        // every region the view tree built up, with the highly
        // misleading symptom "clicks on TextFields / Buttons /
        // anything do nothing, but only on pages whose content
        // doesn't exactly fill the terminal".
        return buffer.replacingLines(
            result,
            overlayShiftX: horizontalOffset,
            overlayShiftY: verticalOffset
        )
    }
}

// MARK: - Grounding and Fitting a Bar

extension FrameBuffer {
    /// This bar with its own background under every cell, out to `width`.
    ///
    /// A bar has a surface of its own (``Palette/appHeaderBackground``,
    /// ``Palette/statusBarBackground``), and the frame's rows are built over the
    /// PAGE's: each row is erased in the page's background before its cells are
    /// written. So a bar row states its background on every cell that names
    /// none, and is padded to the full width so the cells past its last glyph
    /// are the bar's too.
    func groundedAsChrome(width: Int, background: String) -> FrameBuffer {
        guard !background.isEmpty else { return self }
        let padded = lines.map { line -> String in
            let missing = width - line.strippedLength
            return missing > 0 ? line + String(asciiSpaces(missing)) : line
        }
        return replacingLines(padded).paintedOver(background: background)
    }

    /// This bar in exactly `rows` rows: cut to them when it declared more this
    /// walk than last frame reserved, and padded with rows of its background
    /// when it declared fewer — the frame is drawn honestly at the old
    /// reservation, and the next one adopts the new (see `WindowChromeState`).
    func fittedAsChrome(toRows rows: Int, width: Int, background: String) -> FrameBuffer {
        if height > rows { return clamped(toWidth: width, height: rows) }
        guard height < rows else { return self }
        var padded = self
        let blank = FrameBuffer(lines: Array(repeating: String(asciiSpaces(width)), count: rows - height))
        padded.appendVertically(blank.groundedAsChrome(width: width, background: background))
        return padded
    }
}
