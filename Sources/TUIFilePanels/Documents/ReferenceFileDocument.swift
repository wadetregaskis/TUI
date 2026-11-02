//  🖥️ TUI — A Terminal UI framework for Swift
//  ReferenceFileDocument.swift
//
//  SwiftUI's `ReferenceFileDocument`: a document that is an object.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

#if canImport(Combine)
    import Combine

    /// What a ``ReferenceFileDocument`` refines: Combine's `ObservableObject`,
    /// as SwiftUI's does, where Combine exists, so that a SwiftUI document with
    /// `@Published` properties compiles as written. `ObservableObject` asks a
    /// class for nothing, so an `@Observable` document conforms as it stands.
    public typealias _ReferenceFileDocumentObject = ObservableObject
#else
    /// What a ``ReferenceFileDocument`` refines: any class, where Combine does
    /// not exist, and so nor does `ObservableObject`. There, a document is
    /// `@Observable`.
    public typealias _ReferenceFileDocumentObject = AnyObject
#endif

/// A type that you use to serialize reference type documents to and from file.
///
/// SwiftUI's protocol. `DocumentGroup` shows one object for the life of the
/// document. To save it, it takes a ``snapshot(contentType:)`` on the main actor
/// and writes that off the main actor, so the object can go on changing during
/// a slow write.
///
/// TUI watches a document that is `@Observable`, on every platform: a
/// `DocumentGroup` knows it has unsaved changes when something
/// ``snapshot(contentType:)`` reads has changed. Where Combine exists it also
/// watches `objectWillChange`, so a SwiftUI document with `@Published` properties
/// redraws and counts as edited. SwiftUI's own rule, that a change counts only
/// once registered with the undo manager, is not needed: registering one does
/// no harm.
///
/// ```swift
/// @Observable
/// final class Sketch: ReferenceFileDocument, @unchecked Sendable {
///     static var readableContentTypes: [UTType] { [.plainText] }
///     var text = ""
///
///     init() {}
///
///     init(configuration: ReadConfiguration) throws {
///         text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
///     }
///
///     func snapshot(contentType: UTType) throws -> String { text }
///
///     func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
///         FileWrapper(regularFileWithContents: Data(snapshot.utf8))
///     }
/// }
/// ```
@preconcurrency
public protocol ReferenceFileDocument: _ReferenceFileDocumentObject, Sendable {
    /// The type of a value that represents the document's stored state.
    associatedtype Snapshot

    /// The file and data types that the document reads from.
    static var readableContentTypes: [UTType] { get }

    /// The file types that the document supports saving or exporting to.
    ///
    /// By default, the ``readableContentTypes``.
    static var writableContentTypes: [UTType] { get }

    /// Creates a document and initializes it with the contents of a file.
    ///
    /// TUI calls it off the main actor.
    ///
    /// - Parameter configuration: Information about the file that you
    ///   read document data from.
    init(configuration: ReadConfiguration) throws

    /// The configuration for reading document contents.
    typealias ReadConfiguration = FileDocumentReadConfiguration

    /// Creates a snapshot that represents the current state of the document.
    ///
    /// TUI calls it on the main actor before each save, and once after each to
    /// see what it reads, which is what it watches for edits.
    ///
    /// - Parameter contentType: The content type being saved.
    /// - Returns: A value the document's state can be written from.
    func snapshot(contentType: UTType) throws -> Snapshot

    /// Serializes a document snapshot to a file wrapper.
    ///
    /// TUI calls it off the main actor.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot of the document to save.
    ///   - configuration: Information about a file that already exists for
    ///     the document, if any.
    /// - Returns: The destination to serialize the document contents to.
    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper

    /// The configuration for writing document contents.
    typealias WriteConfiguration = FileDocumentWriteConfiguration
}

extension ReferenceFileDocument {
    /// The file types that the document supports saving or exporting to:
    /// by default, the types it reads.
    public static var writableContentTypes: [UTType] { readableContentTypes }
}

extension FileDocumentRead {
    /// The document at `url`, read as `type`, off the main actor.
    @concurrent
    package static func read<D: ReferenceFileDocument>(
        _: D.Type = D.self, from url: URL, as type: UTType
    ) async throws -> D {
        try D(configuration: FileDocumentReadConfiguration(contentType: type, file: FileWrapper(url: url, options: .immediate)))
    }
}

extension FileDocumentWrite {
    /// `document`'s snapshot, taken on the main actor, serialized as `type` and
    /// written to `url` off it, atomically, replacing what is there.
    ///
    /// - Parameter existing: Where the document's current file is, for its
    ///   ``FileDocumentWriteConfiguration/existingFile``: `nil` for a file
    ///   being made somewhere new.
    @MainActor
    package static func write<D: ReferenceFileDocument>(
        _ document: D, as type: UTType, to url: URL, existing: URL? = nil
    ) async -> Result<URL, any Error> {
        do {
            let snapshot = try document.snapshot(contentType: type)
            return await write(snapshot: snapshot, of: document, as: type, to: url, existing: existing)
        } catch {
            return .failure(error)
        }
    }

    /// `snapshot` serialized by `document` as `type` and written to `url`, off
    /// the main actor.
    @concurrent
    private static func write<D: ReferenceFileDocument>(
        snapshot: sending D.Snapshot, of document: D, as type: UTType, to url: URL, existing: URL?
    ) async -> Result<URL, any Error> {
        do {
            let wrapper = try document.fileWrapper(
                snapshot: snapshot,
                configuration: FileDocumentWriteConfiguration(
                    contentType: type, existingFile: existing.flatMap { try? FileWrapper(url: $0) }))
            try wrapper.write(to: url, options: .atomic, originalContentsURL: existing)
            return .success(url)
        } catch {
            return .failure(error)
        }
    }
}
