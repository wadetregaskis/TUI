//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+SectionActions.swift
//
//  Which section the pointer is over, for the sections whose actions show
//  while the pointer is over them (owner ruling B78-VISIBILITY).
//
//  Created by Wade Tregaskis
//  License: MIT

extension ItemListHandler {
    /// Notes the section with actions under the pointer at `contentY` (in
    /// ``visibleRowBands``' space), or none for `nil` — the pointer gone.
    ///
    /// - Returns: Whether that changed which section it is, and so whose
    ///   actions are drawn: the only move worth a frame.
    func hoverSections(atContentY contentY: Int?) -> Bool {
        var section: Int?
        if let contentY,
            let band = visibleRowBands.first(where: { contentY >= $0.yStart && contentY < $0.yStart + $0.height })
        {
            section = sectionActionSpans.first { $0.contains(band.rowIndex) }?.lowerBound
        }
        guard section != hoveredSectionRow else { return false }
        hoveredSectionRow = section
        return true
    }
}
