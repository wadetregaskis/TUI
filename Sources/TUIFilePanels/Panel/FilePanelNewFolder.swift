//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelNewFolder.swift
//
//  New Folder: a save panel, or a mover's, makes a folder in the folder it shows
//  and opens it, as a macOS save panel's New Folder button does
//  (`NSSavePanel.canCreateDirectories`, on by default; an open panel's is off,
//  both measured). The owner asked for it on 2026-10-28 (NEW-FOLDER), and said on
//  2026-11-02 that the open panel shouldn't have one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIPresentation
import TUITextInput

/// `content` with the sheet that asks a new folder's name, as the Mac's New
/// Folder sheet does — "Name of new folder:", a field holding "untitled
/// folder" (numbered past any the folder holds already), all selected so that
/// typing replaces it, Cancel and Create —
/// a sheet, not an alert, since an alert holds only buttons. Create, or Return
/// in the field, makes the folder in the folder `browser` shows and opens it; a
/// folder that cannot be made says why in the sheet, which stays up with the name
/// in its field to change, where an alert over it would only have to be dismissed
/// first.
struct FilePanelNewFolderPrompt<Content: View>: View {
    let content: Content
    @Binding var isPresented: Bool
    let browser: FileBrowser

    /// The name in the sheet's field.
    @State private var name = ""
    /// What of the name is selected: all of it, when it is offered and when it fails.
    @State private var selection: TextSelection?
    /// Why the last name asked for could not be made, until the name changes.
    @State private var failure: String?
    /// Whether the field has the focus: given to it when the sheet opens, and back
    /// to it when a name fails, as a click on Create took it, so that the next thing
    /// typed is the new name.
    @FocusState private var nameHasFocus: Bool

    var body: some View {
        content
            .sheet(isPresented: $isPresented) { prompt }
            .onChange(of: isPresented) { _, shown in
                guard shown else { return }
                failure = nil
                name = Self.availableName(
                    LocalizationService.shared.string(for: LocalizationKey.FilePanel.untitledFolder),
                    in: browser.directory)
                selectName()
            }
    }

    /// The sheet: the name field under its label, why it failed if it did, Cancel
    /// and Create.
    private var prompt: some View {
        let label = LocalizationService.shared.string(for: LocalizationKey.FilePanel.newFolderName)
        return Dialog(
            title: LocalizationService.shared.string(for: LocalizationKey.FilePanel.newFolder),
            footerAlignment: .trailing
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                TextField(label, text: $name, selection: $selection)
                    .frame(minWidth: 30)
                    .focused($nameHasFocus)
                    .onSubmit { create() }
                    .onChange(of: name) { _, _ in failure = nil }
                if let failure {
                    Text(verbatim: failure).foregroundStyle(.palette.warning)
                }
            }
            .defaultFocus($nameHasFocus, true)
        } footer: {
            HStack(spacing: 2) {
                Button(localized: LocalizationKey.Button.cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(localized: LocalizationKey.Button.create) { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    /// The name asked for, without the blanks around it.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Makes the folder named in the field and opens it, closing the sheet; an
    /// empty name makes nothing, as the Mac's Create is disabled for one, and one
    /// that fails leaves the sheet up, saying why.
    private func create() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        do {
            let folder = try Self.makeFolder(named: trimmed, in: browser.directory)
            isPresented = false
            // The folder shown lists the new one once read again.
            browser.reload()
            browser.open(folder)
        } catch {
            failure = Self.failureMessage(error, named: trimmed)
            nameHasFocus = true
            selectName()
        }
    }

    /// Selects the whole of the name.
    private func selectName() {
        selection = TextSelection(range: name.startIndex..<name.endIndex)
    }

    /// Why a folder `name` could not be made, in the app's language: the two
    /// reasons a person can act on, and a name the Finder would refuse, in TUI's own
    /// words, and anything else in the system's, whose language is the process's.
    static func failureMessage(_ error: any Error, named name: String) -> String {
        let service = LocalizationService.shared
        switch (error as? CocoaError)?.code {
        case .fileWriteFileExists:
            return LocalizedStringKey.substituting([name], into: service.string(for: LocalizationKey.FilePanel.newFolderNameTaken))
        case .fileWriteNoPermission, .fileWriteVolumeReadOnly:
            return service.string(for: LocalizationKey.FilePanel.newFolderNoPermission)
        case .fileWriteInvalidFileName:
            return LocalizedStringKey.substituting([name], into: service.string(for: LocalizationKey.FilePanel.newFolderBadName))
        default:
            return LocalizedStringKey.substituting([name], into: service.string(for: LocalizationKey.FilePanel.newFolderFailed))
                + " " + error.localizedDescription
        }
    }

    /// `base`, or the first of "`base` 2", "`base` 3" … that `folder` does not
    /// hold, as the Finder numbers a new folder.
    static func availableName(_ base: String, in folder: URL) -> String {
        let manager = FileManager.default
        func taken(_ name: String) -> Bool { manager.fileExists(atPath: folder.appendingPathComponent(name).path) }
        guard taken(base) else { return base }
        var number = 2
        while taken("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Makes a folder `name` in `folder` and returns it. A name holding a `/`
    /// would make a folder somewhere else, or several, so it is refused as
    /// the Finder refuses it.
    static func makeFolder(named name: String, in folder: URL) throws -> URL {
        guard !name.contains("/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let made = folder.appendingPathComponent(name, isDirectory: true)
        // Asked first, so that a name taken says so wherever this runs, whatever
        // error its Foundation would answer with: a file of that name counts too.
        guard !FileManager.default.fileExists(atPath: made.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: false)
        return made
    }
}
