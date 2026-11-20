//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelCommands+Windows.swift
//
//  Where Windows keeps the folders a file panel's Go chords go to.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import WinSDK

extension FilePanelCommand {
    /// The folder Windows keeps for this command, by its known folder
    /// (`SHGetKnownFolderPath`): the Desktop, Downloads and Documents wherever
    /// the user or OneDrive moved them, and for Applications the Program Files
    /// folder; `nil` for the other commands, and where Windows answers none.
    ///
    /// A folder moved is common: with OneDrive's backup on, the Desktop is
    /// `OneDrive\Desktop`, and the profile's own `Desktop` does not exist (the
    /// VM this was measured on, 2026-11-20). Windows may also name a folder
    /// that is not there (the same VM's Documents, `OneDrive\Documents`), so
    /// ``place(home:)`` takes this only where it exists.
    var windowsKnownFolder: URL? {
        var id: KNOWNFOLDERID
        switch self {
        case .desktop: id = FOLDERID_Desktop
        case .downloads: id = FOLDERID_Downloads
        case .documents: id = FOLDERID_Documents
        case .applications: id = FOLDERID_ProgramFiles
        default: return nil
        }
        var path: PWSTR?
        let result = unsafe SHGetKnownFolderPath(&id, 0, nil, &path)
        defer { unsafe CoTaskMemFree(path) }
        guard result == S_OK, let path = unsafe path else { return nil }
        return URL(fileURLWithPath: unsafe String(decodingCString: path, as: UTF16.self), isDirectory: true)
    }
}

#endif
