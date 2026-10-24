//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelTypePopUp.swift
//
//  A file panel's file-type pop-up: macOS's "Enable:" pop-up of an open
//  panel's accessory, which narrows the files it takes to one of the types
//  or widens them to all, and a save panel's "Format:" pop-up, which says
//  which of the types to save as.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitPickers

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// One choice of a file panel's type pop-up.
enum FileTypeChoice: Hashable {
    /// Every type the caller allows, together: the panel as asked for.
    case supported
    /// One of them.
    case type(UTType)
    /// Every file, whatever its type: the caller's filter set aside.
    case allFiles

    /// The files an open panel takes under this choice: `nil` for the
    /// caller's own types, empty for every file (``FileChoiceRule/fileTypes``).
    var fileTypes: [UTType]? {
        switch self {
        case .supported: nil
        case .type(let type): [type]
        case .allFiles: []
        }
    }
}

extension FilePanelRequest {
    /// What the panel's type pop-up offers, or `nil` where the panel shows
    /// none: an open panel's lists the types together (where there are
    /// several), each of them, and All Files; a save panel's, each of the
    /// types it saves as. Shown where there is more than one type, unless the
    /// app says otherwise (`fileDialogContentTypePicker(_:)`); never where
    /// there is nothing to filter — a panel that takes every type, or no file
    /// at all (a mover's, or one choosing a folder to save into).
    var typeChoices: [FileTypeChoice]? {
        let types: [UTType]
        switch purpose {
        case .open:
            guard rule.choosesFiles else { return nil }
            types = rule.allowedContentTypes
        case .save(let contentTypes):
            types = contentTypes
        }
        guard !types.isEmpty else { return nil }
        switch contentTypePicker {
        case .hidden: return nil
        case .automatic: guard types.count > 1 else { return nil }
        case .visible: break
        }
        if saveContentTypes != nil { return types.map(FileTypeChoice.type) }
        return (types.count > 1 ? [.supported] : []) + types.map(FileTypeChoice.type) + [.allFiles]
    }

    /// The choice an open panel's pop-up starts on: the types together, or
    /// the one type, which is the same thing.
    var initialTypeChoice: FileTypeChoice {
        let types = rule.allowedContentTypes
        return types.count == 1 ? .type(types[0]) : .supported
    }
}

/// The pop-up: a menu ``Picker``, "Show:" to open and "Format:" to save, with
/// All Files after a rule of its own.
struct FilePanelTypePopUp: View {
    /// What it offers.
    let choices: [FileTypeChoice]

    /// What is chosen.
    let selection: Binding<FileTypeChoice>

    /// Whether the panel saves, which makes it the Format pop-up.
    let saves: Bool

    var body: some View {
        let label = LocalizationService.shared.string(
            for: saves ? LocalizationKey.FilePanel.typeFormat : LocalizationKey.FilePanel.typeShow)
        Picker(label, selection: selection) {
            ForEach(choices.filter { $0 != .allFiles }, id: \.self) { choice in
                Text(verbatim: Self.title(of: choice)).tag(choice)
            }
            if choices.contains(.allFiles) {
                Divider()
                Text(verbatim: Self.title(of: .allFiles)).tag(FileTypeChoice.allFiles)
            }
        }
        .pickerStyle(.menu)
    }

    /// A choice's words: All Supported Files, All Files, or the type's own
    /// description, its first letter raised for a menu ("Text", "PDF
    /// document"), else its identifier.
    static func title(of choice: FileTypeChoice) -> String {
        switch choice {
        case .supported:
            return LocalizationService.shared.string(for: LocalizationKey.FilePanel.typeSupported)
        case .allFiles:
            return LocalizationService.shared.string(for: LocalizationKey.FilePanel.typeAllFiles)
        case .type(let type):
            guard let description = type.localizedDescription, let first = description.first else {
                return type.identifier
            }
            return first.uppercased() + description.dropFirst()
        }
    }
}
