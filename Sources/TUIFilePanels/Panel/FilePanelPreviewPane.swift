//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelPreviewPane.swift
//
//  The list view's preview pane, behind a splitter after the table, as
//  Finder's list view has one (View ▸ Show Preview), and whether a panel
//  shows it: the owner asked for it on 2026-10-28.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// Whether a file panel shows its preview — the list view's pane, the column
/// view's column — kept in the app's storage beside the view mode
/// (``storageKey(for:)``), so the next panel opens as the last was left.
///
/// Until the user opens or closes it (⇧⌘P, or the Preview button beside the
/// view switcher), it is ``automatic``: open where the panel has room for it
/// and for a list that stays comfortable (``opensByDefault(inWidth:)``), and
/// closed where it has not, as the preview would take the list's columns.
enum FilePanelPreviewVisibility: String, CaseIterable, Sendable {
    /// Open where the panel is wide enough (``opensByDefault(inWidth:)``).
    case automatic
    /// Open, as the user left it.
    case shown
    /// Closed, as the user left it.
    case hidden

    /// The key the choice is kept under, as the view mode's is
    /// (``FilePanelViewMode/storageKey(for:)``): `TUIFilePanels.preview` for
    /// every panel of the app, or `TUIFilePanels.<id>.preview` for one with
    /// the customization identifier `id`.
    static func storageKey(for id: String?) -> String {
        id.map { "TUIFilePanels.\($0).preview" } ?? "TUIFilePanels.preview"
    }

    /// Whether the preview shows in a panel whose folder is `width` cells wide.
    @MainActor func isShown(inWidth width: Int) -> Bool {
        switch self {
        case .automatic: Self.opensByDefault(inWidth: width)
        case .shown: true
        case .hidden: false
        }
    }

    /// The fewest cells the list keeps beside an open pane while the panel
    /// chooses: the name and the Size and Date Modified columns at their
    /// widths (``FilePanelColumns/width(showing:)``). Kind may give way, as
    /// it does first in a narrow panel; the other two are what a row is
    /// compared by.
    @MainActor static var comfortableListWidth: Int { FilePanelColumns.width(showing: 2) }

    /// Whether the preview opens by default in a folder `width` cells wide:
    /// where the comfortable list, the splitter's rule and the narrowest pane
    /// (a column's, ``FilePanelColumnView/minimumColumnWidth``) all fit — 82
    /// cells, which a page sheet's 96 columns have room for and an 80-column
    /// terminal has not.
    @MainActor static func opensByDefault(inWidth width: Int) -> Bool {
        width >= comfortableListWidth + 1 + FilePanelColumnView.minimumColumnWidth
    }

    /// The pane's starting width in a folder `width` cells wide: the column
    /// view's preview width (a third, ``FilePanelColumnView/previewWidth(in:)``)
    /// where that leaves the list comfortable, else what does, and never
    /// narrower than a column.
    @MainActor static func paneWidth(in width: Int) -> Int {
        max(
            FilePanelColumnView.minimumColumnWidth,
            min(FilePanelColumnView.previewWidth(in: width), width - 1 - comfortableListWidth))
    }
}

/// The list view's preview pane: the item selected, alone, previewed as the
/// column view previews a file (``FilePanelPreview``) — a folder too, by its
/// name, kind and date, as Finder's pane shows one — or a short "No
/// Selection" while there is no one item to show.
struct FilePanelPreviewPane: View {
    /// The one item selected, or `nil`.
    let entry: FileEntry?

    var body: some View {
        if let entry {
            FilePanelPreview(entry: entry)
        } else {
            Text(localized: LocalizationKey.FilePanel.noSelection)
                .foregroundStyle(.palette.foregroundTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The button beside the view switcher that opens and closes the preview: a
/// toggle in the button style, pressed in while the preview shows, as
/// Finder's toolbar has a Preview button. A Tab stop, as the switcher is,
/// whose Space toggles it; ⇧⌘P does the same from anywhere in the panel.
struct FilePanelPreviewToggle: View {
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(LocalizationService.shared.string(for: LocalizationKey.FilePanel.preview), isOn: isOn)
            .toggleStyle(.button)
    }
}
