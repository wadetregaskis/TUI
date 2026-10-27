//  🖥️ TUI — A Terminal UI framework for Swift
//  AccessibilityDisplayPreferences.swift
//
//  `\.accessibilityReduceTransparency` and `\.accessibilityDifferentiateWithoutColor`
//  (owner ruling P5 (c), 2026-10-23): read as `\.accessibilityReduceMotion` is
//  — the user's `TUI_*` variable, or the host's own setting where TUI is
//  sure the user is at this machine — and written at the root by the app
//  runner. `\.colorSchemeContrast`, the third, is with the device values
//  (`DeviceEnvironment.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

private struct AccessibilityReduceTransparencyKey: EnvironmentKey {
    // `false`, and not read from the process environment: a key's default must
    // not depend on where a test runs. The render loop writes the user's
    // answer at the root.
    static let defaultValue = false
}

private struct AccessibilityDifferentiateWithoutColorKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the system preference for Reduce Transparency is enabled —
    /// mirrors SwiftUI's `accessibilityReduceTransparency`.
    ///
    /// If it is `true`, a view should draw without translucency. TUI's
    /// materials, and the glass made of them, are drawn opaque, as one that
    /// does not appear active already is.
    ///
    /// `true` when the user set `TUI_REDUCE_TRANSPARENCY=1` in the
    /// environment the app runs in, or when macOS's Reduce transparency is on
    /// where TUI is sure the user is at this machine, as for
    /// ``accessibilityReduceMotion``: read at launch and whenever the terminal
    /// regains the focus. GNOME has no such setting. Read-only, as SwiftUI's
    /// is; `_accessibilityReduceTransparency` writes it, as SwiftUI's does.
    public package(set) var accessibilityReduceTransparency: Bool {
        get { self[AccessibilityReduceTransparencyKey.self] }
        set { self[AccessibilityReduceTransparencyKey.self] = newValue }
    }

    /// ``accessibilityReduceTransparency``, writable — SwiftUI's
    /// `_accessibilityReduceTransparency`, for `.environment(_:_:)` in a preview
    /// or a test.
    public var _accessibilityReduceTransparency: Bool {
        get { accessibilityReduceTransparency }
        set { accessibilityReduceTransparency = newValue }
    }

    /// Whether the system preference for Differentiate without Color is
    /// enabled — mirrors SwiftUI's `accessibilityDifferentiateWithoutColor`.
    ///
    /// If it is `true`, a view should not convey information by colour alone.
    /// TUI reads it for your views; its own focus and selection cues do not
    /// change with it yet (they are designed apart, under the focus colour
    /// rules: owner ruling P5).
    ///
    /// `true` when the user set `TUI_DIFFERENTIATE_WITHOUT_COLOR=1` in the
    /// environment the app runs in, or when macOS's Differentiate without
    /// colour is on where TUI is sure the user is at this machine, as for
    /// ``accessibilityReduceMotion``. GNOME has no such setting. Read-only, as
    /// SwiftUI's is; `_accessibilityDifferentiateWithoutColor` writes it.
    public package(set) var accessibilityDifferentiateWithoutColor: Bool {
        get { self[AccessibilityDifferentiateWithoutColorKey.self] }
        set { self[AccessibilityDifferentiateWithoutColorKey.self] = newValue }
    }

    /// ``accessibilityDifferentiateWithoutColor``, writable — SwiftUI's
    /// `_accessibilityDifferentiateWithoutColor`.
    public var _accessibilityDifferentiateWithoutColor: Bool {
        get { accessibilityDifferentiateWithoutColor }
        set { accessibilityDifferentiateWithoutColor = newValue }
    }
}
