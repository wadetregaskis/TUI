//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AutomaticSidebarToggle.swift
//
//  The sidebar button the window's top bar shows by default, as SwiftUI's
//  toolbar does on macOS.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension WindowChromeState {
    /// The items of the toolbar at `edge` as the bar draws them: those the
    /// page declared and, at the front of the top bar, the window's sidebar
    /// button (``automaticSidebarToggle``) where it has one.
    @MainActor
    func barEntries(for edge: Edge) -> [ToolbarEntry] {
        let entries = toolbarEntries(for: edge)
        guard edge == .top, !entries.isEmpty else { return entries }
        return [automaticSidebarToggle, automaticToggle(.content, kind: .contentColumnToggle)].compactMap { $0 }
            + entries
    }

    /// The sidebar button the top bar shows by default, at its leading edge:
    /// for the window's split view — the first drawn
    /// (``panelToggle(_:)``) — as SwiftUI's macOS toolbar shows one for its
    /// window's.
    ///
    /// Only in a bar the page already has: a bar is three rows of the
    /// terminal's, which one button does not earn, and the ◀ and ▶ the split
    /// draws itself already do its job. None where the split's toggle was
    /// removed (`.toolbar(removing: .sidebarToggle)`), which takes this with
    /// the rest, nor where the page placed a ``DefaultToolbarItem`` of kind
    /// ``ToolbarDefaultItemKind/sidebarToggle`` for the same split itself, in
    /// either bar.
    @MainActor
    private var automaticSidebarToggle: ToolbarEntry? { automaticToggle(.sidebar, kind: .sidebarToggle) }

    /// The button the top bar shows by default for `panel` of the window's
    /// split view — the sidebar's, and beside it a three-column split's
    /// content column's (``ToolbarDefaultItemKind/contentColumnToggle``) — unless
    /// the page placed one of `kind` for the same split itself.
    @MainActor
    private func automaticToggle(_ panel: PanelToggle.Panel, kind: ToolbarDefaultItemKind.Kind) -> ToolbarEntry? {
        guard let offer = panelToggleOffer(panel) else { return nil }
        let placed = (declaredEntries(for: .top) + declaredEntries(for: .bottom)).contains { entry in
            guard entry.defaultKind == kind else { return false }
            switch entry.environment.panelToggleScope(panel) {
            case .window: return true
            case .split(let toggle): return toggle?.owner == offer.toggle.owner
            }
        }
        guard !placed else { return nil }
        var environment = offer.environment
        switch panel {
        case .sidebar: environment.sidebarToggleScope = .split(offer.toggle)
        case .content: environment.contentColumnToggleScope = .split(offer.toggle)
        case .inspector: environment.inspectorToggleScope = .split(offer.toggle)
        }
        return ToolbarEntry(
            placement: .navigation, view: AnyView(_PanelToggleButton(panel: panel, label: nil)), environment: environment,
            identity: offer.itemIdentity, defaultKind: kind)
    }
}
