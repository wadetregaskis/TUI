//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileDocument.swift
//
//  SwiftUI's `FileDocument`, and the configurations it reads and writes
//  through: what `fileExporter(document:)` writes. Apple platforms only —
//  a document is a `FileWrapper`, which is Objective-C Foundation's.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(ObjectiveC)
    import Foundation
    import UniformTypeIdentifiers

    /// A type that you use to serialize documents to and from file.
    ///
    /// SwiftUI's protocol, as `fileExporter(isPresented:document:…)` uses it: a
    /// value that writes itself to a `FileWrapper` for one of its
    /// ``writableContentTypes``. TUIkit's panels only ever WRITE a document
    /// (there is no `DocumentGroup`, which is where SwiftUI reads one), so
    /// ``init(configuration:)`` is the app's own to call, as it is for any type
    /// that conforms.
    ///
    /// Present where `FileWrapper` is, which is Objective-C Foundation's: the
    /// Apple platforms. Elsewhere this protocol, and the exporters that take
    /// one, are absent, so code that uses them fails to compile there rather
    /// than doing nothing (decisions A18).
    ///
    /// ```swift
    /// struct TextFile: FileDocument {
    ///     static var readableContentTypes: [UTType] { [.plainText] }
    ///     var text = ""
    ///
    ///     init(text: String) { self.text = text }
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
        /// - Parameter configuration: Information about the file that you
        ///   read document data from.
        init(configuration: ReadConfiguration) throws

        /// The configuration for reading document contents.
        typealias ReadConfiguration = FileDocumentReadConfiguration

        /// Serializes a document snapshot to a file wrapper.
        ///
        /// TUIkit calls it off the main actor, as SwiftUI calls it on a
        /// background thread.
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

        /// The file wrapper containing the current document content. `nil` if
        /// the document is unsaved — which, exported, it always is: an export
        /// writes a new file.
        public let existingFile: FileWrapper?

        /// Package-made, as SwiftUI's has no public initializer.
        package init(contentType: UTType, existingFile: FileWrapper?) {
            self.contentType = contentType
            self.existingFile = existingFile
        }
    }

    /// Writing a document an exporter's panel chose a place for.
    enum FileDocumentWrite {
        /// `document` serialized as `type` and written to `url`, off the main
        /// actor (as SwiftUI calls ``FileDocument/fileWrapper(configuration:)``
        /// on a background thread), atomically, replacing what is there: the
        /// panel asked before handing over a URL that exists.
        @concurrent
        static func write<D: FileDocument>(_ document: D, as type: UTType, to url: URL) async -> Result<URL, any Error> {
            do {
                let wrapper = try document.fileWrapper(
                    configuration: FileDocumentWriteConfiguration(contentType: type, existingFile: nil))
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
                return .success(url)
            } catch {
                return .failure(error)
            }
        }

        /// Writes `documents` into `folder`, each under its name, in order;
        /// the first failure ends the operation — an item of the name made
        /// since the names were chosen (``ExportNames``) one, never replaced.
        static func write<D: FileDocument>(
            _ documents: [D], named names: [String], as types: [UTType], into folder: URL
        ) async -> Result<[URL], any Error> {
            var written: [URL] = []
            for (index, document) in documents.enumerated() {
                let url = folder.appendingPathComponent(names[index])
                if FileManager.default.fileExists(atPath: url.path) {
                    return .failure(CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path]))
                }
                let type = SaveName.type(for: names[index], among: types) ?? .data
                switch await write(document, as: type, to: url) {
                case .success(let url): written.append(url)
                case .failure(let error): return .failure(error)
                }
            }
            return .success(written)
        }
    }
#endif
