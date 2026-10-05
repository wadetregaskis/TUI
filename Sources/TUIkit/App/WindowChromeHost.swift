//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeHost.swift
//
//  The window's chrome — the app header above the page, the status bar below
//  it — drawn by the scene, as views, into one buffer with the page.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - WindowGroup

/// The bridge from the `Scene` hierarchy to `View` rendering: the window
/// group's content, framed by its chrome, as one ``FrameBuffer`` the size of
/// the terminal. Terminal output (diffing, writing) is handled by `RenderLoop`
/// via `FrameDiffWriter`.
///
/// Like SwiftUI, `WindowGroup` centres its content both horizontally and
/// vertically within the space the chrome leaves it.
extension WindowGroup: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(_WindowChromeHost(content: content), context: context)
    }
}

// MARK: - The Chrome Host

/// The scene-level host that lays the window out: the app header, the content,
/// and the status bar, stacked into one buffer the size of the terminal.
///
/// The chrome is drawn here, in the tree, rather than by the run loop around
/// it. The run loop once built each bar outside the tree and wrote it as a
/// region of its own, and everything that crosses between a bar and the page
/// had to be forwarded by hand: pointer coordinates translated below the
/// header, the bars' hit regions shifted onto the screen, a header menu's
/// drop-down lifted onto the page, each bar's opacity resolved against its own
/// surface, the bars' animated runs kept apart because the replay could not
/// patch them. Here the bars are rows of the frame like any other, so the
/// frame is one coordinate space — the screen's.
///
/// What it does, per walk of the scene:
///
/// 1. Reserves the rows the bars take: the header's ``AppHeaderState/reservedHeight``
///    (the run loop's estimate, corrected by a second walk when the page's
///    header turns out a different height), and the status bar's height as it
///    stands before the page declares its items.
/// 2. Draws the content in what is left, at the content's own identity — this
///    view stores nothing of its own, so no `@State` or focus ID moves.
/// 3. Composites the content's overlay layers inside the content area, with the
///    header's anchored layers lifted onto it, so a modal's dimming stops at
///    the chrome.
/// 4. Draws each bar as its view, on its own surface, and stacks the three.
///
/// A measuring walk (the run loop's first-frame walk, whose only output is the
/// header's height) draws the content and nothing else.
struct _WindowChromeHost<Content: View>: View, Renderable {
    /// The window's content.
    let content: Content

    var body: Never { fatalError("_WindowChromeHost renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        let appHeader = context.environment.appHeader
        let statusBar = context.environment.statusBar
        // Read before the content draws, so the page's own declarations — made
        // as it draws, and cleared before every walk — do not count yet.
        let headerRows = appHeader?.reservedHeight ?? 0
        let statusBarRows = statusBar?.height ?? 0
        let contentHeight = contentAreaHeight(
            terminalHeight: height, statusBarHeight: statusBarRows, headerHeight: headerRows)

        var contentContext = context
        contentContext.availableHeight = contentHeight
        // Anchored overlays (a Picker drop-down) size to the area the
        // compositor will clamp them to — between the bars — rather than to
        // the full terminal height, which would shave their bottom rows off
        // against the status bar.
        contentContext.environment.overlayContentHeight = contentHeight
        var page = placeContent(context: contentContext, rowsAbove: headerRows)
        guard !context.isMeasuring else { return page }

        let palette = context.environment.palette
        let backgrounds = RenderBackgroundCodes(palette: palette)
        let header = appHeader.flatMap {
            headerBuffer($0, width: width, context: context, liftingOverlaysOnto: &page)
        }
        // The screen selection reads the page and draws its highlight on it,
        // before the layers over the page — so a menu opened over it draws
        // over the highlight rather than through it. Nothing but a reference
        // to the lines while nothing is selected (`ScreenSelection`).
        let isUnderPresentation = context.environment.focusManager?.activeSectionIsModal == true
        if let selection = context.environment.screenSelection {
            page = selection.takeFrame(
                page, width: width, palette: palette, top: header?.height ?? 0,
                underPresentation: isUnderPresentation)
        }
        // Composite every free-floating overlay layer (Picker drop-downs,
        // popovers, …) emitted during rendering onto the content area only:
        // that is what keeps the chrome out from under a modal's dimming.
        if !page.overlays.isEmpty {
            page = page.compositingOverlays(maxWidth: width, maxHeight: contentHeight, palette: palette)
        }

        var frame = FrameBuffer()
        if var header {
            header = header.resolvingOpacity(surface: palette.appHeaderBackground, palette: palette)
                .groundedAsChrome(width: width, background: backgrounds.appHeader)
            // The header is drawn OUTSIDE the composited content area, so
            // nothing a presentation does can reach it: the modifier isolates
            // what it wraps, and the compositor dims what it composites. A
            // modal's guarantee is that the page beneath is inert, and a header
            // button is part of that page — it was still firing on a click with
            // a dialog up, the last of the channels a presentation has to close.
            //
            // Its regions only, not its appearance. The header stays legible
            // because it is chrome the app draws around every screen, like the
            // status bar, which likewise keeps `q quit` live behind a modal by
            // design. What it must not do is answer a click that the same
            // page's body would refuse.
            if isUnderPresentation {
                header.hitTestRegions = []
            }
            frame.appendVertically(header)
        }
        frame.appendVertically(page)
        // `hasContent`, not `hasItems`: the question `statusBar.height`
        // answered when it took the rows, so a tooltip on a bar with no items
        // is drawn into the rows it reserved rather than leaving them blank.
        if let statusBar, statusBar.hasContent {
            let bar = statusBarBuffer(statusBar, width: width, context: context)
                .resolvingOpacity(surface: palette.statusBarBackground, palette: palette)
                .groundedAsChrome(width: width, background: backgrounds.statusBar)
            frame.appendVertically(bar)
        }
        return frame
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
        let buffer = TUIkit.renderToBuffer(
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
        if let frame = dragSession?.liftedPreviewFrame(),
            let preview = dragSession?.liftedPreviewContent()
        {
            centered.overlays.append(
                OverlayLayer(
                    offsetX: frame.x,
                    offsetY: frame.y - rowsAbove,
                    content: Self.card(preview, palette: context.environment.palette),
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
        // a terminal shorter than its own status bar plus app header. Clamping at
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

    // MARK: The bars

    /// The app header, framed by its style, or `nil` when no `.appHeader { … }`
    /// drew this walk. Its anchored overlay layers — a `Menu`'s drop-down, a
    /// popover — go onto `page`, where the page's own are composited.
    private func headerBuffer(
        _ appHeader: AppHeaderState, width: Int, context: RenderContext,
        liftingOverlaysOnto page: inout FrameBuffer
    ) -> FrameBuffer? {
        guard appHeader.hasContent, let contentBuffer = appHeader.contentBuffer else { return nil }
        let headerContext = RenderContext(
            availableWidth: width, availableHeight: appHeader.height, environment: context.environment)
        return TUIkit.renderToBuffer(
            AppHeader(contentBuffer: contentBuffer, style: appHeader.style), context: headerContext
        )
        .liftingOverlays(shiftingBy: -appHeader.height, onto: &page)
    }

    /// The status bar as this walk left its state: the page's items, the
    /// system items, and the tooltip row.
    private func statusBarBuffer(_ statusBar: StatusBarState, width: Int, context: RenderContext) -> FrameBuffer {
        // The two colours go through as the app set them. An unset one is the
        // palette's accent or foreground, and every colour is resolved against
        // the palette inside `StatusBar` itself.
        let drawsItems = statusBar.drawsItems
        let view = StatusBar(
            userItems: drawsItems ? statusBar.currentUserItems : [],
            systemItems: drawsItems ? statusBar.currentSystemItems : [],
            style: statusBar.style,
            alignment: statusBar.alignment,
            highlightColor: statusBar.highlightColor,
            labelColor: statusBar.labelColor,
            tooltipLines: statusBar.tooltipLines
        )
        let barContext = RenderContext(
            availableWidth: width, availableHeight: view.height, environment: context.environment)
        return TUIkit.renderToBuffer(view, context: barContext)
    }
}

// MARK: - Grounding a Bar

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
}
