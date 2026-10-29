//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanel+Helpers.swift
//
//  A file panel's pure helpers — the room between its parts, the folder on
//  the way down, what its request decides, the keys its status bar names —
//  apart from the panel's state, which `FilePanel.swift` keeps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension FilePanel {
    /// The folder in `folder` on the way to `deeper`, spelled as the folder's
    /// rows spell their URLs (`DirectoryListing`); `nil` where `deeper` is not
    /// inside `folder`.
    static func folder(in folder: URL, toward deeper: URL) -> URL? {
        let base = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        guard deeper.path.hasPrefix(base),
            let component = deeper.path.dropFirst(base.count).split(separator: "/").first
        else { return nil }
        return folder.appendingPathComponent(String(component))
    }

    /// The blank rows between the panel's parts — the message, the name
    /// field, the path and the folder: none at the small control sizes, as
    /// dense as a terminal panel can be; one at `.regular` and `.large`, to
    /// set the parts apart as a macOS panel's margins do; two at
    /// `.extraLarge`. None, whatever the size, where the vertical size class
    /// is compact: a short terminal keeps its rows for the folder.
    static func spacing(controlSize: ControlSize, verticalSizeClass: UserInterfaceSizeClass?) -> Int {
        if verticalSizeClass == .compact { return 0 }
        switch controlSize {
        case .mini, .small: return 0
        case .regular, .large: return 1
        case .extraLarge: return 2
        }
    }

    /// Whether the panel makes folders: a save panel, or one that chooses a
    /// folder (a mover's destination, an importer of folders), as a macOS
    /// save panel does and an open panel does not by default.
    var createsFolders: Bool {
        request.saveContentTypes != nil || request.rule.choosesFolders
    }

    /// The one folder of `selected`, when it is one folder that cannot be
    /// chosen: the confirmation button opens it.
    func openableSelection(_ selected: [FileEntry]) -> URL? {
        guard selected.count == 1, let entry = selected.first, entry.isFolder, !entry.isChoosable else { return nil }
        return entry.url
    }

    /// The URL the caller is handed for `entry`.
    func chosenURL(_ entry: FileEntry) -> URL {
        entry.chosenURL(resolvingLinks: request.resolvesSymbolicLinks)
    }

    /// The keys the panel adds to the status bar, beside the sheet's own
    /// Escape item, which presses the Cancel button
    /// (`StatusBarState.keepPresentationItem`): to the enclosing folder in
    /// the view `viewMode` shows, home, the go-to field, and New Folder where
    /// the panel `createsFolders`.
    @StatusBarItemBuilder
    static func statusItems(viewMode: FilePanelViewMode, createsFolders: Bool) -> [any StatusBarItemProtocol] {
        StatusBarItem(
            shortcut: viewMode == .list ? Shortcut.backspace : Shortcut.arrowLeft,
            label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusEnclosingFolder))
        StatusBarItem(
            shortcut: "~",
            label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusHome))
        StatusBarItem(
            shortcut: "/",
            label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusGoTo))
        if createsFolders {
            StatusBarItem(
                shortcut: "+",
                label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusNewFolder))
        }
    }
}
