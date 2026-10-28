//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelNewFolder.swift
//
//  New Folder: a save panel, or one that chooses a folder, makes a folder in
//  the folder it shows and opens it, as a macOS save panel's New Folder
//  button does (`NSSavePanel.canCreateDirectories`, on by default; an open
//  panel's is off). The owner asked for it on 2026-10-28 (NEW-FOLDER).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation
import TUIPresentation
import TUITextInput

/// `content` with the sheet that asks a new folder's name, as the Mac's New
/// Folder sheet does — "Name of new folder:", a field holding "untitled
/// folder" (numbered past any the folder holds already), Cancel and Create —
/// a sheet, not an alert, since an alert holds only buttons. Create, or Return
/// in the field, makes the folder in the folder `browser` shows and opens it;
/// a folder that cannot be made says why in an alert.
struct FilePanelNewFolderPrompt<Content: View>: View {
    let content: Content
    @Binding var isPresented: Bool
    let browser: FileBrowser

    /// The name in the sheet's field.
    @State private var name = ""
    /// The name of a folder that could not be made, and why.
    @State private var failure: (name: String, reason: String)?

    var body: some View {
        content
            .sheet(isPresented: $isPresented) { prompt }
            .alert(
                String(
                    format: LocalizationService.shared.string(for: LocalizationKey.FilePanel.newFolderFailed),
                    failure?.name ?? ""),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button(localized: LocalizationKey.Button.ok) {}
            } message: {
                Text(failure?.reason ?? "")
            }
            .onChange(of: isPresented) { _, shown in
                guard shown else { return }
                name = Self.availableName(
                    LocalizationService.shared.string(for: LocalizationKey.FilePanel.untitledFolder),
                    in: browser.directory)
            }
    }

    /// The sheet: the name field under its label, Cancel and Create.
    private var prompt: some View {
        let label = LocalizationService.shared.string(for: LocalizationKey.FilePanel.newFolderName)
        return Dialog(
            title: LocalizationService.shared.string(for: LocalizationKey.FilePanel.newFolder),
            footerAlignment: .trailing
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                TextField(label, text: $name)
                    .frame(minWidth: 30)
                    .onSubmit { create() }
            }
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

    /// Makes the folder named in the field and opens it, closing the sheet;
    /// an empty name makes nothing, as the Mac's Create is disabled for one.
    private func create() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        isPresented = false
        do {
            let folder = try Self.makeFolder(named: trimmed, in: browser.directory)
            // The folder shown lists the new one once read again.
            browser.reload()
            browser.open(folder)
        } catch {
            failure = (trimmed, error.localizedDescription)
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
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: false)
        return made
    }
}
