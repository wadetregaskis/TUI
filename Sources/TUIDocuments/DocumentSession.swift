//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentSession.swift
//
//  One document open in a `DocumentGroup`'s window: where its file is, whether
//  it has unsaved changes, and what New, Open, Save and quitting do about them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUIFilePanels
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The state of a ``DocumentGroup``'s window, and every way it changes.
///
/// A reference, kept by the window across frames, and published to the menu bar
/// as a focused value: the commands are drawn outside the window's content.
@MainActor
@Observable
final class DocumentSession {
    /// What holds the document.
    @ObservationIgnored let store: any DocumentStore

    /// Whether the document can be changed and saved here at all.
    @ObservationIgnored let isViewer: Bool

    /// The document's file; `nil` for one never saved.
    private(set) var fileURL: URL?

    /// The type it was read as or last saved as, or a new one's.
    private(set) var contentType: UTType

    /// The folder of the last file opened or saved, which a new document's save
    /// panel opens on too.
    private(set) var lastFolder: URL?

    /// Whether it has changes not in its file.
    private(set) var isEdited = false

    /// Whether its file can be written; so `true` with no file.
    private var isFileWritable = true

    /// Counts the documents the window has shown, so that what the app drew of
    /// one, its `@State` above all, is not kept for the next.
    private(set) var documentNumber = 0

    /// Whether the open panel is up.
    var isOpenPanelShown = false

    /// Whether the save panel is up.
    var isSavePanelShown = false

    /// Whether the question about unsaved changes is up.
    var isAskingToSave = false

    /// What went wrong, while an alert says so.
    var failure: DocumentFailure?

    /// What waits on the answer to the question about unsaved changes.
    @ObservationIgnored private var waitingOnAnswer: PendingWork?

    /// What waits on the save panel, and then on its save.
    @ObservationIgnored private var waitingOnSavePanel: PendingWork?

    /// Counts the edits, so a save knows whether any came during it.
    @ObservationIgnored private var editCount = 0

    /// Counts the watches begun, so a change told of late, by a watch since
    /// replaced, is known for one a snapshot since has already seen.
    @ObservationIgnored private var watchNumber = 0

    /// Something to do once unsaved changes are dealt with, and what to do if
    /// they are not.
    struct PendingWork {
        let run: () -> Void
        var abandoned: () -> Void = {}
    }

    /// A viewer opens with the open panel up, having nothing to show.
    init(store: any DocumentStore, isViewer: Bool) {
        self.store = store
        self.isViewer = isViewer
        self.contentType = Self.firstType(of: store)
        self.isOpenPanelShown = !store.hasDocument
        watch()
    }

    private static func firstType(of store: any DocumentStore) -> UTType {
        store.writableContentTypes.first ?? store.readableContentTypes.first ?? .data
    }

    // MARK: What the window draws

    /// Whether the document can be changed: not in a viewer, nor for a file
    /// that cannot be written.
    var isEditable: Bool { !isViewer && isFileWritable }

    /// The document's name: its file's, or the word for one with none.
    var name: String {
        fileURL?.lastPathComponent ?? LocalizationService.shared.string(for: LocalizationKey.FilePanel.untitled)
    }

    /// The window's title: nothing with no document, and *name* — Edited
    /// while it has unsaved changes, as a macOS document window's reads.
    var title: String {
        guard store.hasDocument else { return "" }
        guard isEdited else { return name }
        return "\(name) — \(LocalizationService.shared.string(for: LocalizationKey.Document.edited))"
    }

    /// What ``EnvironmentValues/documentConfiguration`` says.
    var configuration: DocumentConfiguration? {
        store.hasDocument ? DocumentConfiguration(isEditable: isEditable, fileURL: fileURL) : nil
    }

    /// The name the save panel offers.
    var nameToSaveAs: String {
        guard let fileURL else { return name }
        return fileURL.lastPathComponent
    }

    // MARK: Edits

    /// The document changed.
    func noteEdit() {
        editCount += 1
        if !isEdited { isEdited = true }
    }

    /// Watches the document for changes that do not come through a binding.
    private func watch() {
        watchNumber += 1
        let number = watchNumber
        store.watchForEdits(contentType: contentType) { [weak self] in
            guard let self, self.watchNumber == number else { return }
            self.noteEdit()
        }
    }

    // MARK: The commands

    /// File ▸ New: a new document from the group's `newDocument`.
    func new() {
        guard store.canMakeNew else { return }
        new { self.store.makeNew() }
    }

    /// `newDocument(contentType:)`: as ``new()``, saving as `type`.
    func new(contentType type: UTType) {
        guard store.canMakeNew else { return }
        new(contentType: type) { self.store.makeNew() }
    }

    /// Replaces the document with what `make` puts in the store, once its
    /// unsaved changes are dealt with.
    func new(contentType type: UTType? = nil, make: @escaping @MainActor () -> Void) {
        let type = type ?? Self.firstType(of: store)
        pastChanges(
            PendingWork(run: { [self] in
                make()
                show(fileURL: nil, contentType: type)
            }))
    }

    /// File ▸ Open…: the panel, and the question after it, if one is chosen.
    func open() {
        isOpenPanelShown = true
    }

    /// Replaces the document with the one the open panel chose, saying so with
    /// an alert if it cannot be read.
    func open(chosen url: URL) {
        Task {
            do {
                try await open(url)
            } catch is CancellationError {
                // The person kept the document: the answer to their own question.
            } catch {
                failure = DocumentFailure(
                    title: Self.failureTitle(LocalizationKey.Document.openFailed, url.lastPathComponent),
                    message: error.localizedDescription)
            }
        }
    }

    /// Replaces the document with the one at `url`, once its unsaved changes
    /// are dealt with, or throws and keeps it.
    func open(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            pastChanges(
                PendingWork(
                    run: { [self] in
                        Task {
                            do {
                                let type = FileDocumentRead.contentType(of: url, among: store.readableContentTypes)
                                try await store.load(from: url, as: type)
                                show(fileURL: url, contentType: type)
                                done.resume()
                            } catch {
                                done.resume(throwing: error)
                            }
                        }
                    },
                    abandoned: { done.resume(throwing: CancellationError()) }))
        }
    }

    /// File ▸ Save: over its file if it has one that can be written, and by way
    /// of the panel if not.
    func save() {
        save(then: nil)
    }

    /// File ▸ Save As…: by way of the panel.
    func saveAs() {
        guard store.hasDocument else { return }
        // What waited on the panel no longer will: tell it, as every other
        // replacement does, or an `openDocument(at:)` behind it never returns.
        waitingOnSavePanel?.abandoned()
        waitingOnSavePanel = nil
        isSavePanelShown = true
    }

    private func save(then next: PendingWork?) {
        guard store.hasDocument, !isViewer else {
            next?.abandoned()
            return
        }
        if let fileURL, isFileWritable {
            write(to: fileURL, then: next)
        } else {
            // As in `saveAs()`: what waited on the panel before is given up.
            waitingOnSavePanel?.abandoned()
            waitingOnSavePanel = next
            isSavePanelShown = true
        }
    }

    /// The save panel chose `url`.
    func savePanelChose(_ url: URL) {
        let next = waitingOnSavePanel
        waitingOnSavePanel = nil
        write(to: url, then: next)
    }

    /// The save panel went without a choice.
    func savePanelCancelled() {
        let next = waitingOnSavePanel
        waitingOnSavePanel = nil
        next?.abandoned()
    }

    /// Writes the document, keeping it edited if it changed meanwhile, and goes
    /// on to `next` if that worked.
    private func write(to url: URL, then next: PendingWork?) {
        let writable = store.writableContentTypes
        let existing = url == fileURL ? url : nil
        let type =
            existing != nil && writable.contains(contentType)
            ? contentType : FileDocumentRead.contentType(of: url, among: writable)
        // Before the snapshot the save takes: a change after it is not in the
        // file, so the watch must tell of it.
        watch()
        let editsSaved = editCount
        Task {
            switch await store.save(to: url, as: type, existing: existing) {
            case .success:
                fileURL = url
                lastFolder = url.deletingLastPathComponent()
                contentType = type
                isFileWritable = true
                isEdited = editCount != editsSaved
                next?.run()
            case .failure(let error):
                failure = DocumentFailure(
                    title: Self.failureTitle(LocalizationKey.Document.saveFailed, url.lastPathComponent),
                    message: error.localizedDescription)
                next?.abandoned()
            }
        }
    }

    /// Shows the document the store now holds, as `fileURL`'s, unedited.
    private func show(fileURL url: URL?, contentType type: UTType) {
        fileURL = url
        if let url { lastFolder = url.deletingLastPathComponent() }
        contentType = type
        isEdited = false
        isFileWritable = url.map { FileManager.default.isWritableFile(atPath: $0.path) } ?? true
        documentNumber += 1
        watch()
    }

    private static func failureTitle(_ key: LocalizationKey.Document, _ name: String) -> String {
        LocalizedStringKey.substituting([name], into: LocalizationService.shared.string(for: key))
    }

    // MARK: Unsaved changes

    /// Does `work` now, or once the question about unsaved changes is answered.
    ///
    /// A question already up gives way: what it waited on is abandoned.
    func pastChanges(_ work: PendingWork) {
        guard isEdited else {
            work.run()
            return
        }
        waitingOnAnswer?.abandoned()
        waitingOnAnswer = work
        isAskingToSave = true
    }

    /// The question's Save.
    func answerSave() {
        let work = waitingOnAnswer
        waitingOnAnswer = nil
        save(then: work)
    }

    /// The question's Don't Save.
    func answerDontSave() {
        let work = waitingOnAnswer
        waitingOnAnswer = nil
        work?.run()
    }

    /// The question's Cancel.
    func answerCancel() {
        let work = waitingOnAnswer
        waitingOnAnswer = nil
        work?.abandoned()
    }
}

/// An alert's worth of what went wrong.
struct DocumentFailure: Equatable {
    let title: String
    let message: String
}
