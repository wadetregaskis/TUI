//  🖥️ TUI — A Terminal UI framework for Swift
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
    /// Constrains this view's dimensions to the given aspect ratio.
    ///
    /// Offers the view the largest size of the ratio that fits what this is
    /// offered (`.fit`), or the smallest that covers it (`.fill`), and takes
    /// what the view makes of it — as SwiftUI does, for any view:
    ///
    /// ```swift
    /// Color.blue.aspectRatio(16.0 / 9.0, contentMode: .fit)
    ///
    /// Image(.file("photo.png"))
    ///     .resizable()
    ///     .scaledToFit()
    /// ```
    ///
    /// The ratio is width over height in points, as SwiftUI's is; a cell is
    /// taller than it is wide (``EnvironmentValues/imageCellAspect``), so a
    /// square is about twice as many columns as rows. With `nil`, the view's own
    /// ideal size gives the ratio — an image's, its picture's. A view that does
    /// not take what it is offered, such as `Text`, keeps its size. A terminal
    /// has nothing outside a view to draw into, so a fill larger than its space
    /// is cut to it, centred, rather than drawn past it.
    ///
    /// - Parameters:
    ///   - aspectRatio: The ratio of width to height to use for the resulting
    ///     view, or `nil` to keep the view's own.
    ///   - contentMode: Whether this view fits or fills the space it is
    ///     offered.
    /// - Returns: A view that constrains this view's dimensions to the given
    ///   aspect ratio and content mode.
    nonisolated public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
        // A ratio that is not a positive number is none; one finite but past
        // what a box of cells can show — 1e-300, 1e18 — is held to one cell
        // by `Int.statedLengthLimit`. Unheld, it reached the image inside as
        // a height no conversion could take.
        let limit = Double(Int.statedLengthLimit)
        let aspectRatio = aspectRatio.flatMap { $0.isFinite && $0 > 0 ? min(max($0, 1 / limit), limit) : nil }
        // The layout is SwiftUI's, for any view (`_AspectRatioView`). The
        // environment still tells an image inside how it fills the box it is
        // given: a resizable image stretches unless a content mode is set.
        return _AspectRatioView(content: self, aspectRatio: aspectRatio, contentMode: contentMode)
            .environment(\.imageContentMode, contentMode)
            .environment(\.imageAspectRatio, aspectRatio)
    }

    /// Scales this view to fit within the space it is offered, keeping its
    /// own aspect ratio.
    ///
    /// Equivalent to `.aspectRatio(contentMode: .fit)`.
    ///
    /// - Returns: A view that scales to fit.
    nonisolated public func scaledToFit() -> some View {
        // This IS the modern spelling SwiftLint's rule points callers to; it is
        // defined in terms of the general modifier, so the rule's advice does
        // not apply to its own definition. The rule autocorrects, too: without
        // the disable below, `swiftlint --fix` rewrites the body into a call to
        // `scaledToFit()` itself, which does not compile — an opaque return
        // type with nothing to infer it from.
        // swiftlint:disable:next legacy_swiftui_aspect_ratio
        aspectRatio(contentMode: .fit)
    }

    /// Scales this view to fill the space it is offered, keeping its own
    /// aspect ratio; what lies past that space is cut to it.
    ///
    /// Equivalent to `.aspectRatio(contentMode: .fill)`.
    ///
    /// - Returns: A view that scales to fill.
    nonisolated public func scaledToFill() -> some View {
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
