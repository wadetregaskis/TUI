//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeHost+Toolbars.swift
//
//  The window's two toolbars, as the chrome host draws them.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _WindowChromeHost {
    /// The rows a toolbar of `contentRows` rows takes in `style`, or 0 for
    /// none.
    static func toolbarHeight(contentRows: Int, style: ChromeStyle) -> Int {
        contentRows > 0 ? style.barHeight(contentRows: contentRows) : 0
    }

    /// The rows of content the items declared for the toolbar at `edge` want:
    /// the tallest item's height at the bar's width — and the title's, in the
    /// top bar's title slot — measured, so finding it registers nothing; 0 when
    /// nothing is placed there, or what is placed draws nothing (a `StatusBar()`
    /// with no items to show).
    func toolbarContentRows(
        _ edge: WindowChromeState.Edge, chrome: WindowChromeState, width: Int, context: RenderContext
    ) -> Int {
        let entries = chrome.toolbarEntries(for: edge)
        guard !entries.isEmpty else { return 0 }
        let style = chrome.style(edge)
        let measureContext = barContext(edge, width: width, rows: context.availableHeight, style: style, context: context)
        let proposal = ProposedSize(width: style.barContentWidth(width), height: nil)
        let tallest = entries.map {
            measureChild(_ToolbarEntryView(entry: $0), proposal: proposal, context: measureContext).height
        }.max() ?? 0
        let (title, subtitle) = titleSlot(edge, chrome: chrome)
        let titleRows = title.isEmpty || entries.contains { $0.placement.region == .principal } ? 0 : subtitle.isEmpty ? 1 : 2
        return max(0, tallest, titleRows)
    }

    /// What the title slot of the bar at `edge` shows: the window's title and
    /// subtitle in the top bar, nothing in the bottom one.
    private func titleSlot(_ edge: WindowChromeState.Edge, chrome: WindowChromeState) -> (String, String) {
        edge == .top ? (chrome.title, chrome.subtitle) : ("", "")
    }

    /// The toolbar at `edge`, framed and on its own background, in the
    /// `contentRows` it reserved — with the bottom bar's tooltip rows above
    /// its items — or `nil` when there is nothing to draw.
    ///
    /// Its items are in an optional focus section of their own, after the
    /// page's, so Tab reaches them last and they never take the initial focus.
    /// While a modal holds the input the bar is drawn inert — on throwaway
    /// focus and key channels — and the top bar's hit regions go; the bottom
    /// bar keeps its regions, so a click on the line of key hints still does
    /// what the key would, as a press of the key does behind a modal.
    func toolbarBuffer(
        _ edge: WindowChromeState.Edge, chrome: WindowChromeState, contentRows: Int,
        tooltip: [String] = [], width: Int, isModal: Bool, context: RenderContext
    ) -> FrameBuffer? {
        // A bar the page no longer declares anything for keeps its reserved
        // rows for the frame, blank: the caller pads them with its background.
        let entries = chrome.toolbarEntries(for: edge)
        let drawsItems = contentRows > 0 && !entries.isEmpty
        guard drawsItems || !tooltip.isEmpty else { return nil }
        let style = chrome.style(edge)
        var row = FrameBuffer()
        if !tooltip.isEmpty {
            row.appendVertically(tooltipRows(tooltip, width: style.barContentWidth(width), context: context))
        }
        if drawsItems {
            var barContext = barContext(edge, width: width, rows: contentRows, style: style, context: context)
            let sectionID = Self.toolbarSectionID(edge)
            if isModal {
                barContext = barContext.isolatedForBackground()
            } else if let focusManager = context.environment.focusManager {
                focusManager.markSectionFocusOptional(id: sectionID)
                focusManager.registerSection(id: sectionID)
            }
            barContext.environment.activeFocusSectionID = sectionID
            let (title, subtitle) = titleSlot(edge, chrome: chrome)
            row.appendVertically(
                TUIkit.renderToBuffer(
                    _ToolbarBarRow(entries: entries, title: title, subtitle: subtitle), context: barContext
                ).fittedAsChrome(toRows: contentRows, width: style.barContentWidth(width), background: ""))
        }
        let palette = context.environment.palette
        let backgrounds = RenderBackgroundCodes(palette: palette)
        let background = edge == .bottom ? backgrounds.statusBar : backgrounds.appHeader
        var bar = framed(row, style: style, ruleAbove: edge == .bottom, width: width, context: context)
            .resolvingOpacity(
                surface: edge == .bottom ? palette.statusBarBackground : palette.appHeaderBackground,
                palette: palette)
            .groundedAsChrome(width: width, background: background)
        if isModal, edge == .top { bar.hitTestRegions = [] }
        return bar
    }

    /// The focus section the toolbar at `edge` puts its items in.
    static func toolbarSectionID(_ edge: WindowChromeState.Edge) -> String {
        "window-toolbar-\(edge)"
    }

    /// The tooltip's rows, styled as the line of key hints styles them.
    private func tooltipRows(_ lines: [String], width: Int, context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(
            StatusBar(style: .compact, tooltipLines: lines),
            context: RenderContext(availableWidth: width, availableHeight: lines.count, environment: context.environment))
    }

    /// The context a toolbar's row is drawn in: the bar's content width, its
    /// rows, and an identity of its own under the window's.
    private func barContext(
        _ edge: WindowChromeState.Edge, width: Int, rows: Int, style: ChromeStyle, context: RenderContext
    ) -> RenderContext {
        var barContext = context.withChildIdentity(type: _ToolbarBarRow.self, index: edge == .bottom ? 1 : 0)
        barContext.availableWidth = style.barContentWidth(width)
        barContext.availableHeight = rows
        barContext.hasExplicitWidth = true
        barContext.hasExplicitHeight = false
        return barContext
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
        return TUIkit.renderToBuffer(
            _ChromeBarFrame(contentBuffer: padded, style: style, ruleAbove: ruleAbove), context: frameContext)
    }
}
