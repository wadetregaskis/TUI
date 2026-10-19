//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextContentTypeEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation
import TUIkitStyling

// MARK: - Environment Key

/// Environment key for the text content type.
private struct TextContentTypeKey: EnvironmentKey {
    static let defaultValue: TextContentType? = nil
}

extension EnvironmentValues {
    /// The text content type for text fields and editors.
    ///
    /// When set, text fields, secure fields and text editors filter both
    /// typed characters and pasted text against the allowed character set of
    /// the content type, and ring the terminal's bell for what they drop.
    ///
    /// Set this value using the `.textContentType(_:)` modifier:
    ///
    /// ```swift
    /// TextField("URL", text: $url)
    ///     .textContentType(.URL)
    /// ```
    public var textContentType: TextContentType? {
        get { self[TextContentTypeKey.self] }
        set { self[TextContentTypeKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Sets the text content type for text fields and editors within this
    /// view — mirrors SwiftUI's `textContentType(_:)`, whose
    /// `NSTextContentType` spellings `TextContentType` carries.
    ///
    /// There is no autofill in a terminal, so a content type is a filter:
    /// typed characters and pasted text are checked against the type's
    /// allowed character set, in a ``TextField``, a ``SecureField`` and a
    /// ``TextEditor`` alike, and a character that could not be part of a valid
    /// value is dropped with a ring of the terminal's bell — once for a paste,
    /// however many it drops. A line break is a character like any other: a
    /// vertical field or an editor whose content type cannot hold one takes
    /// none.
    ///
    /// ```swift
    /// TextField("URL", text: $url)
    ///     .textContentType(.URL)
    /// ```
    ///
    /// - Parameter type: The content type, or `nil` to disable filtering.
    /// - Returns: A view with the content type applied.
    public func textContentType(_ type: TextContentType?) -> some View {
        environment(\.textContentType, type)
    }
}
