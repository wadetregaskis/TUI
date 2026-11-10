//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDocument.swift
//
//  SwiftUI's `FileDocument`, and the configurations it reads and writes
//  through: what `DocumentGroup` opens and saves and `fileExporter(document:)`
//  writes. Everywhere: a document is a `FileWrapper`, which is Foundation's on
//  Apple platforms and TUI's elsewhere (FileWrapper+Portable.swift).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// A type that you use to serialize documents to and from file.
///
/// SwiftUI's protocol: a value that `DocumentGroup` reads from, and writes to,
/// a `FileWrapper`, for one of its ``readableContentTypes`` or
/// ``writableContentTypes``, and that `fileExporter(isPresented:document:…)`
/// writes.
///
/// ```swift
/// struct TextFile: FileDocument {
///     static var readableContentTypes: [UTType] { [.plainText] }
///     var text = ""
///
///     init(text: String = "") { self.text = text }
///
///     init(configuration: ReadConfiguration) throws {
///         guard let data = configuration.file.regularFileContents else {
///             throw CocoaError(.fileReadCorruptFile)
///         }
///         text = String(decoding: data, as: UTF8.self)
///     }
///
///     func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
///         FileWrapper(regularFileWithContents: Data(text.utf8))
///     }
/// }
/// ```
///
/// That compiles on Linux unchanged, where `UTType` and `FileWrapper` are TUI's;
/// only `import UniformTypeIdentifiers`, if the file says so, wants
/// `#if canImport(UniformTypeIdentifiers)`.
@preconcurrency
public protocol FileDocument: Sendable {
    /// The file and data types that the document reads from.
    static var readableContentTypes: [UTType] { get }

    /// The file types that the document supports saving or exporting to.
    ///
    /// By default, the ``readableContentTypes``.
    static var writableContentTypes: [UTType] { get }

    /// Creates a document and initializes it with the contents of a file.
    ///
    /// TUI calls it off the main actor, as SwiftUI calls it on a background
    /// thread.
    ///
    /// - Parameter configuration: Information about the file that you
    ///   read document data from.
    init(configuration: ReadConfiguration) throws

    /// The configuration for reading document contents.
    typealias ReadConfiguration = FileDocumentReadConfiguration

    /// Serializes a document snapshot to a file wrapper.
    ///
    /// TUI calls it off the main actor, as SwiftUI calls it on a background
    /// thread.
    ///
    /// - Parameter configuration: Information about a file that already
    ///   exists for the document, if any.
    /// - Returns: The destination to serialize the document contents to.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper

    /// The configuration for writing document contents.
    typealias WriteConfiguration = FileDocumentWriteConfiguration
}

extension FileDocument {
    /// The file types that the document supports saving or exporting to:
    /// by default, the types it reads.
    public static var writableContentTypes: [UTType] { readableContentTypes }
}

/// The configuration for reading file contents.
public struct FileDocumentReadConfiguration {
    /// The expected uniform type of the file contents.
    public let contentType: UTType

    /// The file wrapper containing the document content.
    public let file: FileWrapper

    /// Package-made, as SwiftUI's has no public initializer.
    package init(contentType: UTType, file: FileWrapper) {
        self.contentType = contentType
        self.file = file
    }
}

/// The configuration for serializing file contents.
public struct FileDocumentWriteConfiguration {
    /// The expected uniform type of the file contents.
    public let contentType: UTType

    /// The file wrapper containing the current document content: the file a
    /// save in place is about to replace. `nil` if the document is unsaved,
    /// or is being written somewhere new, as a Save As and an export are.
    public let existingFile: FileWrapper?

    /// Package-made, as SwiftUI's has no public initializer.
    package init(contentType: UTType, existingFile: FileWrapper?) {
        self.contentType = contentType
        self.existingFile = existingFile
    }
}

/// Reading a document from where a panel, or an app, says it is.
package enum FileDocumentRead {
    /// The document at `url`, read as `type`, off the main actor, as SwiftUI
    /// calls ``FileDocument/init(configuration:)`` on a background thread.
    @concurrent
    package static func read<D: FileDocument>(_: D.Type = D.self, from url: URL, as type: UTType) async throws -> D {
        try D(configuration: FileDocumentReadConfiguration(contentType: type, file: FileWrapper(url: url, options: .immediate)))
    }

    /// The type to read the file at `url` as: of `types`, the one its name
    /// says, else the first; plain data where there are none.
    package static func contentType(of url: URL, among types: [UTType]) -> UTType {
        SaveName.type(for: url.lastPathComponent, among: types) ?? .data
    }
}

/// Writing a document where a panel chose a place for it, or over the file it
/// was read from.
package enum FileDocumentWrite {
    /// `document` serialized as `type` and written to `url`, off the main
    /// actor (as SwiftUI calls ``FileDocument/fileWrapper(configuration:)``
    /// on a background thread), atomically, replacing what is there: the
    /// panel asked before handing over a URL that exists.
    ///
    /// - Parameter existing: Where the document's current file is, for its
    ///   ``FileDocumentWriteConfiguration/existingFile``: `nil` for a file
    ///   being made somewhere new.
    @concurrent
    package static func write<D: FileDocument>(
        _ document: D, as type: UTType, to url: URL, existing: URL? = nil
    ) async -> Result<URL, any Error> {
        do {
            let wrapper = try document.fileWrapper(
                configuration: FileDocumentWriteConfiguration(
                    contentType: type, existingFile: existing.flatMap { try? FileWrapper(url: $0) }))
            try wrapper.write(to: url, options: .atomic, originalContentsURL: existing)
            return .success(url)
        } catch {
            return .failure(error)
        }
    }

    /// Writes `documents` into `folder`, each under its name, in order;
    /// the first failure ends the operation — an item of the name made
    /// since the names were chosen (``ExportNames``) one, never replaced.
    @MainActor
    static func write<D: FileDocument>(
        _ documents: [D], named names: [String], as types: [UTType], into folder: URL
    ) async -> Result<[URL], any Error> {
        await write(documents, named: names, as: types, into: folder) { document, type, url in
            await write(document, as: type, to: url)
        }
    }

    /// Writes `documents` into `folder` with `writeOne`, each under its name,
    /// in order; the first failure ends the operation.
    @MainActor
    static func write<D>(
        _ documents: [D], named names: [String], as types: [UTType], into folder: URL,
        with writeOne: @MainActor (D, UTType, URL) async -> Result<URL, any Error>
    ) async -> Result<[URL], any Error> {
        var written: [URL] = []
        for (index, document) in documents.enumerated() {
            let url = folder.appendingPathComponent(names[index])
            if FileManager.default.itemExists(atPath: url.path) {
                return .failure(CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path]))
            }
            let type = SaveName.type(for: names[index], among: types) ?? .data
            switch await writeOne(document, type, url) {
            case .success(let url): written.append(url)
            case .failure(let error): return .failure(error)
            }
        }
        return .success(written)
    }
}
