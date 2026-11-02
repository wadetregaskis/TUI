//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentGroup.swift
//
//  SwiftUI's `DocumentGroup`: a scene that opens, edits and saves a document,
//  one at a time, in the terminal's one window.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIApp
import TUICommands
import TUIFilePanels
import TUIFoundation

/// A scene that enables support for opening, creating, and saving documents.
///
/// SwiftUI's scene, with its signatures, for a ``FileDocument`` (a value) or a
/// ``ReferenceFileDocument`` (an object), as an editor or a viewer:
///
/// ```swift
/// @main
/// struct TextEdit: App {
///     var body: some Scene {
///         DocumentGroup(newDocument: TextFile()) { file in
///             TextEditor(text: file.$document.text)
///         }
///     }
/// }
/// ```
///
/// ## One document at a time
///
/// macOS gives each document a window. A terminal has one surface, so here one
/// document is open at a time, and **opening or creating another replaces it**,
/// after asking about its unsaved changes as closing its window would: Save,
/// Don't Save or Cancel. Don't Save loses them, Cancel keeps everything as it
/// was, and Save saves first, through the save panel if the document has no
/// file yet; cancelling that panel, or a save that fails, keeps it too. An open
/// that fails keeps the document as well. So does the panel: the question comes
/// once a file has been chosen, not before.
///
/// An app declares one document type this way. With a second `DocumentGroup`,
/// only the first window scene opens at launch, and nothing reaches the second.
///
/// ## At launch
///
/// An editor opens with a new document, from `newDocument`, as a document app
/// with no iCloud does on macOS. A viewer cannot make one, so it opens the open
/// panel, and cancelling that leaves a page saying no document is open, with a
/// button that asks again. TUI never parses an app's arguments: an app that
/// takes a path on its command line opens it with
/// ``EnvironmentValues/openDocument``.
///
/// ## Commands
///
/// The File menu has what a document app's has, through the panels
/// (`fileImporter`'s and `fileExporter`'s):
///
/// | Item | Key | Where |
/// |---|---|---|
/// | New | ⌘N | editors |
/// | Open… | ⌘O | editors and viewers |
/// | Save | ⌘S | editors: the save panel, for a document with no file or a read-only one |
/// | Save As… | ⇧⌘S | editors |
///
/// The keys answer to Control where the terminal does not report ⌘
/// (``EnvironmentValues/commandKey``), and in a terminal's legacy encoding ⇧⌘S
/// is ⌘S, which leaves Save As… to the menu bar's keys. `.commands` on the scene
/// adds to or replaces these (`CommandGroup(replacing: .newItem)`) as it does in
/// SwiftUI, and `.commandsRemoved()` takes them away.
///
/// ## Unsaved changes
///
/// A value document counts as edited once something writes through
/// ``FileDocumentConfiguration/document``. A reference document does as
/// ``ReferenceFileDocument`` says. The window's title reads *name* — Edited
/// meanwhile, and quitting, or the content's own `dismiss()`, asks the same
/// question as replacing it does.
///
/// There is no autosave: macOS can undo an autosave through a document's
/// versions, and a terminal app has none. File has no Close, which would leave
/// a window with nothing in it, nor Duplicate, Rename, Move To or Revert To,
/// which are AppKit's document browser. An edit undone leaves the document
/// edited.
///
/// Available everywhere the framework's file panels are; on Linux the
/// `FileWrapper` it reads and writes through is TUI's.
public struct DocumentGroup<Document, Content: View> {
    /// Makes what holds the document, once, as the window first draws.
    let makeStore: @MainActor @Sendable () -> any DocumentStore

    /// The app's editor or viewer, given the configuration of the store's
    /// document.
    let content: (Any) -> Content?

    /// Whether the document can be changed and saved here.
    let isViewer: Bool
}

// In an extension, so the type is not isolated to the main actor as the
// conformance would make it, which its `nonisolated` initializers, SwiftUI's
// spelling, could not then store a closure in.
extension DocumentGroup: Scene {
    /// The scene: the one window, with its File commands.
    @MainActor public var body: some Scene {
        WindowGroup {
            DocumentWindow(makeStore: makeStore, isViewer: isViewer, content: content)
        }
        .commands {
            DocumentCommands(isViewer: isViewer)
        }
    }
}

// MARK: - FileDocument

extension DocumentGroup where Document: FileDocument {
    /// Creates a document group for creating and editing file documents.
    ///
    /// - Parameters:
    ///   - newDocument: The initial document used when the user creates a new
    ///     document, called once for each.
    ///   - editor: The editing UI for the provided document.
    @preconcurrency
    nonisolated public init(
        newDocument: @autoclosure @escaping @Sendable () -> Document,
        @ViewBuilder editor: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) {
        self.makeStore = { FileDocumentStore(make: newDocument) }
        self.content = { ($0 as? FileDocumentConfiguration<Document>).map(editor) }
        self.isViewer = false
    }

    /// Creates a document group capable of viewing file documents.
    ///
    /// Use this method to create a document group that can view files of a
    /// specific type, whose configuration's `isEditable` is `false` and whose
    /// binding ignores writes. The File menu has only Open….
    ///
    /// - Parameters:
    ///   - documentType: The type of document this scene can view.
    ///   - viewer: The viewing UI for the provided document.
    nonisolated public init(
        viewing documentType: Document.Type,
        @ViewBuilder viewer: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) {
        self.makeStore = { FileDocumentStore<Document>(make: nil) }
        self.content = { ($0 as? FileDocumentConfiguration<Document>).map(viewer) }
        self.isViewer = true
    }
}

// MARK: - ReferenceFileDocument

extension DocumentGroup where Document: ReferenceFileDocument {
    /// Creates a document group for creating and editing reference documents.
    ///
    /// - Parameters:
    ///   - newDocument: The initial document used when the user creates a new
    ///     document, called once for each.
    ///   - editor: The editing UI for the provided document.
    @preconcurrency
    nonisolated public init(
        newDocument: @escaping @Sendable () -> Document,
        @ViewBuilder editor: @escaping (ReferenceFileDocumentConfiguration<Document>) -> Content
    ) {
        self.makeStore = { ReferenceDocumentStore(make: newDocument) }
        self.content = { ($0 as? ReferenceFileDocumentConfiguration<Document>).map(editor) }
        self.isViewer = false
    }

    /// Creates a document group capable of viewing reference documents.
    ///
    /// - Parameters:
    ///   - documentType: The type of document this scene can view.
    ///   - viewer: The viewing UI for the provided document.
    nonisolated public init(
        viewing documentType: Document.Type,
        @ViewBuilder viewer: @escaping (ReferenceFileDocumentConfiguration<Document>) -> Content
    ) {
        self.makeStore = { ReferenceDocumentStore<Document>(make: nil) }
        self.content = { ($0 as? ReferenceFileDocumentConfiguration<Document>).map(viewer) }
        self.isViewer = true
    }
}
