//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuSections.swift
//
//  A `Section` in a menu, drawn as SwiftUI's macOS menus draw one: set off
//  from the items around it by separators, under its header as a title that
//  is no item.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// A menu's items, each `Section` among them drawn as a menu draws one —
/// what every TUIkit menu (a pop-up `Menu`, a `.contextMenu`, an inline
/// `Menu`) stacks as its rows.
///
/// Measured on macOS 15.8 (`D1S/probe2/menuapp`, SwiftUI's own `NSMenu` for a
/// `CommandMenu` read back): each section is wrapped in separators and its
/// header is a section-header item — a small grey title, never highlighted or
/// chosen — followed by its items; a menu shows no separator at its top or
/// bottom and never two in a row. Outside a menu a section is its parts with no
/// styling (decisions B16); a menu is the container that styles them, as a
/// `List` is.
///
/// So the items are resolved keeping their sections whole, and each is spliced
/// back as rows: a separator, its header drawn under the section-header chrome
/// role (bold and dimmed, a `List` section header's look), its content's and
/// footer's views, and a separator. A separator at either end, or beside
/// another (one the app wrote too), is dropped. Every other item is handed
/// over as it was, at the identity it had.
struct _MenuSectionedItems<Items: View>: View, Renderable, Layoutable, ChildViewProvider {
    let items: Items

    var body: Never {
        fatalError("_MenuSectionedItems renders via Renderable")
    }

    /// One row of the menu before separators are collapsed.
    private enum Entry {
        /// An item, a section's header or one of its views.
        case row(ChildView)
        /// A separator the app wrote: kept, and taken as one for a section.
        case divider(ChildView)
        /// A separator a section adds, before or after it — drawn only where it
        /// separates two rows that are not already separated.
        case sectionEdge(ChildView)
    }

    func childViews(context: RenderContext) -> [ChildView] {
        // The type says whether a section can be among the items at all, so
        // a menu of buttons resolves them exactly as it always did.
        guard mayHandOver(.section, in: items) else { return resolveChildViews(from: items, context: context) }
        let children = resolveChildViews(from: items, context: context.keepingSectionsWhole())
        guard children.contains(where: { sectionParts(of: $0) != nil }) else { return children }
        var entries: [Entry] = []
        for child in children {
            guard let parts = sectionParts(of: child) else {
                entries.append(throughWrappers(child.wrappedView, as: Divider.self) != nil ? .divider(child) : .row(child))
                continue
            }
            let scope = pinnedScope(of: child, in: context)
            let scoped = parts.scopedParts(in: scope)
            entries.append(.sectionEdge(separator(MenuSectionSeparatorIndex.before, in: scope)))
            if !(parts.header is EmptyView) {
                entries.append(
                    .row(ChildView(_MenuSectionHeader(header: parts.header)).pinningIdentity(to: scoped[0].scope.identity)))
            }
            for part in scoped.dropFirst() {
                entries += resolveChildViews(from: part.view, context: part.scope).map {
                    .row($0.pinningIdentity(to: part.scope.identity))
                }
            }
            entries.append(.sectionEdge(separator(MenuSectionSeparatorIndex.after, in: scope)))
        }
        return Self.collapsed(entries)
    }

    /// A separator a section adds, at an identity of its own under the
    /// section's.
    private func separator(_ index: Int, in scope: RenderContext) -> ChildView {
        ChildView(Divider(), childIndex: index).pinningIdentity(to: scope.identity)
    }

    /// The rows, with the separators a section adds kept only where they
    /// separate: none at the menu's top or bottom, none beside another.
    private static func collapsed(_ entries: [Entry]) -> [ChildView] {
        var rows: [ChildView] = []
        var lastWasSeparator = true
        var pendingEdge: ChildView?
        for entry in entries {
            switch entry {
            case .sectionEdge(let edge):
                if !lastWasSeparator, pendingEdge == nil { pendingEdge = edge }
            case .divider(let divider):
                pendingEdge = nil
                rows.append(divider)
                lastWasSeparator = true
            case .row(let row):
                if let edge = pendingEdge { rows.append(edge) }
                pendingEdge = nil
                rows.append(row)
                lastWasSeparator = false
            }
        }
        return rows
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderStackedVertically(childViews(context: context), context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureStackedVertically(childViews(context: context), proposal: proposal, context: context)
    }
}

/// Child indices for the separators a menu section adds, under the section's
/// own scope: after its parts' (0, 1 and 2, ``SectionParts/scopedParts(in:)``).
private enum MenuSectionSeparatorIndex {
    static let before = 3
    static let after = 4
}

/// A menu section's header: drawn under the section-header chrome role, as a
/// `List`'s is, and never a row the menu highlights or chooses — it publishes
/// no row, as a `Divider` does not.
private struct _MenuSectionHeader: View, Renderable, Layoutable {
    let header: any View

    var body: Never {
        fatalError("_MenuSectionHeader renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(header, context: sectionChromeContext(context, .sectionHeader))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(header, proposal: proposal, context: sectionChromeContext(context, .sectionHeader))
    }
}
