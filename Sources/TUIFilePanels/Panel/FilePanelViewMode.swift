//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelViewMode.swift
//
//  How a file panel shows a folder — a list or columns, as Finder's view
//  buttons choose — and the segmented control that chooses.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIPickers

/// How a file panel shows a folder: two of the four views Finder and a macOS
/// panel offer, as a terminal can draw them (decisions B-FP2-6).
///
/// Kept in the app's storage, so a panel opens in the view the last one was
/// left in: app-wide, or under a `fileDialogCustomizationID(_:)` its own, as
/// macOS keeps a panel's "view style" under it (``storageKey(for:)``).
enum FilePanelViewMode: String, CaseIterable, Sendable {
    /// The folder's items in a table, as an outline (``FilePanelListView``).
    case list
    /// A column for each folder on the way to the one shown
    /// (``FilePanelColumnView``).
    case columns

    /// The key the view mode is kept under: `TUIFilePanels.viewMode` for
    /// every panel of the app, or `TUIFilePanels.<id>.viewMode` for one
    /// with the customization identifier `id`.
    static func storageKey(for id: String?) -> String {
        id.map { "TUIFilePanels.\($0).viewMode" } ?? "TUIFilePanels.viewMode"
    }

    /// The mode's name, as its segment shows it.
    var title: String {
        switch self {
        case .list: LocalizationService.shared.string(for: LocalizationKey.FilePanel.viewList)
        case .columns: LocalizationService.shared.string(for: LocalizationKey.FilePanel.viewColumns)
        }
    }
}

/// The view switcher, as Finder's toolbar has one: a segmented ``Picker`` of
/// the view modes, one Tab stop whose ← and → move among them and Space or
/// Return chooses, each segment its own target under the pointer.
struct FilePanelViewModePicker: View {
    let mode: Binding<FilePanelViewMode>

    var body: some View {
        // No label: an empty one reserves nothing, and the segments say
        // what the control is.
        Picker("", selection: mode) {
            ForEach(FilePanelViewMode.allCases, id: \.self) { mode in
                Text(verbatim: mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
