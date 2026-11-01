//  🖥️ TUI — A Terminal UI framework for Swift
//  View+FileDocumentExporter.swift
//
//  SwiftUI's `fileExporter` forms that write a `FileDocument`: TUI's save
//  panel, and the document's file wrapper written where it says. Apple
//  platforms only, as `FileDocument` is.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(ObjectiveC)
    import Foundation
    import TUIFoundation
    import UniformTypeIdentifiers

    extension View {
        /// Presents a system interface for allowing the user to export a
        /// `FileDocument` to a file on disk.
        ///
        /// In order for the interface to appear, `isPresented` must be `true`
        /// (and `document` must not be `nil`). When the operation is finished,
        /// `isPresented` will be set to `false` before `onCompletion` is called.
        /// If the user cancels the operation, `isPresented` will be set to
        /// `false` and `onCancellation` will be called.
        ///
        /// The interface is TUI's save panel, as for
        /// `fileExporter(isPresented:item:…)`: a name field offering
        /// `defaultFilename`, or Untitled, above the folder browser; a name
        /// without one of the types' extensions is given the first type's, and
        /// saving over a file asks first. The document's
        /// ``FileDocument/fileWrapper(configuration:)`` is called off the main
        /// actor, for the type the name's extension names, and its wrapper
        /// written there atomically.
        ///
        /// - Parameters:
        ///   - isPresented: A binding to whether the interface should be shown.
        ///   - document: The in-memory document to export.
        ///   - contentTypes: The list of supported content types which can be
        ///     exported. If not provided, `FileDocument.writableContentTypes`
        ///     are used.
        ///   - defaultFilename: If provided, the default name to use for the
        ///     exported file, which the user will have an opportunity to edit
        ///     prior to the export.
        ///   - onCompletion: A callback that will be invoked when the operation
        ///     has succeeded or failed.
        ///   - onCancellation: A callback that will be invoked if the user
        ///     cancels the operation.
        @MainActor public func fileExporter<D: FileDocument>(
            isPresented: Binding<Bool>, document: D?, contentTypes: [UTType] = [], defaultFilename: String? = nil,
            onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation: @escaping () -> Void = {}
        ) -> some View {
            let types = contentTypes.isEmpty ? D.writableContentTypes : contentTypes
            let shown = Binding<Bool>(
                get: { isPresented.wrappedValue && document != nil },
                set: { isPresented.wrappedValue = $0 })
            return FilePanelPresenter(
                content: self, isPresented: shown,
                request: { .save(contentTypes: types, defaultFilename: defaultFilename) },
                onChoose: { urls in
                    guard let document, let url = urls.first else { return }
                    let type = SaveName.type(for: url.lastPathComponent, among: types) ?? .data
                    Task { @MainActor in
                        onCompletion(await FileDocumentWrite.write(document, as: type, to: url))
                    }
                },
                onCancel: onCancellation)
        }

        /// Presents a system interface for allowing the user to export a
        /// `FileDocument` to a file on disk, as a single content type.
        ///
        /// The same as ``fileExporter(isPresented:document:contentTypes:defaultFilename:onCompletion:onCancellation:)``
        /// with `[contentType]`, without a cancellation callback.
        ///
        /// - Parameters:
        ///   - isPresented: A binding to whether the interface should be shown.
        ///   - document: The in-memory document to export.
        ///   - contentType: The content type to use for the exported file.
        ///   - defaultFilename: If provided, the default name to use for the
        ///     exported file.
        ///   - onCompletion: A callback that will be invoked when the operation
        ///     has succeeded or failed.
        @MainActor public func fileExporter<D: FileDocument>(
            isPresented: Binding<Bool>, document: D?, contentType: UTType, defaultFilename: String? = nil,
            onCompletion: @escaping (Result<URL, any Error>) -> Void
        ) -> some View {
            fileExporter(
                isPresented: isPresented, document: document, contentTypes: [contentType],
                defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: {})
        }

        /// Presents a system interface for allowing the user to export a
        /// collection of `FileDocument`s to files on disk.
        ///
        /// In order for the interface to appear, `isPresented` must be `true`
        /// (and `documents` must not be empty). When the operation is finished,
        /// `isPresented` will be set to `false` before `onCompletion` is called.
        /// If the user cancels the operation, `isPresented` will be set to
        /// `false` and `onCancellation` will be called.
        ///
        /// The interface is TUI's panel choosing a folder, titled Save; the
        /// documents are written into it in order, as Untitled, Untitled 2, …
        /// with the first type's extension, numbered past the names the folder
        /// has already, so nothing is replaced; the first that cannot be
        /// written ends the operation with its error.
        ///
        /// - Parameters:
        ///   - isPresented: A binding to whether the interface should be shown.
        ///   - documents: The in-memory documents to export.
        ///   - contentTypes: The list of supported content types which can be
        ///     exported. If not provided, `FileDocument.writableContentTypes`
        ///     are used.
        ///   - onCompletion: A callback that will be invoked when the operation
        ///     has succeeded or failed.
        ///   - onCancellation: A callback that will be invoked if the user
        ///     cancels the operation.
        @MainActor public func fileExporter<C: Collection>(
            isPresented: Binding<Bool>, documents: C, contentTypes: [UTType] = [],
            onCompletion: @escaping (Result<[URL], any Error>) -> Void, onCancellation: @escaping () -> Void = {}
        ) -> some View where C.Element: FileDocument {
            let types = contentTypes.isEmpty ? C.Element.writableContentTypes : contentTypes
            let shown = Binding<Bool>(
                get: { isPresented.wrappedValue && !documents.isEmpty },
                set: { isPresented.wrappedValue = $0 })
            return FilePanelPresenter(
                content: self, isPresented: shown, request: { .saveInto() },
                onChoose: { folders in
                    guard let folder = folders.first else { return }
                    let all = Array(documents)
                    let names = ExportNames.names(
                        Array(repeating: nil, count: all.count), contentTypes: Array(repeating: types, count: all.count),
                        in: folder)
                    Task { @MainActor in
                        onCompletion(await FileDocumentWrite.write(all, named: names, as: types, into: folder))
                    }
                },
                onCancel: onCancellation)
        }

        /// Presents a system interface for allowing the user to export a
        /// collection of `FileDocument`s to files on disk, as a single content
        /// type.
        ///
        /// The same as ``fileExporter(isPresented:documents:contentTypes:onCompletion:onCancellation:)``
        /// with `[contentType]`, without a cancellation callback.
        ///
        /// - Parameters:
        ///   - isPresented: A binding to whether the interface should be shown.
        ///   - documents: The in-memory documents to export.
        ///   - contentType: The content type to use for the exported files.
        ///   - onCompletion: A callback that will be invoked when the operation
        ///     has succeeded or failed.
        @MainActor public func fileExporter<C: Collection>(
            isPresented: Binding<Bool>, documents: C, contentType: UTType,
            onCompletion: @escaping (Result<[URL], any Error>) -> Void
        ) -> some View where C.Element: FileDocument {
            fileExporter(
                isPresented: isPresented, documents: documents, contentTypes: [contentType],
                onCompletion: onCompletion, onCancellation: {})
        }
    }
#endif
