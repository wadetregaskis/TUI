//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+FileExporter.swift
//
//  SwiftUI's `fileExporter` for `Transferable` items, and the label of the
//  save panel's name field: a save panel TUIkit draws, and the write.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

// MARK: - The name field's label

extension View {
    /// On macOS, configures the `fileExporter` with a text to use as a label
    /// for the file name field.
    ///
    /// TUIkit's save panel shows it beside its name field on every platform;
    /// without one the field is labelled Save As:.
    ///
    /// - Parameter label: The optional text to use as the label for the file
    ///   name field; `nil` for the panel's own.
    public func fileExporterFilenameLabel(_ label: Text?) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.filenameLabel = label?.content }
    }

    /// On macOS, configures the `fileExporter` with a label for the file name
    /// field.
    ///
    /// - Parameter labelKey: The key to a localized string to display.
    public func fileExporterFilenameLabel(_ labelKey: LocalizedStringKey) -> some View {
        let label = labelKey.localized
        return transformEnvironment(\.fileDialogCustomization) { $0.filenameLabel = label }
    }

    /// On macOS, configures the `fileExporter` with a label for the file name
    /// field.
    ///
    /// - Parameter label: The string to use as the label for the file name
    ///   field.
    @_disfavoredOverload
    public func fileExporterFilenameLabel<S: StringProtocol>(_ label: S) -> some View {
        let label = String(label)
        return transformEnvironment(\.fileDialogCustomization) { $0.filenameLabel = label }
    }
}

// MARK: - The save panel's two shapes

extension FilePanelRequest {
    /// A save panel: a name, in a folder, for one file of `contentTypes`,
    /// offering `defaultFilename`, else Untitled, as a macOS save panel offers
    /// one: never an empty field, in which Save does nothing.
    static func save(contentTypes: [UTType], defaultFilename: String?) -> Self {
        let save = LocalizationService.shared.string(for: LocalizationKey.Button.save)
        var request = Self(
            purpose: .save(contentTypes: contentTypes),
            rule: FileChoiceRule(allowedContentTypes: contentTypes), title: save, confirmationLabel: save,
            startDirectory: defaultStartDirectory)
        request.defaultFilename =
            defaultFilename ?? LocalizationService.shared.string(for: LocalizationKey.FilePanel.untitled)
        return request
    }

    /// A panel choosing the folder several files are saved into, each under
    /// its own name: a mover's panel, titled Save.
    static func saveInto() -> Self {
        let save = LocalizationService.shared.string(for: LocalizationKey.Button.save)
        return Self(
            purpose: .open(allowsMultipleSelection: false),
            rule: FileChoiceRule(allowedContentTypes: [.folder], choosesFiles: false), title: save,
            confirmationLabel: save, startDirectory: defaultStartDirectory)
    }
}

/// The names several exported files are given in the folder chosen for
/// them: each one's suggested name, else Untitled — a suggestion no file can
/// have too — with its type's extension, as ``SaveName/resolve(_:contentTypes:)``
/// gives one; and numbered as Finder numbers a copy it keeps beside the
/// original (`note.txt`, `note 2.txt`, `note 3.txt`) where the folder has the
/// name already, or a file saved before it in the same export took it. So an
/// export neither replaces a file nor fails on its own names: two items that
/// suggest one name, or the same documents exported twice, once ended at the
/// second file, with the first written.
enum ExportNames {
    static func names(_ suggested: [String?], contentTypes: [[UTType]], in folder: URL) -> [String] {
        let untitled = LocalizationService.shared.string(for: LocalizationKey.FilePanel.untitled)
        // Lowercased: a Mac's disk does not tell two names apart by their
        // case alone, so neither does this.
        var taken: Set<String> = []
        return zip(suggested, contentTypes).map { suggestion, types in
            let name =
                suggestion.flatMap { SaveName.resolve($0, contentTypes: types) }
                ?? SaveName.resolve(untitled, contentTypes: types) ?? untitled
            let free = firstFree(name) { candidate in
                !taken.contains(candidate.lowercased())
                    && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
            }
            taken.insert(free.lowercased())
            return free
        }
    }

    /// `name`, or else the first of `name 2`, `name 3`, …, the number before
    /// the extension, that `isFree` takes.
    static func firstFree(_ name: String, isFree: (String) -> Bool) -> String {
        if isFree(name) { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if isFree(candidate) { return candidate }
            number += 1
        }
    }
}

/// Writing a file a save panel chose, off the main actor.
enum FileExportWrite {
    /// Writes `data` to `url`, atomically, replacing what is there: the panel
    /// asked before handing over a URL that exists.
    @concurrent
    static func write(_ data: Data, to url: URL) async -> Result<URL, any Error> {
        do {
            // Atomically where the platform can, as `AppStorage` writes: WASI's
            // Foundation refuses the option, having no temporary directory to
            // write through, so there the write is direct.
            #if canImport(WASILibc)
                try data.write(to: url)
            #else
                try data.write(to: url, options: .atomic)
            #endif
            return .success(url)
        } catch {
            return .failure(error)
        }
    }
}

#if canImport(CoreTransferable)
    import CoreTransferable

    // MARK: - Transferable items

    extension View {
        /// Presents a system interface allowing the user to export a
        /// `Transferable` item to file on disk.
        ///
        /// In order for the interface to appear `isPresented` must be set to
        /// `true`. When the operation is finished, `isPresented` will be set
        /// to `false` before `onCompletion` is called. If the user cancels the
        /// operation, `isPresented` will be set to `false` and `onCompletion`
        /// will not be called.
        ///
        /// The interface is TUIkit's save panel: a name field — Save As:, or
        /// the `fileExporterFilenameLabel(_:)` — offering `defaultFilename`, or
        /// the item's suggested file name, or Untitled, above the folder
        /// browser; Return in the field, or Save, saves. A name typed without
        /// the type's extension is given it. Saving over a file asks first.
        /// The item is exported through its `transferRepresentation` as the
        /// type its name's extension names, of `contentTypes` (or of the types
        /// it exports, when `contentTypes` is empty), and written atomically.
        ///
        /// Apple platforms only: `Transferable` is CoreTransferable's, which
        /// Linux does not have.
        ///
        /// - Parameters:
        ///   - isPresented: A binding to whether the interface should be shown.
        ///   - item: The item to be saved on disk; `nil` presents nothing.
        ///   - contentTypes: The optional content types to use for the exported
        ///     file. If empty, the content types from the item's
        ///     `transferRepresentation` are used.
        ///   - defaultFilename: The name to offer.
        ///   - onCompletion: A callback that will be invoked when the operation
        ///     has succeeded or failed.
        ///   - onCancellation: A callback that will be invoked if the operation
        ///     was cancelled.
        public func fileExporter<T: Transferable>(
            isPresented: Binding<Bool>, item: T?, contentTypes: [UTType] = [], defaultFilename: String? = nil,
            onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation: @escaping () -> Void = {}
        ) -> some View {
            // The item is registered with a provider only when the panel needs
            // it — as it presents, and as it saves — not on every body.
            let shown = Binding<Bool>(
                get: { isPresented.wrappedValue && item != nil },
                set: { isPresented.wrappedValue = $0 })
            return FilePanelPresenter(
                content: self, isPresented: shown,
                request: {
                    let export = item.map { TransferableExport($0, contentTypes: contentTypes) }
                    return .save(
                        contentTypes: export?.contentTypes ?? contentTypes,
                        defaultFilename: defaultFilename ?? export?.suggestedFilename)
                },
                onChoose: { urls in
                    guard let item, let url = urls.first else { return }
                    let export = TransferableExport(item, contentTypes: contentTypes)
                    Task { @MainActor in
                        onCompletion(await export.write(to: url))
                    }
                },
                onCancel: onCancellation)
        }

        /// Presents a system interface allowing the user to export a
        /// collection of items to files on disk.
        ///
        /// In order for the interface to appear `isPresented` must be set to
        /// `true` (and `items` must not be empty). When the operation is
        /// finished, `isPresented` will be set to `false` before
        /// `onCompletion` is called. If the user cancels the operation,
        /// `isPresented` will be set to `false` and `onCompletion` will not be
        /// called.
        ///
        /// The interface is TUIkit's panel choosing a folder, titled Save; each
        /// item is saved into it under its suggested file name, or Untitled,
        /// with its type's extension — numbered, `note 2.txt`, where the folder
        /// has the name already or an item before it took it, so nothing is
        /// replaced. The items are written in order, and the first that cannot
        /// be ends the operation with its error.
        ///
        /// Apple platforms only, as ``fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)``.
        ///
        /// - Parameters:
        ///   - isPresented: A binding to whether the interface should be shown.
        ///   - items: Collection of values to be saved on disk.
        ///   - contentTypes: The content types to use for the exported files.
        ///     If empty, the content types from each item's
        ///     `transferRepresentation` are used.
        ///   - onCompletion: A callback that will be invoked when the operation
        ///     has succeeded or failed.
        ///   - onCancellation: A callback that will be invoked if the operation
        ///     was cancelled.
        public func fileExporter<C: Collection, T: Transferable>(
            isPresented: Binding<Bool>, items: C, contentTypes: [UTType] = [],
            onCompletion: @escaping (Result<[URL], any Error>) -> Void, onCancellation: @escaping () -> Void = {}
        ) -> some View where T == C.Element {
            let shown = Binding<Bool>(
                get: { isPresented.wrappedValue && !items.isEmpty },
                set: { isPresented.wrappedValue = $0 })
            return FilePanelPresenter(
                content: self, isPresented: shown, request: { .saveInto() },
                onChoose: { folders in
                    guard let folder = folders.first else { return }
                    let exports = items.map { TransferableExport($0, contentTypes: contentTypes) }
                    let names = ExportNames.names(
                        exports.map(\.suggestedFilename), contentTypes: exports.map(\.contentTypes), in: folder)
                    Task { @MainActor in
                        onCompletion(await TransferableExport.write(exports, named: names, into: folder))
                    }
                },
                onCancel: onCancellation)
        }
    }

    /// A `Transferable` item to export, made ready before its panel shows:
    /// registered with an item provider, which knows the types the item
    /// exports as and the name it suggests, and loads its data.
    ///
    /// Through `NSItemProvider` rather than `Transferable.exported(as:)`, which
    /// is macOS 15.2's, where TUIkit runs on macOS 14 (registering a
    /// `Transferable` is macOS 13's).
    /// An item handed to `NSItemProvider`, whose `register(_:)` takes it as
    /// a `@Sendable` autoclosure: see ``TransferableExport/init(_:contentTypes:)``.
    private struct HandedItem<T>: @unchecked Sendable {
        let item: T

        init(_ item: T) {
            self.item = item
        }
    }

    struct TransferableExport: @unchecked Sendable {
        /// The provider the item is registered with. Only read, and only
        /// asked to load: `@unchecked Sendable` for the provider, which is
        /// not marked so.
        private let provider: NSItemProvider

        /// The types the file can be saved as: the caller's, else the ones
        /// the item exports as.
        let contentTypes: [UTType]

        /// The file name the item suggests, if any.
        let suggestedFilename: String?

        @MainActor
        init<T: Transferable>(_ item: T, contentTypes: [UTType]) {
            let provider = NSItemProvider()
            // The provider takes the item as a `@Sendable` autoclosure, which
            // it may call on a queue of its own when it loads the data.
            // SwiftUI's `fileExporter` takes any `Transferable`, `Sendable` or
            // not, so the item is handed over in a box that vouches for it, as
            // SwiftUI's must: only that load reads it, once the panel is
            // closed. swift.org 6.4.0 rejects the bare capture ("implicit
            // capture of 'item' requires that 'T' conforms to 'Sendable'"),
            // which Xcode's 6.2.4 let through. It still warns that the
            // autoclosure captures `T`'s metatype (SE-0470), which nothing
            // SwiftUI's signature lets `T` be constrained by can make
            // `Sendable`.
            let handed = HandedItem(item)
            provider.register(handed.item)
            self.provider = provider
            self.contentTypes = contentTypes.isEmpty ? provider.registeredContentTypes : contentTypes
            // An empty suggestion is none: the panel offers Untitled instead.
            self.suggestedFilename = provider.suggestedName.flatMap { $0.isEmpty ? nil : $0 }
        }

        /// The item exported as the type `url`'s name names and written there.
        func write(to url: URL) async -> Result<URL, any Error> {
            guard let type = SaveName.type(for: url.lastPathComponent, among: contentTypes) else {
                return .failure(CocoaError(.fileWriteUnsupportedScheme))
            }
            do {
                return await FileExportWrite.write(try await data(as: type), to: url)
            } catch {
                return .failure(error)
            }
        }

        /// The item's data as `type`.
        private func data(as type: UTType) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadDataRepresentation(for: type) { data, error in
                    if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    }
                }
            }
        }

        /// Writes `exports` into `folder`, each under its name, in order; the
        /// first failure ends the operation — an item of the name made since
        /// the names were chosen (``ExportNames``) one, never replaced.
        static func write(
            _ exports: [Self], named names: [String], into folder: URL
        ) async -> Result<[URL], any Error> {
            var written: [URL] = []
            for (export, name) in zip(exports, names) {
                let url = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return .failure(CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path]))
                }
                switch await export.write(to: url) {
                case .success(let url): written.append(url)
                case .failure(let error): return .failure(error)
                }
            }
            return .success(written)
        }
    }
#endif
