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

    /// The style the toolbar at `edge` frames itself in: the scene's chrome
    /// style for the header above, the status bar's below.
    func toolbarStyle(_ edge: WindowChromeState.Edge, context: RenderContext) -> ChromeStyle {
        let style = edge == .bottom ? context.environment.statusBar?.style : context.environment.appHeader?.style
        return style ?? .bordered
    }

    /// The rows of content the items declared for the toolbar at `edge` want:
    /// their row's height at the bar's width, measured — so finding it
    /// registers nothing — or 0 when nothing is placed there.
    func toolbarContentRows(
        _ edge: WindowChromeState.Edge, chrome: WindowChromeState, width: Int, context: RenderContext
    ) -> Int {
        let entries = chrome.toolbarEntries(for: edge)
        guard !entries.isEmpty else { return 0 }
        let style = toolbarStyle(edge, context: context)
        let row = _ToolbarBarRow(entries: entries, title: chrome.title, subtitle: chrome.subtitle)
        let size = measureChild(
            row, proposal: ProposedSize(width: style.barContentWidth(width), height: nil),
            context: barContext(edge, width: width, rows: context.availableHeight, style: style, context: context))
        return max(0, size.height)
    }

    /// The toolbar at `edge`, framed and on its own background, in the
    /// `contentRows` it reserved — or `nil` when it reserved none.
    ///
    /// Its items are in an optional focus section of their own, after the
    /// page's, so Tab reaches them last and they never take the initial focus.
    /// While a modal holds the input the bar is drawn inert — on throwaway
    /// focus and key channels — and the top bar's hit regions go, as the app
    /// header's do; the bottom bar keeps its regions, as the status bar does.
    func toolbarBuffer(
        _ edge: WindowChromeState.Edge, chrome: WindowChromeState, contentRows: Int, width: Int,
        isModal: Bool, context: RenderContext
    ) -> FrameBuffer? {
        guard contentRows > 0 else { return nil }
        let style = toolbarStyle(edge, context: context)
        var barContext = barContext(edge, width: width, rows: contentRows, style: style, context: context)
        let sectionID = Self.toolbarSectionID(edge)
        if isModal {
            barContext = barContext.isolatedForBackground()
        } else if let focusManager = context.environment.focusManager {
            focusManager.markSectionFocusOptional(id: sectionID)
            focusManager.registerSection(id: sectionID)
        }
        barContext.environment.activeFocusSectionID = sectionID
        let row = TUIkit.renderToBuffer(
            _ToolbarBarRow(entries: chrome.toolbarEntries(for: edge), title: chrome.title, subtitle: chrome.subtitle),
            context: barContext)
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
            AppHeader(contentBuffer: padded, style: style, ruleAbove: ruleAbove), context: frameContext)
    }
}
