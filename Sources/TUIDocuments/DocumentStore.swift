//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentStore.swift
//
//  What holds a `DocumentGroup`'s document: a value or an object, behind one
//  shape, so the rest of the scene does not care which.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUIFilePanels
import TUIFoundation

#if canImport(Combine)
    import Combine
#endif

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Holds a document, and reads and writes it.
@MainActor
protocol DocumentStore: AnyObject {
    /// The types it opens.
    var readableContentTypes: [UTType] { get }

    /// The types it saves as.
    var writableContentTypes: [UTType] { get }

    /// Whether there is a document: a viewer's has none until one is opened.
    var hasDocument: Bool { get }

    /// Whether it can make a new document: a viewer's cannot.
    var canMakeNew: Bool { get }

    /// Replaces the document with a new one.
    func makeNew()

    /// Replaces the document with the one at `url`, or throws and keeps it.
    func load(from url: URL, as type: UTType) async throws

    /// Writes the document to `url`, where the file at `existing` is its
    /// current one, if it has one.
    func save(to url: URL, as type: UTType, existing: URL?) async -> Result<URL, any Error>

    /// Calls `edited` when the document changes other than through a binding.
    ///
    /// Each call replaces the last, so a change is told of at most once per
    /// call for what ``ReferenceDocumentStore`` learns by observation.
    func watchForEdits(contentType: UTType, _ edited: @escaping @MainActor @Sendable () -> Void)

    /// The configuration the app's editor or viewer is given, or `nil` with no
    /// document, to draw in `session`.
    func configuration(in session: DocumentSession) -> Any?
}

// MARK: - A value

/// Holds a ``FileDocument``, whose edits all come through its binding.
@MainActor
@Observable
final class FileDocumentStore<Document: FileDocument>: DocumentStore {
    /// What makes a new document; `nil` in a viewer.
    @ObservationIgnored private let make: (@Sendable () -> Document)?

    /// The document.
    private(set) var document: Document?

    init(make: (@Sendable () -> Document)?) {
        self.make = make
        self.document = make?()
    }

    var readableContentTypes: [UTType] { Document.readableContentTypes }
    var writableContentTypes: [UTType] { Document.writableContentTypes }
    var hasDocument: Bool { document != nil }
    var canMakeNew: Bool { make != nil }

    func makeNew() {
        if let make { document = make() }
    }

    /// Replaces the document with `document`.
    func replaceDocument(with document: Document) {
        self.document = document
    }

    func load(from url: URL, as type: UTType) async throws {
        document = try await FileDocumentRead.read(Document.self, from: url, as: type)
    }

    func save(to url: URL, as type: UTType, existing: URL?) async -> Result<URL, any Error> {
        guard let document else { return .failure(CocoaError(.fileNoSuchFile)) }
        return await FileDocumentWrite.write(document, as: type, to: url, existing: existing)
    }

    func watchForEdits(contentType: UTType, _ edited: @escaping @MainActor @Sendable () -> Void) {}

    func configuration(in session: DocumentSession) -> Any? {
        guard let drawn = document else { return nil }
        let binding = Binding<Document>(
            get: { self.document ?? drawn },
            set: { value in
                guard session.isEditable else { return }
                self.document = value
                session.noteEdit()
            })
        return FileDocumentConfiguration(document: binding, fileURL: session.fileURL, isEditable: session.isEditable)
    }
}

// MARK: - An object

/// Holds a ``ReferenceFileDocument``, which can change without saying so to
/// anything but what is watching it.
@MainActor
@Observable
final class ReferenceDocumentStore<Document: ReferenceFileDocument>: DocumentStore {
    /// What makes a new document; `nil` in a viewer.
    @ObservationIgnored private let make: (@Sendable () -> Document)?

    /// The document.
    private(set) var document: Document?

    /// Counts the changes `objectWillChange` announced: what a view that drew
    /// the document depends on, since nothing tells Observation about a
    /// `@Published` property.
    private var announcedChanges = 0

    #if canImport(Combine)
        /// The subscription to the document's `objectWillChange`.
        @ObservationIgnored private var announcements: AnyCancellable?
    #endif

    init(make: (@Sendable () -> Document)?) {
        self.make = make
        self.document = make?()
    }

    var readableContentTypes: [UTType] { Document.readableContentTypes }
    var writableContentTypes: [UTType] { Document.writableContentTypes }
    var hasDocument: Bool { document != nil }
    var canMakeNew: Bool { make != nil }

    func makeNew() {
        if let make { document = make() }
    }

    /// Replaces the document with `document`.
    func replaceDocument(with document: Document) {
        self.document = document
    }

    func load(from url: URL, as type: UTType) async throws {
        document = try await FileDocumentRead.read(Document.self, from: url, as: type)
    }

    func save(to url: URL, as type: UTType, existing: URL?) async -> Result<URL, any Error> {
        guard let document else { return .failure(CocoaError(.fileNoSuchFile)) }
        return await FileDocumentWrite.write(document, as: type, to: url, existing: existing)
    }

    /// Watches both ways a document can say it changed. Observation is asked
    /// about what a snapshot reads, the document's stored state, which is both
    /// less than what a view reads and one call, not one per edit: it tells once.
    func watchForEdits(contentType: UTType, _ edited: @escaping @MainActor @Sendable () -> Void) {
        guard let document else { return }
        withObservationTracking {
            _ = try? document.snapshot(contentType: contentType)
        } onChange: {
            Task { @MainActor in edited() }
        }
        #if canImport(Combine)
            announcements = document.objectWillChange.sink { [weak self] _ in
                Task { @MainActor in
                    self?.announcedChanges &+= 1
                    edited()
                }
            }
        #endif
    }

    func configuration(in session: DocumentSession) -> Any? {
        guard let document else { return nil }
        _ = announcedChanges
        let object = ReferenceFileDocumentObject(
            wrappedValue: document,
            write: { write in
                guard session.isEditable else { return }
                write()
                session.noteEdit()
            })
        return ReferenceFileDocumentConfiguration(
            document: object, fileURL: session.fileURL, isEditable: session.isEditable)
    }
}
