//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseCombinedView.swift
//
//  The perf cases' presentations — a sheet, an item sheet, a popover, an
//  alert — and the navigation split view: compositions of other compositions
//  that `CaseCompositionView` hands here from one arm. Every string shown is
//  written here verbatim: a case adds nothing to a translation table
//  (B-PERFCASE-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// A presentation over a composition, or a navigation split view of several.
struct CaseCombinedView: View {
    let composition: CaseComposition
    let rows: CaseRows

    var body: some View {
        switch composition {
        case .sheet(let page, let presented):
            AnyView(
                part(page).sheet(isPresented: isPresented) { part(presented) })
        case .sheetItem(let page, let presented):
            AnyView(
                part(page).sheet(item: Binding(get: { rows.item }, set: { rows.item = $0 })) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "item \(item.id)")
                        part(presented)
                    }
                })
        case .popover(let page, let presented):
            AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: CasePage.title).popover(isPresented: isPresented) { part(presented) }
                    part(page)
                })
        case .alert(let page):
            AnyView(
                part(page).alert(Self.alert[0], isPresented: isPresented) {
                    Button(Self.alert[1], role: .destructive) {}
                    Button(Self.alert[2], role: .cancel) {}
                } message: {
                    Text(verbatim: Self.alert[3])
                })
        case .navigationSplit(let parts) where parts.count == 3:
            AnyView(NavigationSplitView { part(parts[0]) } content: { part(parts[1]) } detail: { part(parts[2]) })
        case .navigationSplit(let parts):
            AnyView(NavigationSplitView { part(parts[0]) } detail: { part(parts[1]) })
        default:
            AnyView(Text(verbatim: "\(composition) is not a presentation or a split"))
        }
    }

    private func part(_ composition: CaseComposition) -> CaseCompositionView {
        CaseCompositionView(composition: composition, rows: rows)
    }

    private var isPresented: Binding<Bool> { Binding(get: { rows.presented }, set: { rows.presented = $0 }) }

    /// The alert's title, its buttons and its message, as strings rather than
    /// literals: a literal is a localization key, and a case adds none.
    static let alert = ["Delete the rows?", "Delete", "Cancel", "This cannot be undone."]
}
