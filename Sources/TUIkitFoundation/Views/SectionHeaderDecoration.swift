//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionHeaderDecoration.swift
//
//  What a list draws around a section's header besides the header: a tab
//  view sidebar's section mover, which the header's fold carries.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Draws around a list section's header — as the list draws it, a collapsible
/// one behind its fold — what the header itself does not: the keys and the drag
/// that move a tab view sidebar's section (TUIkitLists' `_SidebarSectionList`).
///
/// A class, so that one object serves every frame: a list's state.
@MainActor
package protocol SectionHeaderDecorating: AnyObject, Sendable {
    /// `header`, decorated for the section `section` names.
    func decorate(_ header: AnyView, section: Int) -> AnyView
}

/// A ``SectionHeaderDecorating`` and the section it decorates — what a list
/// writes around a section for its header to read
/// (``EnvironmentValues/sectionHeaderDecoration``).
///
/// Compared by the decorator's identity and the section: the decorator is
/// the same object from frame to frame, so the value is comparable and the
/// memos below it stay on, and it changes only where the section does.
package struct SectionHeaderDecoration: Equatable, Sendable {
    /// What draws around the header.
    package let decorator: any SectionHeaderDecorating

    /// The section it is drawn for, in the decorator's own numbering.
    package let section: Int

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitLists makes these.
    package init(decorator: any SectionHeaderDecorating, section: Int) {
        self.decorator = decorator
        self.section = section
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.section == rhs.section && ObjectIdentifier(lhs.decorator) == ObjectIdentifier(rhs.decorator)
    }
}

/// Environment key for ``EnvironmentValues/sectionHeaderDecoration``.
private struct SectionHeaderDecorationKey: EnvironmentKey {
    static let defaultValue: SectionHeaderDecoration? = nil
}

extension EnvironmentValues {
    /// What a list draws around the header of the section this is written on
    /// (``SectionHeaderDecoration``), or `nil` — every section but a tab view
    /// sidebar's that a customization can reorder.
    package var sectionHeaderDecoration: SectionHeaderDecoration? {
        get { self[SectionHeaderDecorationKey.self] }
        set { self[SectionHeaderDecorationKey.self] = newValue }
    }
}
