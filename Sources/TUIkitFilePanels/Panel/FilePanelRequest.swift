//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelRequest.swift
//
//  What a file panel is asked for, and how it ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

/// What a presented file panel is asked for: the modifiers that present one
/// (`fileImporter`, …) each fill one in from their arguments and the
/// environment's customizations.
struct FilePanelRequest {
    /// What the user is choosing.
    enum Purpose: Equatable {
        /// Existing items to open: one, or as many as the user selects.
        case open(allowsMultipleSelection: Bool)
    }

    /// What the user is choosing.
    var purpose: Purpose

    /// What the user may choose among a folder's items.
    var rule: FileChoiceRule

    /// The panel's title.
    var title: String

    /// The confirmation button's label.
    var confirmationLabel: String

    /// The folder the panel opens on.
    var startDirectory: URL

    /// Whether the panel opens with the hidden items listed.
    var showsHiddenFiles = false

    /// Whether a symbolic link chosen is handed back as the item it leads to
    /// (`fileDialogImportsUnresolvedAliases(_:)` says otherwise).
    var resolvesSymbolicLinks = true

    /// The folder `~` stands for: the user's home folder, which `~` goes to
    /// and the path bar abbreviates. A test names a folder of its own.
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    /// Whether more than one item may be chosen.
    var allowsMultipleSelection: Bool {
        switch purpose {
        case .open(let multiple): multiple
        }
    }

    /// The folder a panel opens on when nothing names one: the process's
    /// working directory. A terminal app is started from a shell, in the
    /// folder its user was working in, which is the likeliest place for the
    /// file they want (macOS's panels open on the folder used last instead,
    /// which a panel here does too, once it has been used).
    static var defaultStartDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}

/// How a presented file panel ended.
enum FilePanelOutcome: Equatable {
    /// The user chose these items, in the folder the panel was showing.
    case chose([URL], in: URL)
    /// The user dismissed the panel without choosing.
    case cancelled
}
