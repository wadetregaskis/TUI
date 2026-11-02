//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentConfigurations.swift
//
//  What a `DocumentGroup` hands its editor or viewer, and what the views inside
//  it can read of the document.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFilePanels
import TUIFoundation

// MARK: - FileDocumentConfiguration

/// The properties of an open file document.
///
/// You receive an instance of this structure when you create a
/// ``DocumentGroup`` with a value-type document. Use it to access the document
/// in your viewer or editor.
public struct FileDocumentConfiguration<Document: FileDocument> {
    /// The current document model.
    ///
    /// Setting a new value marks the document as having changes for later
    /// saving and to prompt before they are lost. In a viewer, or for a file
    /// that cannot be written, it is ignored.
    @Binding public var document: Document

    /// The URL of the open file document, or `nil` for one never saved.
    public var fileURL: URL?

    /// Whether the document can be changed: `false` in a viewer and for a file
    /// that cannot be written.
    public var isEditable: Bool

    /// Module-made, as SwiftUI's has no public initializer.
    init(document: Binding<Document>, fileURL: URL?, isEditable: Bool) {
        self._document = document
        self.fileURL = fileURL
        self.isEditable = isEditable
    }
}

// MARK: - ReferenceFileDocumentConfiguration

/// The properties of an open reference file document.
///
/// You receive an instance of this structure when you create a
/// ``DocumentGroup`` with a reference-type document.
@MainActor
@preconcurrency
public struct ReferenceFileDocumentConfiguration<Document: ReferenceFileDocument> {
    /// The current document model.
    ///
    /// `$document` makes a binding to one of its properties
    /// (`file.$document.text`), which ignores writes where ``isEditable`` is
    /// `false`.
    @ReferenceFileDocumentObject public var document: Document

    /// The URL of the open file document, or `nil` for one never saved.
    public var fileURL: URL?

    /// Whether the document can be changed: `false` in a viewer and for a file
    /// that cannot be written.
    public var isEditable: Bool

    /// Module-made, as SwiftUI's has no public initializer.
    init(document: ReferenceFileDocumentObject<Document>, fileURL: URL?, isEditable: Bool) {
        self._document = document
        self.fileURL = fileURL
        self.isEditable = isEditable
    }
}

/// What ``ReferenceFileDocumentConfiguration/document`` is wrapped in, and what
/// its `$document` is: a way to bindings to the document's properties.
///
/// SwiftUI's is `@ObservedObject`, and its `$document` an `ObservedObject.Wrapper`,
/// which TUI declares only for the compile error that points at `@Observable`
/// (`ObservedObject` in TUIFoundation), and which has a wrapped object of its own
/// to watch where this one's group watches it. It spells the same at a use:
/// `file.$document.text` is a binding either way.
@propertyWrapper
@dynamicMemberLookup
@MainActor
public struct ReferenceFileDocumentObject<ObjectType: AnyObject> {
    /// The document.
    public var wrappedValue: ObjectType

    /// What a binding's writes go through: whether they count, and saying so.
    private let write: @MainActor (() -> Void) -> Void

    /// `wrappedValue`, with `write` around each of its bindings' writes.
    init(wrappedValue: ObjectType, write: @escaping @MainActor (() -> Void) -> Void) {
        self.wrappedValue = wrappedValue
        self.write = write
    }

    /// `$document`.
    public var projectedValue: Self { self }

    /// A binding to one of the document's properties.
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
        let object = wrappedValue
        let write = write
        return Binding(
            get: { object[keyPath: keyPath] },
            set: { value in write { object[keyPath: keyPath] = value } })
    }
}

// MARK: - DocumentConfiguration

/// The properties of an open document, whichever kind it is.
public struct DocumentConfiguration: Sendable, Equatable {
    /// A Boolean value that indicates whether you can edit the document.
    public let isEditable: Bool

    /// The URL of the open document, or `nil` for one never saved.
    public let fileURL: URL?
}

private struct DocumentConfigurationKey: EnvironmentKey {
    static let defaultValue: DocumentConfiguration? = nil
}

extension EnvironmentValues {
    /// The configuration of the document this view is in, or `nil` outside a
    /// ``DocumentGroup``, and while one shows no document.
    public internal(set) var documentConfiguration: DocumentConfiguration? {
        get { self[DocumentConfigurationKey.self] }
        set { self[DocumentConfigurationKey.self] = newValue }
    }
}
