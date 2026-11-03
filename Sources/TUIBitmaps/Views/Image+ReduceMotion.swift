//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+ReduceMotion.swift
//
//  Whether an animated picture holds still under Reduce Motion, which depends on
//  what the picture is to the app: TUI-specific, as SwiftUI's `Image` never plays.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

private struct ImageAnimationRespectsReduceMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether an animated ``Image`` shows its first frame, still, under Reduce
    /// Motion. Set via ``View/imageAnimationRespectsReduceMotion(_:)``. Default:
    /// `true`.
    public var imageAnimationRespectsReduceMotion: Bool {
        get { self[ImageAnimationRespectsReduceMotionKey.self] }
        set { self[ImageAnimationRespectsReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// Sets whether animated ``Image`` views within this view hold still when
    /// ``EnvironmentValues/accessibilityReduceMotion`` is on.
    ///
    /// By default they do, showing their first frame. Which is right depends on
    /// what the picture is to the app:
    ///
    /// - **Chrome** (a mascot, a decorative banner, a logo that waves) probably
    ///   should hold still. Nobody came for it, and the setting exists to stop
    ///   motion nobody asked for. Leave this as it is.
    /// - **Content** (the GIF in a message, the file a viewer was opened on)
    ///   probably should play regardless, because playing is what it is for, and
    ///   the first frame of a GIF may not say what the GIF says.
    ///
    /// ```swift
    /// Image(.file(attachment.path))
    ///     .imageAnimationRespectsReduceMotion(false)   // the user opened this
    /// ```
    ///
    /// This decides nothing else about the picture: it still stops when it is
    /// scrolled out of view, and it changes no other view's response to Reduce
    /// Motion. To decide by the setting yourself, read
    /// ``EnvironmentValues/accessibilityReduceMotion``.
    ///
    /// - Parameter respects: Whether images hold still under Reduce Motion
    ///   (default `true`).
    /// - Returns: A view whose animated images honour the setting.
    nonisolated public func imageAnimationRespectsReduceMotion(_ respects: Bool = true) -> some View {
        environment(\.imageAnimationRespectsReduceMotion, respects)
    }
}
