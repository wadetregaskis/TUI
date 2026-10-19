//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowChromeHost+BarRows.swift
//
//  A toolbar's items laid out in rows: the bar's own row and, under the top
//  bar's, a row for each accessory bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension _WindowChromeHost {
    /// One row of a toolbar's items: the bar's own, or one of the top bar's
    /// accessory bars (`ToolbarItemPlacement.accessoryBar(id:)`).
    struct BarRow {
        /// The row's items, in declaration order.
        let entries: [WindowChromeState.ToolbarEntry]
        /// The rows of the bar it takes: its tallest item's height, and in the
        /// top bar's own row the title's.
        let rows: Int
        /// The title its title slot shows; empty for none.
        let title: String
        /// The subtitle under the title.
        let subtitle: String
        /// The accessory bar it is, or `nil` for the bar's own row.
        let accessory: AccessoryBarID?
    }

    /// The rows of the toolbar at `edge` this walk: its own row — the items
    /// placed in it, and in the top bar the title — then, in the top bar, a
    /// row for each accessory bar, in the order the page first placed
    /// something in each. A row with nothing to draw (a `StatusBar()` with no
    /// items to show) takes none; a bar with no rows is not drawn.
    ///
    /// The heights are measured, so finding them registers nothing.
    func barRows(
        _ edge: WindowChromeState.Edge, chrome: WindowChromeState, width: Int, context: RenderContext
    ) -> [BarRow] {
        let entries = chrome.barEntries(for: edge, focus: context.environment.focusManager)
        guard !entries.isEmpty else { return [] }
        let style = chrome.style(edge)
        let measureContext = barContext(edge, width: width, rows: context.availableHeight, style: style, context: context)
        let proposal = ProposedSize(width: style.barContentWidth(width), height: nil)
        // A title menu is the title, counted with it.
        func tallest(_ entries: [WindowChromeState.ToolbarEntry]) -> Int {
            entries.filter { !$0.isTitleMenu }.map {
                measureChild(_ToolbarEntryView(entry: $0), proposal: proposal, context: measureContext).height
            }.max() ?? 0
        }

        var rows: [BarRow] = []
        let own = entries.filter { $0.placement.accessoryBar == nil }
        if !own.isEmpty {
            let (title, subtitle) = titleSlot(edge, chrome: chrome)
            let titleGiven = !chrome.titleBesidePrincipal && own.contains { $0.placement.region == .principal }
            let titleRows = title.isEmpty || titleGiven ? 0 : subtitle.isEmpty ? 1 : 2
            let height = max(tallest(own), titleRows)
            if height > 0 {
                rows.append(BarRow(entries: own, rows: height, title: title, subtitle: subtitle, accessory: nil))
            }
        }
        var accessories: [AccessoryBarID] = []
        for case let id? in entries.map(\.placement.accessoryBar) where !accessories.contains(id) {
            accessories.append(id)
        }
        for id in accessories {
            let bar = entries.filter { $0.placement.accessoryBar == id }
            let height = tallest(bar)
            if height > 0 { rows.append(BarRow(entries: bar, rows: height, title: "", subtitle: "", accessory: id)) }
        }
        return rows
    }

    /// `row` — an accessory bar's, drawn — on the fill a bar modifier stated
    /// for that accessory bar, if any: it is otherwise drawn on the top bar's.
    func accessoryGround(
        _ accessory: AccessoryBarID?, of row: FrameBuffer, chrome: WindowChromeState, width: Int,
        context: RenderContext
    ) -> FrameBuffer {
        guard let accessory, chrome.statesFill(.accessory(accessory)) else { return row }
        let palette = context.environment.palette
        let padded = row.replacingLines(row.lines.map { $0.padToVisibleWidth(width) })
        switch chrome.fill(.accessory(accessory)) {
        case .palette:
            return row
        case .hidden:
            // No fill of its own: the page's background, which the top bar's
            // grounding, painted after, leaves alone.
            return padded.paintedOver(background: RenderBackgroundCodes(palette: palette).content)
        case .style(let style):
            return BackgroundModifier(style: style)._modify(buffer: padded, context: context, owner: BarRow.self)
        }
    }
}
