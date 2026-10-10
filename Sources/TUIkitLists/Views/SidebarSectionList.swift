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

    /// The section's rows, by their places: what the list's `row` draws and
    /// its selection names.
    package var rows: [Int]

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitTabs makes these.
    package init(id: Int, header: AnyView?, actions: AnyView?, rows: [Int]) {
        self.id = id
        self.header = header
        self.actions = actions
        self.rows = rows
    }
}

/// A `.sidebar` `List` of sections, each under its header with its actions,
/// its rows drawn by `row` from their places: the list a `.sidebarAdaptable`
/// tab view (TUIkitTabs) lists its tabs in.
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

    /// Draws the row at a place.
    let row: (Int) -> Row

    package init(sections: [_SidebarSection], selection: Binding<Int?>, row: @escaping (Int) -> Row) {
        self.sections = sections
        self.selection = selection
        self.row = row
    }

    package var body: some View {
        List(selection: selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows, id: \.self) { index in
                        row(index)
                    }
                } header: {
                    section.header ?? AnyView(EmptyView())
                }
                .sectionActions { section.actions }
            }
        }
        // A sidebar list: no border, and a `Label` row's icon in the list
        // item tint, as a macOS sidebar draws it.
        .listStyle(.sidebar)
    }
}
