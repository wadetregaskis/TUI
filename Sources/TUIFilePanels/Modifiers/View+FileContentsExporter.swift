//  🖥️ TUI — A Terminal UI framework for Swift
//  View+FileContentsExporter.swift
//
//  A save panel on every platform. SwiftUI's `fileExporter` takes only
//  Apple-only types — a `Transferable` (CoreTransferable) or a `FileDocument`
//  (whose `FileWrapper` is Objective-C Foundation's) — so on Linux no app
//  could ask where to save a file, though the panel itself is TUI's own and
//  portable. These two TUI-only exporters take what any platform has: a
//  value's bytes, or an `Encodable` value (decisions A-O10-1, the owner's
//  option 2, 2026-10-27: "more generic than literally `Data` … strings and
//  maybe anything that's `Codable`").
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

// MARK: - The contents

/// A value a file can be made of: its bytes, for a content type — what
/// ``View/fileExporter(isPresented:contents:contentType:defaultFilename:onCompletion:onCancellation:)``
/// saves.
///
/// `Data` is its own bytes and `String` its UTF-8, whatever the type; conform
/// a type of your own to write it differently for different types.
///
/// TUI-specific: SwiftUI's exporters take a `Transferable` or a `FileDocument`,
/// which exist only on Apple platforms. This works on every platform.
public protocol FileExportContents {
    /// The bytes of a file of `contentType` holding this value.
    ///
    /// - Parameter contentType: The type being saved: the one the chosen name's
    ///   extension names.
    /// - Throws: An error that ends the save, handed to `onCompletion`.
    func fileData(as contentType: UTType) throws -> Data
}

extension Data: FileExportContents {
    /// These bytes, whatever the type.
    public func fileData(as contentType: UTType) throws -> Data { self }
}

extension String: FileExportContents {
    /// This string as UTF-8, whatever the type.
    public func fileData(as contentType: UTType) throws -> Data { Data(utf8) }
}

// MARK: - The exporters

extension View {
    /// Presents TUI's save panel and writes `contents` to the file the user
    /// names.
    ///
    /// The panel and its rules are those of TUI's other exporters: a name field
    /// offering `defaultFilename`, else Untitled, above the folder
    /// browser; a name typed without `contentType`'s extension is given it;
    /// saving over a file asks first. The file is written atomically. When the
    /// operation is finished, `isPresented` is set to `false` before
    /// `onCompletion` is called; if the user cancels, `isPresented` is set to
    /// `false` and `onCancellation` is called instead.
    ///
    /// ```swift
    /// Text(report)
    ///     .fileExporter(
    ///         isPresented: $exporting, contents: report, contentType: .plainText,
    ///         defaultFilename: "Report"
    ///     ) { result in … }
    /// ```
    ///
    /// TUI-specific, and on every platform: SwiftUI's `fileExporter` takes a
    /// `Transferable` or a `FileDocument`, which Linux does not have.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the panel is shown.
    ///   - contents: What to save (``FileExportContents``: `Data`, a `String`,
    ///     or a type of your own); `nil` presents nothing.
    ///   - contentType: The type of file saved.
    ///   - defaultFilename: The name to offer.
    ///   - onCompletion: Called with the URL written, or the error that stopped
    ///     the write.
    ///   - onCancellation: Called if the user cancels.
    public func fileExporter<C: FileExportContents>(
        isPresented: Binding<Bool>, contents: C?, contentType: UTType, defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation: @escaping () -> Void = {}
    ) -> some View {
        let shown = Binding<Bool>(
            get: { isPresented.wrappedValue && contents != nil },
            set: { isPresented.wrappedValue = $0 })
        return FilePanelPresenter(
            content: self, isPresented: shown,
            request: { .save(contentTypes: [contentType], defaultFilename: defaultFilename) },
            onChoose: { urls in
                guard let contents, let url = urls.first else { return }
                let data: Data
                do {
                    data = try contents.fileData(as: contentType)
                } catch {
                    onCompletion(.failure(error))
                    return
                }
                Task { @MainActor in
                    onCompletion(await FileExportWrite.write(data, to: url))
                }
            },
            onCancel: onCancellation)
    }

    /// Presents TUI's save panel and writes `value`, encoded, to the file the
    /// user names: as a property list where `contentType` is one, and as JSON
    /// otherwise (sorted keys, pretty-printed, so the file reads well and
    /// compares well).
    ///
    /// ```swift
    /// Form { … }
    ///     .fileExporter(isPresented: $exporting, encoding: settings, defaultFilename: "Settings") { result in … }
    /// ```
    ///
    /// The panel, its rules and the callbacks are
    /// ``View/fileExporter(isPresented:contents:contentType:defaultFilename:onCompletion:onCancellation:)``'s.
    /// An encoding error ends the save, handed to `onCompletion`.
    ///
    /// TUI-specific, and on every platform: SwiftUI's `fileExporter` takes a
    /// `Transferable` or a `FileDocument`, which Linux does not have.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the panel is shown.
    ///   - value: What to save; `nil` presents nothing.
    ///   - contentType: The type of file saved: JSON unless named.
    ///   - defaultFilename: The name to offer.
    ///   - onCompletion: Called with the URL written, or the error that stopped
    ///     the encoding or the write.
    ///   - onCancellation: Called if the user cancels.
    public func fileExporter<Value: Encodable>(
        isPresented: Binding<Bool>, encoding value: Value?, contentType: UTType = .json,
        defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation: @escaping () -> Void = {}
    ) -> some View {
        // Wrapped without a closure: `value.map(EncodedContents.init)` captured
        // `Value.Type`, which is not `Sendable`, in this main-actor context.
        var contents: EncodedContents<Value>?
        if let value { contents = EncodedContents(value: value) }
        return fileExporter(
            isPresented: isPresented, contents: contents, contentType: contentType,
            defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: onCancellation)
    }
}

/// An `Encodable` value as a file's contents: a property list for a
/// property-list type, JSON for any other.
struct EncodedContents<Value: Encodable>: FileExportContents {
    let value: Value

    func fileData(as contentType: UTType) throws -> Data {
        if contentType.conforms(to: .propertyList) {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            return try encoder.encode(value)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
