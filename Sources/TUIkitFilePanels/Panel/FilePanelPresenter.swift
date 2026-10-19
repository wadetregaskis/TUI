//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelPresenter.swift
//
//  The modifier every file panel is presented through: a sheet holding the
//  panel while the binding is true, and the panel's end turned into the
//  caller's callbacks in SwiftUI's order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitPresentation

/// Presents a ``FilePanel`` in a sheet while `isPresented` is true, and turns
/// how it ends into the caller's callbacks.
///
/// SwiftUI's order: when the user chooses, `isPresented` is set to `false`
/// and then `onChoose` is called; when the panel is dismissed any other way —
/// Cancel, Escape, or the app clearing the binding — `isPresented` is false
/// and `onCancel` is called instead, once, after the sheet has gone.
///
/// Each presentation's request is made when the sheet is presented, with the
/// `fileDialog` customizations the environment holds then
/// (``FileDialogCustomization``). It opens on, in order: the folder kept
/// under its `fileDialogCustomizationID(_:)`, the `fileDialogDefaultDirectory(_:)`,
/// the folder of the last choice made through this view, and the request's
/// own start folder.
struct FilePanelPresenter<Content: View>: View {
    let content: Content
    let isPresented: Binding<Bool>

    /// What the panel is asked for, made when it is presented: a request
    /// changed while the panel is up applies the next time, as SwiftUI's does.
    let request: () -> FilePanelRequest

    /// The user chose these URLs; `isPresented` is already false.
    let onChoose: ([URL]) -> Void

    /// The panel was dismissed without a choice.
    let onCancel: () -> Void

    /// What one presentation has to remember past the frame that ends it: a
    /// reference, since the sheet's dismissal callback reads it after the
    /// choice was made.
    @State private var session = Session()

    /// The locale the panel writes its sizes and dates in.
    @Environment(\.locale) private var locale

    /// What the `fileDialog` modifiers above have set.
    @Environment(\.fileDialogCustomization) private var customization

    /// The store a `fileDialogCustomizationID(_:)` keeps a panel's state in.
    @Environment(\.defaultAppStorage) private var defaultAppStorage

    private final class Session {
        /// Whether this presentation ended in a choice.
        var chose = false
        /// The folder the last choice was made in.
        var lastDirectory: URL?
        /// The request this presentation was made with.
        var current: FilePanelRequest?
    }

    var body: some View {
        content
            .sheet(isPresented: isPresented, onDismiss: dismissed) {
                // Built only while the sheet is presented, so the request is
                // made when it is.
                FilePanel(request: currentRequest(), finish: finish)
                    .presentationSizing(.page)
            }
    }

    /// The request this presentation was made with: made the first time the
    /// sheet's content is built, and kept until it is dismissed.
    private func currentRequest() -> FilePanelRequest {
        if let current = session.current { return current }
        var made = request()
        made.rule.locale = locale
        Self.apply(customization, to: &made)
        if let lastDirectory = session.lastDirectory, customization.defaultDirectory == nil {
            made.startDirectory = lastDirectory
        }
        if let kept = keptState() {
            made.startDirectory = kept.directory
            made.showsHiddenFiles = kept.showsHiddenFiles
        }
        session.current = made
        return made
    }

    /// `customization` applied to `request`: the words, the default folder,
    /// the browsing options, the URL test and how links are handed back.
    static func apply(_ customization: FileDialogCustomization, to request: inout FilePanelRequest) {
        if let message = customization.message { request.message = message }
        if let label = customization.confirmationLabel { request.confirmationLabel = label }
        if let label = customization.filenameLabel { request.filenameLabel = label }
        if let folder = customization.defaultDirectory { request.startDirectory = folder }
        request.showsHiddenFiles = customization.browserOptions.contains(.includeHiddenFiles)
        request.rule.enumeratesPackages = customization.browserOptions.contains(.enumeratePackages)
        request.rule.urlEnabled = customization.urlEnabled?.predicate
        request.resolvesSymbolicLinks = !customization.importsUnresolvedAliases
    }

    private func finish(_ outcome: FilePanelOutcome) {
        keep(outcome.ending)
        switch outcome {
        case .chose(let urls, let ending):
            session.chose = true
            session.lastDirectory = ending.directory
            isPresented.wrappedValue = false
            onChoose(urls)
        case .cancelled:
            isPresented.wrappedValue = false
        }
    }

    /// The sheet has gone: a cancellation, unless the panel chose.
    private func dismissed() {
        let chose = session.chose
        session.chose = false
        session.current = nil
        if !chose { onCancel() }
    }

    // MARK: - fileDialogCustomizationID

    /// The store the panel's state is kept in.
    private var store: any StorageBackend {
        defaultAppStorage?.store ?? StorageDefaults.backend
    }

    /// The keys the state of the panel with identifier `id` is kept under.
    static func storageKeys(_ id: String) -> (directory: String, showsHiddenFiles: String) {
        ("TUIkitFilePanels.\(id).directory", "TUIkitFilePanels.\(id).showsHiddenFiles")
    }

    /// The state kept under this panel's identifier, when it has one and a
    /// folder is kept that still exists.
    private func keptState() -> FilePanelEnding? {
        guard let id = customization.customizationID else { return nil }
        let keys = Self.storageKeys(id)
        guard let path: String = store.entry(forKey: keys.directory, as: String.self).value else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let hidden = store.entry(forKey: keys.showsHiddenFiles, as: Bool.self).value ?? false
        return FilePanelEnding(directory: URL(fileURLWithPath: path, isDirectory: true), showsHiddenFiles: hidden)
    }

    /// Keeps where the panel ended under its identifier, when it has one.
    private func keep(_ ending: FilePanelEnding) {
        guard let id = customization.customizationID else { return }
        let keys = Self.storageKeys(id)
        store.setValue(ending.directory.path, forKey: keys.directory)
        store.setValue(ending.showsHiddenFiles, forKey: keys.showsHiddenFiles)
    }
}
