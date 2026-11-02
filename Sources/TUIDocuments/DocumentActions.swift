//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentActions.swift
//
//  SwiftUI's `newDocument` and `openDocument` environment actions.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFilePanels
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// An action in the environment that presents a new document.
///
/// SwiftUI's opens a window. Here there is one document at a time, so it
/// replaces the one open, after asking about any unsaved changes
/// (``DocumentGroup``). It does nothing outside a `DocumentGroup`, and for a
/// document of another type than the group's.
public struct NewDocumentAction: Sendable, Equatable {
    /// The document scene this acts on, if there is one.
    let session: DocumentSession?

    /// Presents a new document window with preset contents.
    ///
    /// - Parameter newDocument: The new document.
    @preconcurrency
    @MainActor
    public func callAsFunction<D: FileDocument>(_ newDocument: @autoclosure @escaping @Sendable () -> D) {
        guard let session, let store = session.store as? FileDocumentStore<D> else { return }
        session.new { store.replaceDocument(with: newDocument()) }
    }

    /// Presents a new reference document window with preset contents.
    ///
    /// - Parameter newDocument: Makes the new document.
    @preconcurrency
    @MainActor
    public func callAsFunction<D: ReferenceFileDocument>(_ newDocument: @escaping @Sendable () -> D) {
        guard let session, let store = session.store as? ReferenceDocumentStore<D> else { return }
        session.new { store.replaceDocument(with: newDocument()) }
    }

    /// Presents a new document of the given content type, from the
    /// `newDocument` the group was declared with: what it saves as, unless the
    /// save panel is told otherwise.
    ///
    /// - Parameter contentType: The type of the new document.
    @preconcurrency
    @MainActor
    public func callAsFunction(contentType: UTType) {
        session?.new(contentType: contentType)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session === rhs.session
    }
}

/// An action in the environment that presents an existing document.
///
/// SwiftUI's opens a window. Here there is one document at a time, so it
/// replaces the one open, after asking about any unsaved changes
/// (``DocumentGroup``).
public struct OpenDocumentAction: Sendable, Equatable {
    /// The document scene this acts on, if there is one.
    let session: DocumentSession?

    /// Opens the document at `url`.
    ///
    /// - Parameter url: The file to open.
    /// - Throws: Whatever reading it threw, leaving the document open as it was;
    ///   `CancellationError` where the person chose Cancel or cancelled saving
    ///   the changes; `CocoaError(.featureUnsupported)` outside a
    ///   ``DocumentGroup``.
    @MainActor
    public func callAsFunction(at url: URL) async throws {
        guard let session else { throw CocoaError(.featureUnsupported) }
        try await session.open(url)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session === rhs.session
    }
}

private struct NewDocumentKey: EnvironmentKey {
    static let defaultValue = NewDocumentAction(session: nil)
}

private struct OpenDocumentKey: EnvironmentKey {
    static let defaultValue = OpenDocumentAction(session: nil)
}

extension EnvironmentValues {
    /// An action in the environment that presents a new document.
    public internal(set) var newDocument: NewDocumentAction {
        get { self[NewDocumentKey.self] }
        set { self[NewDocumentKey.self] = newValue }
    }

    /// An action in the environment that presents an existing document.
    public internal(set) var openDocument: OpenDocumentAction {
        get { self[OpenDocumentKey.self] }
        set { self[OpenDocumentKey.self] = newValue }
    }
}
