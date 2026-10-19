//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SidebarSectionList.swift
//
//  A sidebar list of sections, each with its actions, for a list that
//  another module of the package lays out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitView

/// One section of a ``_SidebarSectionList``: consecutive rows under a header,
/// with the section's actions.
package struct _SidebarSection: Identifiable {
    /// The section's place among the sections.
    package let id: Int

    /// The section's header, or `nil` for none.
    package let header: AnyView?

    /// The section's actions (``View/sectionActions(content:)``), or `nil`
    /// for none.
    package let actions: AnyView?

    /// The section's rows: what the list's `row` draws and its selection
    /// names, by their places, with what each draws.
    package var rows: [_SidebarRow]

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitTabs makes these.
    package init(id: Int, header: AnyView?, actions: AnyView?, rows: [_SidebarRow]) {
        self.id = id
        self.header = header
        self.actions = actions
        self.rows = rows
    }
}

/// One row of a ``_SidebarSection``: its place, and what it draws.
///
/// The list's loop keys its rows by place — a row keeps its `@State` and its
/// focus while what it draws changes — and its row memo by the whole element,
/// so a row is served from the memo only while ``look`` is unchanged. Keyed
/// by its place alone, the memo served a row drawn from data the place does
/// not carry, after that data changed: a tab's old title, or the opener of a
/// context menu the tab no longer has (decisions B-LISTS-2).
package struct _SidebarRow: Equatable {
    /// The row's place: what the list's `row` draws and its selection names.
    package let place: Int

    /// The row's id in the list: its place, in a type no hand-written row's
    /// ordinal casts into, so the sidebar's header and footer rows are never
    /// a selection.
    var id: _SidebarPlace { _SidebarPlace(place: place) }

    /// What the row draws, as far as it can be compared. A part that cannot —
    /// a view of the app's own — is the row's to declare (an unkeyed read), so
    /// the memo does not keep it.
    package let look: AnyHashable

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitTabs makes these.
    package init(place: Int, look: AnyHashable) {
        self.place = place
        self.look = look
    }
}

/// A row's place, as the sidebar list's selection names it (``_SidebarRow/id``).
struct _SidebarPlace: Hashable {
    let place: Int
}

/// A `.sidebar` `List` of sections, each under its header with its actions,
/// its rows drawn by `row` from their places: the list a `.sidebarAdaptable`
/// tab view (TUIkitTabs) lists its tabs in.
///
/// Its header and footer (`tabViewSidebarHeader(content:)`,
/// `tabViewSidebarFooter(content:)`) are its first and last rows, so they
/// scroll with the tabs, as SwiftUI's do. Neither is a row the selection can
/// name — the rows are named by ``_SidebarPlace``, which their ordinals do
/// not cast into — so the cursor steps over them, as it steps over a section
/// header, and a control in either is a Tab stop as in any row.
///
/// A section with a header folds, as a macOS sidebar's does: its header is a
/// disclosure the keyboard and a click toggle, and a folded section's rows
/// leave the list until it is opened again. What is folded is the sidebar's
/// own state, kept by the section's place.
///
/// Built here rather than by the tab view: ``View/sectionActions(content:)``'s
/// `some View` names `_SectionActionsView`, internal to this module, so in
/// another module that type stays opaque, and the list's content asked the
/// runtime for it on every evaluation (CONTRIBUTING.md, "Crossing a module
/// boundary"). Here it is concrete, and the list's initializer and style are
/// this module's own calls.
package struct _SidebarSectionList<Row: View>: View {
    /// The sections, in order.
    let sections: [_SidebarSection]

    /// The selected row's place, or `nil` for none.
    let selection: Binding<Int?>

    /// The first row, above the sections, or `nil` for none.
    let header: AnyView?

    /// The last row, below the sections, or `nil` for none.
    let footer: AnyView?

    /// Draws the row at a place.
    let row: (Int) -> Row

    /// The places of the sections the user has folded.
    @State private var folded: Set<Int> = []

    package init(
        sections: [_SidebarSection], header: AnyView? = nil, footer: AnyView? = nil, selection: Binding<Int?>,
        row: @escaping (Int) -> Row
    ) {
        self.sections = sections
        self.header = header
        self.footer = footer
        self.selection = selection
        self.row = row
    }

    package var body: some View {
        let selection = self.selection
        let placeSelection = Binding<_SidebarPlace?>(
            get: { selection.wrappedValue.map(_SidebarPlace.init) }, set: { selection.wrappedValue = $0?.place })
        return List(selection: placeSelection) {
            if let header { header }
            ForEach(sections) { section in
                Section(
                    header: section.header ?? AnyView(EmptyView()),
                    content: ForEach(section.rows, id: \.id) { row in self.row(row.place) },
                    footer: EmptyView(),
                    // A run of tabs outside any section has no header to fold.
                    isExpanded: section.header == nil ? nil : expansion(of: section.id)
                )
                .sectionActions { section.actions }
            }
            if let footer { footer }
        }
        // A sidebar list: no border, and a `Label` row's icon in the list
        // item tint, as a macOS sidebar draws it.
        .listStyle(.sidebar)
    }

    /// Whether the section at `place` is open, as its fold reads and writes it.
    private func expansion(of place: Int) -> Binding<Bool> {
        let folded = $folded
        return Binding(
            get: { !folded.wrappedValue.contains(place) },
            set: { isOpen in
                if isOpen {
                    folded.wrappedValue.remove(place)
                } else {
                    folded.wrappedValue.insert(place)
                }
            })
    }
}
