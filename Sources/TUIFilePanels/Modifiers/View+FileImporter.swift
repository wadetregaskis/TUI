//  🖥️ TUI — A Terminal UI framework for Swift
//  View+FileImporter.swift
//
//  SwiftUI's three `fileImporter` modifiers: an open panel TUI draws, in
//  a sheet.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

extension View {
    /// Presents a system interface for allowing the user to import an existing
    /// file.
    ///
    /// In order for the interface to appear, `isPresented` must be `true`. When
    /// the operation is finished, `isPresented` will be set to `false` before
    /// `onCompletion` is called. If the user cancels the operation,
    /// `isPresented` will be set to `false` and `onCompletion` will not be
    /// called.
    ///
    /// The interface is a panel TUI draws in a sheet, as SwiftUI presents
    /// the system's open panel: the items of a folder in a table, folders first,
    /// the ones of a type `allowedContentTypes` does not name dimmed. Return
    /// or a double-click opens a folder or chooses a file; Backspace goes
    /// to the enclosing folder, `~` to the home folder; Escape cancels. It
    /// opens on the process's working directory, the folder its user started
    /// it from, then on the folder of the last choice made through this
    /// modifier.
    ///
    /// The panel browses the file system of the machine the app runs on — over
    /// `ssh`, the remote machine's, not the user's own.
    ///
    /// ```swift
    /// @State private var importing = false
    ///
    /// Button("Choose templates directory") { importing = true }
    ///     .fileImporter(isPresented: $importing, allowedContentTypes: [.directory]) { result in
    ///         if case .success(let directory) = result { useTemplates(at: directory) }
    ///     }
    /// ```
    ///
    /// The URL is a plain file URL. Apple's documentation asks for
    /// `startAccessingSecurityScopedResource()` around its use, which a sandboxed
    /// macOS app needs; the call is harmless here on macOS (it returns `true`),
    /// and Linux's Foundation has no such method, so code shared with Linux
    /// keeps it inside `#if canImport(Darwin)`.
    ///
    /// - Note: Changing `allowedContentTypes` while the file importer is
    ///   presented will have no immediate effect, however will apply the next
    ///   time it is presented.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - allowedContentTypes: The list of supported content types which can
    ///     be imported.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    public func fileImporter(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, any Error>) -> Void
    ) -> some View {
        fileImporterPanel(
            isPresented: isPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: false,
            onChoose: { urls in
                if let url = urls.first { onCompletion(.success(url)) }
            }, onCancellation: {})
    }

    /// Presents a system dialog for allowing the user to import multiple
    /// files.
    ///
    /// In order for the dialog to appear, `isPresented` must be `true`. When
    /// the operation is finished, `isPresented` will be set to `false` before
    /// `onCompletion` is called. If the user cancels the operation,
    /// `isPresented` will be set to `false` and `onCompletion` will not be
    /// called.
    ///
    /// The panel is the one ``fileImporter(isPresented:allowedContentTypes:onCompletion:)``
    /// presents; with `allowsMultipleSelection`, Space adds the item under the
    /// cursor to the selection (and takes it out again), and Return on a
    /// selected item, or the confirmation button, chooses the whole selection.
    ///
    /// - Note: Changing `allowedContentTypes` or `allowsMultipleSelection`
    ///   while the file importer is presented will have no immediate effect,
    ///   however will apply the next time it is presented.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the dialog should be shown.
    ///   - allowedContentTypes: The list of supported content types which can
    ///     be imported.
    ///   - allowsMultipleSelection: Whether the importer allows the user to
    ///     select more than one file to import.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    public func fileImporter(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], any Error>) -> Void
    ) -> some View {
        fileImporterPanel(
            isPresented: isPresented, allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: allowsMultipleSelection, onChoose: { onCompletion(.success($0)) },
            onCancellation: {})
    }

    /// Presents a system dialog for allowing the user to import multiple
    /// files, with a callback for when the user cancels.
    ///
    /// The same as ``fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)``,
    /// and `onCancellation` is called once the panel has gone without a choice:
    /// Cancel, Escape, or the app setting `isPresented` to `false` itself.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the dialog should be shown.
    ///   - allowedContentTypes: The list of supported content types which can
    ///     be imported.
    ///   - allowsMultipleSelection: Whether the importer allows the user to
    ///     select more than one file to import.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    ///   - onCancellation: A callback that will be invoked if the user cancels
    ///     the operation.
    public func fileImporter(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], any Error>) -> Void, onCancellation: @escaping () -> Void
    ) -> some View {
        fileImporterPanel(
            isPresented: isPresented, allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: allowsMultipleSelection, onChoose: { onCompletion(.success($0)) },
            onCancellation: onCancellation)
    }

    /// The three importers' one presentation.
    private func fileImporterPanel(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
        onChoose: @escaping ([URL]) -> Void, onCancellation: @escaping () -> Void
    ) -> some View {
        FilePanelPresenter(
            content: self, isPresented: isPresented,
            request: {
                let open = LocalizationService.shared.string(for: LocalizationKey.FilePanel.open)
                return FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: allowsMultipleSelection),
                    rule: FileChoiceRule(allowedContentTypes: allowedContentTypes), title: open,
                    confirmationLabel: open, startDirectory: FilePanelRequest.defaultStartDirectory)
            },
            onChoose: onChoose, onCancel: onCancellation)
    }
}
