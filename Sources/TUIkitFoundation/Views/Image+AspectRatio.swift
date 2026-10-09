//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+AspectRatio.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Environment Keys

/// Environment key for the image content mode.
private struct ImageContentModeKey: EnvironmentKey {
    static let defaultValue: ContentMode? = nil
}

/// Environment key for an explicit aspect ratio override.
private struct ImageAspectRatioKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    /// The content mode for image scaling: the one
    /// ``View/aspectRatio(_:contentMode:)`` set, or `.fit`.
    package var imageContentMode: ContentMode {
        get { self[ImageContentModeKey.self] ?? .fit }
        set { self[ImageContentModeKey.self] = newValue }
    }

    /// The content mode a modifier set, or `nil` where none did: a resizable
    /// image stretches to its frame unless one did — see
    /// ``Image/resizable(capInsets:resizingMode:)``.
    package var imageExplicitContentMode: ContentMode? {
        self[ImageContentModeKey.self]
    }

    /// An explicit aspect ratio override for images (width/height).
    ///
    /// When `nil`, the source image's natural aspect ratio is used.
    package var imageAspectRatio: Double? {
        get { self[ImageAspectRatioKey.self] }
        set { self[ImageAspectRatioKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {
    /// Sets the aspect ratio and content mode for image rendering.
    ///
    /// Use this modifier to control how images are scaled within their
    /// available space.
    ///
    /// ```swift
    /// // Use natural aspect ratio, fit within bounds
    /// Image(.file("photo.png"))
    ///     .aspectRatio(contentMode: .fit)
    ///
    /// // Force 16:9 ratio, fill bounds
    /// Image(.url("https://example.com/banner.png"))
    ///     .aspectRatio(16.0/9.0, contentMode: .fill)
    /// ```
    ///
    /// - Parameters:
    ///   - aspectRatio: The ratio of width to height to use for the
    ///     resulting view. Use `nil` to maintain the source image's
    ///     natural aspect ratio.
    ///   - contentMode: A flag that indicates whether this view fits or
    ///     fills the parent context.
    /// - Returns: A view that constrains this view's dimensions to the
    ///   given aspect ratio and content mode.
    public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
        environment(\.imageContentMode, contentMode)
            .environment(\.imageAspectRatio, aspectRatio)
    }

    /// Scales this view to fit within the parent while maintaining the
    /// aspect ratio.
    ///
    /// Equivalent to `.aspectRatio(contentMode: .fit)`.
    ///
    /// - Returns: A view that scales to fit.
    public func scaledToFit() -> some View {
        // This IS the modern spelling SwiftLint's rule points callers to; it is
        // defined in terms of the general modifier, so the rule's advice does
        // not apply to its own definition. The rule autocorrects, too: without
        // the disable below, `swiftlint --fix` rewrites the body into a call to
        // `scaledToFit()` itself, which does not compile — an opaque return
        // type with nothing to infer it from.
        // swiftlint:disable:next legacy_swiftui_aspect_ratio
        aspectRatio(contentMode: .fit)
    }

    /// Scales this view to fill the parent while maintaining the
    /// aspect ratio.
    ///
    /// Equivalent to `.aspectRatio(contentMode: .fill)`.
    ///
    /// - Returns: A view that scales to fill.
    public func scaledToFill() -> some View {
        // This IS the modern spelling SwiftLint's rule points callers to; it is
        // defined in terms of the general modifier, so the rule's advice does
        // not apply to its own definition. The rule autocorrects, too: without
        // the disable below, `swiftlint --fix` rewrites the body into a call to
        // `scaledToFill()` itself, which does not compile — an opaque return
        // type with nothing to infer it from.
        // swiftlint:disable:next legacy_swiftui_aspect_ratio
        aspectRatio(contentMode: .fill)
    }
}
