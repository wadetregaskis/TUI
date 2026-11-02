//  🖥️ TUI — A Terminal UI framework for Swift
//  View+ReferenceFileDocumentExporter.swift
//
//  SwiftUI's `fileExporter` forms that write a `ReferenceFileDocument`, and the
//  save panel a document scene asks for where it should write.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

extension View {
    /// Presents a system interface for allowing the user to export a
    /// `ReferenceFileDocument` to a file on disk.
    ///
    /// As `fileExporter(isPresented:document:contentTypes:defaultFilename:onCompletion:onCancellation:)`
    /// for a `FileDocument`; what is written is the document's snapshot, taken
    /// on the main actor once a place has been chosen.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - document: The in-memory document to export.
    ///   - contentTypes: The list of supported content types which can be
    ///     exported. If not provided, `ReferenceFileDocument.writableContentTypes`
    ///     are used.
    ///   - defaultFilename: If provided, the default name to use for the
    ///     exported file, which the user will have an opportunity to edit
    ///     prior to the export.
    ///   - onCompletion: A callback that will be invoked when the operation
    ///     has succeeded or failed.
    ///   - onCancellation: A callback that will be invoked if the user
    ///     cancels the operation.
    @MainActor public func fileExporter<D: ReferenceFileDocument>(
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
    /// `ReferenceFileDocument` to a file on disk, as a single content type.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - document: The in-memory document to export.
    ///   - contentType: The content type to use for the exported file.
    ///   - defaultFilename: If provided, the default name to use for the
    ///     exported file.
    ///   - onCompletion: A callback that will be invoked when the operation
    ///     has succeeded or failed.
    @MainActor public func fileExporter<D: ReferenceFileDocument>(
        isPresented: Binding<Bool>, document: D?, contentType: UTType, defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, any Error>) -> Void
    ) -> some View {
        fileExporter(
            isPresented: isPresented, document: document, contentTypes: [contentType],
            defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: {})
    }

    /// Presents a system interface for allowing the user to export a
    /// collection of `ReferenceFileDocument`s to files on disk.
    ///
    /// As `fileExporter(isPresented:documents:contentTypes:onCompletion:onCancellation:)`
    /// for `FileDocument`s.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - documents: The in-memory documents to export.
    ///   - contentTypes: The list of supported content types which can be
    ///     exported. If not provided, `ReferenceFileDocument.writableContentTypes`
    ///     are used.
    ///   - onCompletion: A callback that will be invoked when the operation
    ///     has succeeded or failed.
    ///   - onCancellation: A callback that will be invoked if the user
    ///     cancels the operation.
    @MainActor public func fileExporter<C: Collection>(
        isPresented: Binding<Bool>, documents: C, contentTypes: [UTType] = [],
        onCompletion: @escaping (Result<[URL], any Error>) -> Void, onCancellation: @escaping () -> Void = {}
    ) -> some View where C.Element: ReferenceFileDocument {
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
                    onCompletion(
                        await FileDocumentWrite.write(all, named: names, as: types, into: folder) { document, type, url in
                            await FileDocumentWrite.write(document, as: type, to: url)
                        })
                }
            },
            onCancel: onCancellation)
    }

    /// Presents a system interface for allowing the user to export a
    /// collection of `ReferenceFileDocument`s to files on disk, as a single
    /// content type.
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
    ) -> some View where C.Element: ReferenceFileDocument {
        fileExporter(
            isPresented: isPresented, documents: documents, contentTypes: [contentType],
            onCompletion: onCompletion, onCancellation: {})
    }

    /// Presents the save panel a document scene writes through, which only asks
    /// where: `onChoose` writes, so it decides what the write means for the
    /// document it belongs to.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the panel should be shown.
    ///   - contentTypes: The types it may be saved as.
    ///   - defaultFilename: The name offered.
    ///   - onChoose: Called with the URL chosen; `isPresented` is already false.
    ///   - onCancel: Called when the panel goes without a choice.
    @MainActor package func documentSavePanel(
        isPresented: Binding<Bool>, contentTypes: [UTType], defaultFilename: String?,
        onChoose: @escaping (URL) -> Void, onCancel: @escaping () -> Void
    ) -> some View {
        FilePanelPresenter(
            content: self, isPresented: isPresented,
            request: { .save(contentTypes: contentTypes, defaultFilename: defaultFilename) },
            onChoose: { urls in if let url = urls.first { onChoose(url) } },
            onCancel: onCancel)
    }

    /// Has the panels here open on `folder`, where there is one; otherwise on
    /// what the views around them say.
    nonisolated package func documentPanelFolder(_ folder: URL?) -> some View {
        transformEnvironment(\.fileDialogCustomization) { customization in
            if let folder { customization.defaultDirectory = folder }
        }
    }
}
