//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DeviceEnvironment.swift
//
//  The environment values that describe the device and the user's display
//  settings: scale, contrast, size class, type size, layout direction. A
//  terminal fixes most of them, and every default here is what SwiftUI itself
//  reports on macOS, read off a SwiftUI build (macOS 15.8, 2026-10-03) rather
//  than assumed.
//
//  Whether each one can be WRITTEN follows one rule: a write compiles only if
//  TUIkit honours it the way SwiftUI on macOS does. Where macOS's own views
//  ignore a write — a dynamic type size, a display scale, a size class — so do
//  TUIkit's, the value is a channel the app's own views can read, and it is
//  settable. Where macOS's views would change what they draw and TUIkit's
//  cannot yet — a right-to-left layout, a bolder legibility weight — the value
//  is read-only, so the write fails to compile instead of being ignored.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - The value types

/// The contrast the user has asked the colour scheme to have.
public enum ColorSchemeContrast: Hashable, CaseIterable, Sendable {
    /// SwiftUI's standard contrast.
    case standard

    /// The increased contrast an accessibility setting asks for.
    case increased
}

/// The font weight an accessibility setting asks text to be drawn at.
public enum LegibilityWeight: Hashable, Sendable {
    /// Text at its own weight.
    case regular

    /// Text a weight heavier than it asks for.
    case bold
}

/// The direction in which a layout runs.
public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    /// Left to right: leading is the left edge.
    case leftToRight

    /// Right to left: leading is the right edge.
    case rightToLeft
}

/// A set of values that indicate the visual size available to the view.
public enum UserInterfaceSizeClass: Hashable, Sendable {
    /// A constrained amount of space.
    case compact

    /// An expansive amount of space.
    case regular
}

/// A Dynamic Type size, the text size a user has asked for, smallest first.
public enum DynamicTypeSize: Hashable, Comparable, CaseIterable, Sendable {
    /// An extra small size.
    case xSmall
    /// A small size.
    case small
    /// A medium size.
    case medium
    /// A large size — the default.
    case large
    /// An extra large size.
    case xLarge
    /// An extra extra large size.
    case xxLarge
    /// An extra extra extra large size.
    case xxxLarge
    /// The first accessibility size.
    case accessibility1
    /// The second accessibility size.
    case accessibility2
    /// The third accessibility size.
    case accessibility3
    /// The fourth accessibility size.
    case accessibility4
    /// The fifth accessibility size.
    case accessibility5

    /// Whether this is one of the five accessibility sizes.
    public var isAccessibilitySize: Bool {
        self >= .accessibility1
    }

    /// The size's position from the smallest, for ordering.
    private var ordinal: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// The size in `range` closest to this one: this size if the range holds
    /// it, else the nearest bound.
    func clamped<R: RangeExpression>(to range: R) -> Self where R.Bound == Self {
        if range.contains(self) { return self }
        return Self.allCases.filter { range.contains($0) }
            .min { abs($0.ordinal - ordinal) < abs($1.ordinal - ordinal) } ?? self
    }
}

// MARK: - Keys

private struct DisplayScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct DynamicTypeSizeKey: EnvironmentKey {
    static let defaultValue = DynamicTypeSize.large
}

private struct HorizontalSizeClassKey: EnvironmentKey {
    static let defaultValue: UserInterfaceSizeClass? = .regular
}

private struct VerticalSizeClassKey: EnvironmentKey {
    static let defaultValue: UserInterfaceSizeClass? = .regular
}

private struct LuminanceReducedKey: EnvironmentKey {
    static let defaultValue = false
}

// MARK: - The values

extension EnvironmentValues {
    /// The contrast of the colour scheme: always ``ColorSchemeContrast/standard``.
    ///
    /// A terminal reports no contrast setting, and macOS's answer under the
    /// default setting is the same. Read-only, as in SwiftUI.
    public var colorSchemeContrast: ColorSchemeContrast { .standard }

    /// The display scale, `1` unless something sets it.
    ///
    /// A cell is TUIkit's unit and there are no points to scale, so nothing
    /// TUIkit draws reads this — which is also what SwiftUI on macOS does with a
    /// written scale for text. It is settable so an app's own views can be told
    /// one.
    public var displayScale: CGFloat {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }

    /// The size of the smallest thing the screen can draw: one cell.
    ///
    /// `Int`, because it is a measurement and TUIkit measures in whole cells
    /// (§2.1 of the compatibility doc) — so `.frame(height: pixelLength)`, the
    /// hairline idiom, draws a one-row line. Read-only, as in SwiftUI.
    public var pixelLength: Int { 1 }

    /// The Dynamic Type size, ``DynamicTypeSize/large`` unless something sets it.
    ///
    /// The terminal owns the font, so no size changes how TUIkit draws text —
    /// and SwiftUI on macOS ignores it for text too (measured: a `.body` text
    /// under `.accessibility5` is the width it is under `.xSmall`). It is
    /// settable, and ``View/dynamicTypeSize(_:)-(DynamicTypeSize)`` sets it, for
    /// an app's own views to read.
    public var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }

    /// The horizontal size class, ``UserInterfaceSizeClass/regular`` unless
    /// something sets it — macOS's answer for any window.
    public var horizontalSizeClass: UserInterfaceSizeClass? {
        get { self[HorizontalSizeClassKey.self] }
        set { self[HorizontalSizeClassKey.self] = newValue }
    }

    /// The vertical size class, ``UserInterfaceSizeClass/regular`` unless
    /// something sets it — macOS's answer for any window.
    public var verticalSizeClass: UserInterfaceSizeClass? {
        get { self[VerticalSizeClassKey.self] }
        set { self[VerticalSizeClassKey.self] = newValue }
    }

    /// Whether the display is dimmed to save power, as an always-on display is.
    ///
    /// `false` unless something sets it: a terminal is never dimmed by the
    /// system, and nothing TUIkit draws changes under it — nor does anything
    /// SwiftUI draws on macOS.
    public var isLuminanceReduced: Bool {
        get { self[LuminanceReducedKey.self] }
        set { self[LuminanceReducedKey.self] = newValue }
    }

    /// Whether the system will ask the device's owner to authenticate before
    /// revealing content from behind a system shield: `false`, as on macOS —
    /// a terminal has no such shield. Read-only, as in SwiftUI.
    public var isUserAuthenticationEnabled: Bool { false }

    /// The direction layouts run: always ``LayoutDirection/leftToRight``.
    ///
    /// Read-only, where SwiftUI's is settable: SwiftUI's stacks, alignments and
    /// insets mirror under a right-to-left direction, and TUIkit's do not yet,
    /// so a write would be accepted and ignored. Leaving the setter out makes it
    /// a compile error instead.
    public var layoutDirection: LayoutDirection { .leftToRight }

    /// The weight the user has asked text to be drawn at: always `nil`, meaning
    /// no preference — macOS's answer under the default setting.
    ///
    /// Read-only, where SwiftUI's is settable: SwiftUI draws all of its text a
    /// weight heavier under ``LegibilityWeight/bold``, control labels included,
    /// and TUIkit does not yet, so a write would be accepted and ignored.
    public var legibilityWeight: LegibilityWeight? { nil }

    /// Whether this device can present a remote immersive space: `false`.
    /// Read-only, as in SwiftUI.
    public var supportsRemoteScenes: Bool { false }
}

// MARK: - Modifiers

extension View {
    /// Sets the Dynamic Type size for this view's subtree.
    ///
    /// Nothing TUIkit draws changes with it — the terminal owns the font — just
    /// as SwiftUI's text on macOS does not; views that read
    /// ``EnvironmentValues/dynamicTypeSize`` see it.
    ///
    /// - Parameter size: The size to set.
    /// - Returns: A view with the size set.
    public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View {
        environment(\.dynamicTypeSize, size)
    }

    /// Limits the Dynamic Type size for this view's subtree to a range.
    ///
    /// A size outside the range becomes the nearest size inside it, as in
    /// SwiftUI: under `...DynamicTypeSize.small`, a subtree that would have
    /// been ``DynamicTypeSize/large`` reads ``DynamicTypeSize/small``.
    ///
    /// - Parameter range: The sizes the subtree may have.
    /// - Returns: A view with the size limited to `range`.
    public func dynamicTypeSize<T: RangeExpression>(_ range: T) -> some View
    where T.Bound == DynamicTypeSize {
        transformEnvironment(\.dynamicTypeSize) { $0 = $0.clamped(to: range) }
    }
}
