//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalProgressModifier.swift
//
//  A progress report the terminal draws itself, on its tab, its window or its
//  pane: `.terminalProgress(_:)`, sent as ConEmu's `OSC 9 ; 4`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TerminalProgress

/// How far along the app's work is, for the terminal to show beside the app's
/// own cells: a bar on its tab, its window or its pane, where the person sees
/// it from another tab or window too.
///
/// TUI-specific: SwiftUI has no counterpart, the nearest being a Dock tile's
/// progress, which AppKit draws and SwiftUI does not reach. A view states one
/// with ``View/terminalProgress(_:)``.
public enum TerminalProgress: Hashable, Sendable {
    /// The work is the fraction `fraction` done, from `0` (none of it) to `1`
    /// (all of it), as ``ProgressView``'s `value` is with its default total.
    /// The terminal is told whole percents, so a fraction outside `0...1` is
    /// clamped and the rest rounded.
    case value(Double)

    /// The work is under way, with no known extent.
    case indeterminate

    /// The work has failed: at `fraction` done, or, for `nil`, wherever the
    /// terminal's bar already stood.
    case error(Double?)

    /// The work is held up: at `fraction` done, or, for `nil`, wherever the
    /// terminal's bar already stood.
    case paused(Double?)
}

// MARK: - Preference Key

/// The progress the views drawn this frame state, for the run loop to send:
/// the last one drawn wins, and `nil` — a view stating none — leaves another
/// view's standing.
package struct TerminalProgressKey: PreferenceKey {
    package static let defaultValue: TerminalProgress? = nil

    package static func reduce(value: inout TerminalProgress?, nextValue: () -> TerminalProgress?) {
        if let next = nextValue() { value = next }
    }
}

// MARK: - View Modifier

extension View {
    /// Shows `progress` as a bar the terminal draws on its tab, its window or
    /// its pane, while this view is drawn; `nil` states none.
    ///
    /// ```swift
    /// List(files) { file in FileRow(file) }
    ///     .terminalProgress(isCopying ? .value(copied / total) : nil)
    /// ```
    ///
    /// The terminal draws it outside the app's cells, so it is seen from other
    /// tabs and windows as well: Ghostty and iTerm2 draw it, and tmux passes
    /// it on to a client it gives the `progressbar` feature (iTerm2, not
    /// Ghostty, Apple Terminal or Warp, unless the user says so). Where the
    /// person sees no bar — elsewhere nothing is sent —
    /// ``EnvironmentValues/terminalCapabilities``' ``TerminalCapabilities/Feature/progressReports``
    /// is not supported, so an app can draw its own instead.
    ///
    /// Where several views drawn at once state progress, the last one drawn
    /// wins: the innermost of nested views, the last of siblings. The app's
    /// bar goes when no view drawn states one any more, when it is suspended,
    /// and when it quits.
    ///
    /// TUI-specific, with no SwiftUI counterpart: sent as ConEmu's progress
    /// report, `OSC 9 ; 4`, on a change, and again every five seconds while it
    /// is shown, because Ghostty takes a bar no program has updated for about
    /// fifteen seconds for one left behind and removes it — but not to tmux,
    /// which keeps the bar itself. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "Progress
    /// and attention".
    ///
    /// - Parameter progress: How far along the work is, or `nil` for no bar.
    /// - Returns: A view that states `progress` for the terminal while it is
    ///   drawn.
    public func terminalProgress(_ progress: TerminalProgress?) -> some View {
        preference(key: TerminalProgressKey.self, value: progress)
    }
}
