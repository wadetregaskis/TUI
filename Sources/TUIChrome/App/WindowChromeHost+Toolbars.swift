//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowChromeHost+Toolbars.swift
//
//  The window's two toolbars, as the chrome host draws them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _WindowChromeHost {
    /// The rows a toolbar of `contentRows` rows takes in `style`, or 0 for
    /// none.
    static func toolbarHeight(contentRows: Int, style: ChromeStyle) -> Int {
        contentRows > 0 ? style.barHeight(contentRows: contentRows) : 0
    }

    /// The rows of content the items declared for the toolbar at `edge` want:
    /// the sum of its rows' (``barRows(_:chrome:width:context:)``) — each
    /// row's tallest item at the bar's width, and the title's in the top
    /// bar's title slot — measured, so finding it registers nothing; 0 when
    /// nothing is placed there, or what is placed draws nothing (a `StatusBar()`
    /// with no items to show).
    func toolbarContentRows(
        _ edge: WindowChromeState.Edge, chrome: WindowChromeState, width: Int, context: RenderContext
    ) -> Int {
        Self.contentRows(of: barRows(edge, chrome: chrome, width: width, context: context))
    }

    /// The rows of content `rows` take together.
    static func contentRows(of rows: [BarRow]) -> Int {
        rows.reduce(0) { $0 + $1.rows }
    }

    /// What the title slot of the bar at `edge` shows: the window's title and
    /// subtitle in the top bar — unless the window toolbar style says not to —
    /// and nothing in the bottom one.
    func titleSlot(_ edge: WindowChromeState.Edge, chrome: WindowChromeState) -> (String, String) {
        edge == .top && chrome.showsTitle && !chrome.titleRemoved ? (chrome.title, chrome.subtitle) : ("", "")
    }

    /// The toolbar at `edge`, framed and on its own background, in the
    /// `contentRows` it reserved — with the bottom bar's tooltip rows above
    /// its items — or `nil` when there is nothing to draw.
    ///
    /// Its items are laid out in the first `itemRows` of those rows: all of
    /// them, unless the terminal is too short to show the whole bar, when
    /// they are the rows it shows (`itemRowsShown`), and with none
    /// the bar is drawn with no items in it. The top bar's rows are its own
    /// and then its accessory bars' (``barRows(_:chrome:width:context:)``),
    /// given out in that order, so a short terminal cuts the last accessory
    /// bar first. Every item drawn is added to `drawn`.
    ///
    /// Its items are in an optional focus section of their own, after the
    /// page's, so Tab reaches them last and they never take the initial focus.
    /// While a modal holds the input the bar is drawn inert — on throwaway
    /// focus and key channels, its items' click regions dropped — except for
    /// the line of key hints, where a click still does what the key would, as
    /// a press of the key does behind a modal (see `_ToolbarEntryView`).
    func toolbarBuffer(
        _ bar: BarDrawing, chrome: WindowChromeState, width: Int, isModal: Bool, drawn: inout Set<ViewIdentity>,
        context: RenderContext
    ) -> FrameBuffer? {
        let (edge, contentRows, itemRows, tooltip, ground) = (bar.edge, bar.contentRows, bar.itemRows, bar.tooltip, bar.ground)
        // A bar the page no longer declares anything for keeps its reserved
        // rows for the frame, blank: the caller pads them with its background.
        let rows = contentRows > 0 ? bar.rows : []
        let hasItems = !rows.isEmpty
        guard hasItems || !tooltip.isEmpty else { return nil }
        let style = chrome.style(edge)
        let contentWidth = style.barContentWidth(width)
        var row = FrameBuffer()
        if !tooltip.isEmpty {
            row.appendVertically(tooltipRows(tooltip, width: contentWidth, context: context))
        }
        if hasItems {
            let sectionID = Self.toolbarSectionID(edge)
            if !isModal { context.environment.focusManager?.registerPassiveSection(id: sectionID) }
            // The rows the frame shows, given out from the top: framed but
            // empty where it shows none of them.
            var left = max(0, itemRows)
            var items = FrameBuffer()
            for (index, barRow) in rows.enumerated() {
                let shown = min(barRow.rows, left)
                left -= shown
                guard shown > 0 else { continue }
                var rowContext = barContext(
                    edge, row: index, width: width, rows: shown, style: style, context: context)
                if isModal { rowContext = rowContext.isolatedForBackground() }
                rowContext.environment.activeFocusSectionID = sectionID
                let barRowView = _ToolbarBarRow(
                    entries: barRow.entries, title: barRow.title, subtitle: barRow.subtitle,
                    keepsTitleBesidePrincipal: chrome.titleBesidePrincipal)
                let drawnRow =
                    (bar.hostsCustomization && index == 0
                    ? TUIView.renderToBuffer(
                        _ToolbarCustomizationHost(content: barRowView, chrome: chrome), context: rowContext)
                    : TUIView.renderToBuffer(barRowView, context: rowContext))
                    .fittedAsChrome(toRows: shown, width: contentWidth, background: "")
                items.appendVertically(
                    accessoryGround(barRow.accessory, of: drawnRow, chrome: chrome, width: contentWidth, context: rowContext))
                for entry in barRow.entries { drawn.insert(entry.identity) }
            }
            row.appendVertically(items.fittedAsChrome(toRows: contentRows, width: contentWidth, background: ""))
        }
        let palette = context.environment.palette
        let bar = framed(row, style: style, ruleAbove: edge == .bottom, width: width, context: context)
            .resolvingOpacity(surface: ground.surface, palette: palette)
        guard let painted = ground.style else { return bar.groundedAsChrome(width: width, background: ground.code) }
        // A ramp, a mesh or a translucent fill: painted over the whole bar —
        // its frame's cells too — as `.background(_:)` paints a view's.
        let padded = bar.replacingLines(bar.lines.map { $0.padToVisibleWidth(width) })
        return BackgroundModifier(style: painted)._modify(
            buffer: padded, context: barContext(edge, width: width, rows: padded.height, style: style, context: context),
            owner: _ToolbarBarRow.self)
    }

    /// What ``toolbarBuffer(_:chrome:width:isModal:drawn:context:)`` draws a
    /// toolbar from.
    struct BarDrawing {
        /// The bar.
        let edge: WindowChromeState.Edge
        /// Its rows as this walk declared them
        /// (``barRows(_:chrome:width:context:)``).
        let rows: [BarRow]
        /// The rows of content last frame reserved for it.
        let contentRows: Int
        /// How many of those the frame shows (`itemRowsShown`).
        let itemRows: Int
        /// The tooltip's lines, drawn above the bottom bar's items.
        var tooltip: [String] = []
        /// What it is drawn on.
        let ground: BarGround
        /// Whether its first row carries the customization of the window's
        /// customizable toolbars: its context menu and panel.
        var hostsCustomization = false
    }

    /// What a bar is drawn on this walk (``WindowChromeState/fill(_:)``).
    struct BarGround {
        /// The colour the fades inside the bar resolve against.
        let surface: Color
        /// The background escape of the bar's bare cells and of the rows it
        /// holds blank; empty for none, the page's own showing through.
        let code: String
        /// A style that is no single opaque colour — a ramp, a mesh, a
        /// translucent fill — painted over the bar instead of ``code``.
        let style: AnyShapeStyle?
    }

    /// What the bar at `edge` is drawn on: the palette's surface for it, a
    /// `.toolbarBackground(_:for:)` style, or — its fill declared hidden — the
    /// page's own background.
    func barGround(_ edge: WindowChromeState.Edge, chrome: WindowChromeState, context: RenderContext) -> BarGround {
        let palette = context.environment.palette
        switch chrome.fill(.edge(edge)) {
        case .palette:
            let surface = edge == .bottom ? palette.statusBarBackground : palette.appHeaderBackground
            let backgrounds = RenderBackgroundCodes(palette: palette)
            return BarGround(
                surface: surface, code: edge == .bottom ? backgrounds.statusBar : backgrounds.appHeader, style: nil)
        case .hidden:
            return BarGround(surface: palette.background, code: "", style: nil)
        case .style(let style):
            let paint = style.paint(in: context.environment)
            let representative = paint.representative.resolve(with: palette)
            let code = ANSIRenderer.backgroundCode(for: representative.opaqueSpelling)
            if case .color = paint, representative.isOpaque {
                return BarGround(surface: representative, code: code, style: nil)
            }
            return BarGround(surface: representative, code: code, style: style)
        }
    }

    /// Keeps the `@State` of the items a walk declared but did not draw — not
    /// in `drawn`: those of a bar `.toolbarVisibility(.hidden, for:)` hides,
    /// of a bar declared on a frame laid out with no rows for it — the frame
    /// before a bar is adopted, whether it is new or coming back — of a bar
    /// row the terminal is too short to show, and a keyboard item with no
    /// typing to be beside.
    ///
    /// An item's state is kept at the identity it was declared at, and state
    /// whose view did not render is collected at the end of the pass, so
    /// hiding a bar and showing it again reset every item in it — a counter
    /// went back to 0, a field was blank — and the adoption frame of a bar
    /// coming back did the same on its own. The declaration says the items
    /// are still there; ``StateStorage/retainSubtree(_:)`` says it to the
    /// state, as a collapsed `DisclosureGroup` does for its content. Per walk,
    /// so an item that stops being declared is collected the pass after.
    func retainUndrawnItems(_ chrome: WindowChromeState, drawn: Set<ViewIdentity>, context: RenderContext) {
        guard let storage = context.stateStorage else { return }
        for edge in WindowChromeState.Edge.allCases {
            for entry in chrome.declaredEntries(for: edge) where !drawn.contains(entry.identity) {
                storage.markActive(entry.identity)
                storage.retainSubtree(entry.identity)
            }
        }
    }

    /// The focus section the toolbar at `edge` puts its items in.
    static func toolbarSectionID(_ edge: WindowChromeState.Edge) -> String {
        "window-toolbar-\(edge)"
    }

    /// The tooltip's rows, styled as the line of key hints styles them.
    private func tooltipRows(_ lines: [String], width: Int, context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(
            StatusBar(style: .compact, tooltipLines: lines),
            context: RenderContext(availableWidth: width, availableHeight: lines.count, environment: context.environment))
    }

    /// The context a toolbar's row is drawn in: the bar's content width, its
    /// rows, and an identity of its own under the window's — the bar's own
    /// row's, or for `row` past the first, the top bar's accessory bar's.
    func barContext(
        _ edge: WindowChromeState.Edge, row: Int = 0, width: Int, rows: Int, style: ChromeStyle,
        context: RenderContext
    ) -> RenderContext {
        var barContext = context.withChildIdentity(
            type: _ToolbarBarRow.self, index: edge == .bottom ? 1 : row == 0 ? 0 : row + 1)
        barContext.availableWidth = style.barContentWidth(width)
        barContext.availableHeight = rows
        barContext.hasExplicitWidth = true
        barContext.hasExplicitHeight = false
        return barContext
    }

    /// How many rows ``framed(_:style:ruleAbove:width:context:)`` draws above
    /// the bar's content: a box's top wall, or the rule of a bar ruled above.
    static func framedRowsAbove(style: ChromeStyle, ruleAbove: Bool) -> Int {
        switch style {
        case .bordered: 1
        case .rule: ruleAbove ? 1 : 0
        case .compact: 0
        }
    }

    /// `row` framed in `style`: boxed with a column of air inside each wall,
    /// ruled on the content's side (`ruleAbove` for a bar below the page), or
    /// bare.
    private func framed(
        _ row: FrameBuffer, style: ChromeStyle, ruleAbove: Bool, width: Int, context: RenderContext
    ) -> FrameBuffer {
        let inner = style.barContentWidth(width)
        let padded =
            style == .bordered
            ? row.replacingLines(
                row.lines.map { " " + $0.padToVisibleWidth(inner) + " " }, overlayShiftX: 1)
            : row
        let frameContext = RenderContext(
            availableWidth: width, availableHeight: style.barHeight(contentRows: row.height),
            environment: context.environment)
        return TUIView.renderToBuffer(
            _ChromeBarFrame(contentBuffer: padded, style: style, ruleAbove: ruleAbove), context: frameContext)
    }
}
