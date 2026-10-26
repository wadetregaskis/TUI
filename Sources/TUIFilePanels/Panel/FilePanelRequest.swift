//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelRequest.swift
//
//  What a file panel is asked for, and how it ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// What a presented file panel is asked for: the modifiers that present one
/// (`fileImporter`, …) each fill one in from their arguments and the
/// environment's customizations.
struct FilePanelRequest {
    /// What the user is choosing.
    enum Purpose: Equatable {
        /// Existing items to open: one, or as many as the user selects.
        case open(allowsMultipleSelection: Bool)
        /// A name, in a folder, to save a file of one of these types under.
        case save(contentTypes: [UTType])
    }

    /// What the user is choosing.
    var purpose: Purpose

    /// What the user may choose among a folder's items.
    var rule: FileChoiceRule

    /// The panel's title.
    var title: String

    /// The confirmation button's label.
    var confirmationLabel: String

    /// A line the panel shows above its folder (`fileDialogMessage(_:)`).
    var message: String?

    /// The name a save panel offers.
    var defaultFilename: String?

    /// The label of a save panel's name field (`fileExporterFilenameLabel(_:)`).
    var filenameLabel: String?

    /// The folder the panel opens on.
    var startDirectory: URL

    /// Whether the panel opens with the hidden items listed.
    var showsHiddenFiles = false

    /// Whether a symbolic link chosen is handed back as the item it leads to
    /// (`fileDialogImportsUnresolvedAliases(_:)` says otherwise).
    var resolvesSymbolicLinks = true

    /// Whether the panel shows its file-type pop-up: where it has more than
    /// one type, unless `fileDialogContentTypePicker(_:)` says otherwise
    /// (``typeChoices``).
    var contentTypePicker: Visibility = .automatic

    /// Whether the panel says it browses another machine than the user's
    /// (`fileDialogRemoteNotice(_:)`, ``FilePanelSession/notice(_:)``).
    var remoteNotice: Visibility = .automatic

    /// The key the panel's view mode is kept under in the app's storage:
    /// app-wide, or a `fileDialogCustomizationID(_:)`'s own
    /// (``FilePanelViewMode/storageKey(for:)``).
    var viewModeKey = FilePanelViewMode.storageKey(for: nil)

    /// The folder `~` stands for: the user's home folder, which `~` goes to
    /// and the path bar abbreviates. A test names a folder of its own.
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    /// Whether more than one item may be chosen.
    var allowsMultipleSelection: Bool {
        switch purpose {
        case .open(let multiple): multiple
        case .save: false
        }
    }

    /// The types a save panel saves as, or `nil` for a panel that opens.
    var saveContentTypes: [UTType]? {
        if case .save(let types) = purpose { return types }
        return nil
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
    /// The user chose these items.
    case chose([URL], FilePanelEnding)
    /// The user dismissed the panel without choosing.
    case cancelled(FilePanelEnding)

    /// Where the panel was when it ended.
    var ending: FilePanelEnding {
        switch self {
        case .chose(_, let ending), .cancelled(let ending): ending
        }
    }
}

/// Where a panel was when it ended: what `fileDialogCustomizationID(_:)`
/// keeps, and the folder the next presentation opens on.
struct FilePanelEnding: Equatable {
    /// The folder the panel was showing.
    var directory: URL
    /// Whether it was listing hidden files.
    var showsHiddenFiles: Bool
}
