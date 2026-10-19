//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+FileMover.swift
//
//  SwiftUI's four `fileMover` modifiers: a panel TUIkit draws to choose a
//  folder, and the move into it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

extension View {
    /// Presents a system dialog for allowing the user to move an existing file
    /// to a new location.
    ///
    /// In order for the dialog to appear, `isPresented` must be `true` and
    /// `file` must not be `nil`. When the operation is finished, `isPresented`
    /// will be set to `false` before `onCompletion` is called. If the user
    /// cancels the operation, `isPresented` will be set to `false` and
    /// `onCompletion` will not be called.
    ///
    /// The dialog is the panel `fileImporter` presents, titled Move, choosing a
    /// folder: the files in it are dimmed, Return opens a folder, and Move moves
    /// the file into the folder selected, or into the folder shown when none
    /// is. It opens on the folder that holds the file; once a move has been
    /// made through this view, on the folder moved into, as every file panel
    /// opens on the folder of its last choice (and a macOS panel on the
    /// folder used last); `fileDialogDefaultDirectory(_:)` names one before
    /// both. The move is `FileManager.moveItem(at:to:)`, done off the main
    /// actor; `onCompletion` is handed the file's new URL, or the error — an
    /// item of the same name already in the folder is one,
    /// `CocoaError.fileWriteFileExists`. Moving a file to the folder it is in
    /// already is a success that moves nothing.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the dialog should be shown.
    ///   - file: The URL of the file to be moved.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    public func fileMover(
        isPresented: Binding<Bool>, file: URL?, onCompletion: @escaping (Result<URL, any Error>) -> Void
    ) -> some View {
        fileMoverPanel(
            isPresented: isPresented, files: file.map { [$0] } ?? [],
            onCompletion: { result in onCompletion(result.map { $0[0] }) }, onCancellation: {})
    }

    /// Presents a system dialog for allowing the user to move an existing file
    /// to a new location, with a callback for when the user cancels.
    ///
    /// The same as ``fileMover(isPresented:file:onCompletion:)``, and
    /// `onCancellation` is called once the dialog has gone without a choice.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the dialog should be shown.
    ///   - file: The URL of the file to be moved.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    ///   - onCancellation: A callback that will be invoked if the user cancels
    ///     the operation.
    public func fileMover(
        isPresented: Binding<Bool>, file: URL?, onCompletion: @escaping (Result<URL, any Error>) -> Void,
        onCancellation: @escaping () -> Void
    ) -> some View {
        fileMoverPanel(
            isPresented: isPresented, files: file.map { [$0] } ?? [],
            onCompletion: { result in onCompletion(result.map { $0[0] }) }, onCancellation: onCancellation)
    }

    /// Presents a system interface for allowing the user to move a collection
    /// of existing files to a new location.
    ///
    /// In order for the interface to appear, both `isPresented` must be `true`
    /// and `files` must not be empty. When the operation is finished,
    /// `isPresented` will be set to `false` before `onCompletion` is called. If
    /// the user cancels the operation, `isPresented` will be set to `false`
    /// and `onCompletion` will not be called.
    ///
    /// The files move one after another, in the collection's order; the first
    /// that cannot be moved ends the operation with its error, and the ones
    /// before it stay where they were moved.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - files: A collection of `URL`s for the files to be moved.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    public func fileMover<C: Collection>(
        isPresented: Binding<Bool>, files: C, onCompletion: @escaping (Result<[URL], any Error>) -> Void
    ) -> some View where C.Element == URL {
        fileMoverPanel(
            isPresented: isPresented, files: Array(files), onCompletion: onCompletion, onCancellation: {})
    }

    /// Presents a system dialog for allowing the user to move a collection of
    /// existing files to a new location, with a callback for when the user
    /// cancels.
    ///
    /// The same as ``fileMover(isPresented:files:onCompletion:)``, and
    /// `onCancellation` is called once the dialog has gone without a choice.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the dialog should be shown.
    ///   - files: A collection of `URL`s for the files to be moved.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    ///   - onCancellation: A callback that will be invoked if the user cancels
    ///     the operation.
    public func fileMover<C: Collection>(
        isPresented: Binding<Bool>, files: C, onCompletion: @escaping (Result<[URL], any Error>) -> Void,
        onCancellation: @escaping () -> Void
    ) -> some View where C.Element == URL {
        fileMoverPanel(
            isPresented: isPresented, files: Array(files), onCompletion: onCompletion,
            onCancellation: onCancellation)
    }

    /// The four movers' one presentation: a panel choosing a folder, shown only
    /// while there are files to move, and the move into the folder chosen.
    private func fileMoverPanel(
        isPresented: Binding<Bool>, files: [URL], onCompletion: @escaping (Result<[URL], any Error>) -> Void,
        onCancellation: @escaping () -> Void
    ) -> some View {
        // Shown only with files to move, as SwiftUI documents; the app's
        // binding is cleared as it is for any other dismissal.
        let shown = Binding<Bool>(
            get: { isPresented.wrappedValue && !files.isEmpty },
            set: { isPresented.wrappedValue = $0 })
        return FilePanelPresenter(
            content: self, isPresented: shown,
            request: {
                let move = LocalizationService.shared.string(for: LocalizationKey.FilePanel.move)
                return FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false),
                    rule: FileChoiceRule(allowedContentTypes: [.folder], choosesFiles: false), title: move,
                    confirmationLabel: move,
                    // Until a choice is made through this view, which the
                    // presenter opens on instead.
                    startDirectory: files.first?.deletingLastPathComponent() ?? FilePanelRequest.defaultStartDirectory)
            },
            onChoose: { folders in
                guard let folder = folders.first else { return }
                Task { @MainActor in
                    onCompletion(await FileMove.move(files, into: folder))
                }
            },
            onCancel: onCancellation)
    }
}

/// Moving files into a folder a mover chose.
enum FileMove {
    /// Moves `files` into `folder`, in order, off the main actor.
    ///
    /// - Returns: The files' new URLs, or the first error, which ends the
    ///   operation: the files moved before it stay moved.
    @concurrent
    static func move(_ files: [URL], into folder: URL) async -> Result<[URL], any Error> {
        var moved: [URL] = []
        for file in files {
            let destination = folder.appendingPathComponent(file.lastPathComponent)
            // Already there: nothing to move, and `moveItem` would refuse.
            if destination.standardizedFileURL.path == file.standardizedFileURL.path {
                moved.append(file)
                continue
            }
            do {
                try FileManager.default.moveItem(at: file, to: destination)
                moved.append(destination)
            } catch {
                return .failure(error)
            }
        }
        return .success(moved)
    }
}
