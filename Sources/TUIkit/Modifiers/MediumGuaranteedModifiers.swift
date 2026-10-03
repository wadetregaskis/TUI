//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MediumGuaranteedModifiers.swift
//
//  SwiftUI modifiers whose GUARANTEE a character grid already provides.
//
//  These return `self`, and that is not a stub. A stub accepts a request the
//  medium cannot meet and quietly drops it — TUIkit removes those instead, so
//  the call fails to compile and the gap is the developer's to decide about
//  (`.submitLabel` was one, deleted for exactly that reason). These make a
//  promise the medium keeps: every cell is one column wide, so text is already
//  monospaced and digits are already tabular; nothing between the keyboard and
//  a `TextField`'s binding rewrites what was typed, so there is no
//  autocorrection to disable.
//
//  The distinction is directional, and worth stating because the argument is
//  ignored either way: `.monospaced(true)` is honoured — by the grid, for
//  free — while `.monospaced(false)` asks for proportional text, which no
//  terminal can give. The modifier survives because its default and its
//  overwhelmingly common spelling are the satisfiable ones; deleting it to
//  reject `false` would reject the honoured case too.
//
//  The `View` overloads below are a different symbol from `Text`'s own
//  `monospaced`/`monospacedDigit`, and a `Text` receiver always binds `Text`'s —
//  so a test that wants THESE has to call them on some other view, which
//  `MediumGuaranteedModifierTests` does. Each is covered by a test that asserts the GUARANTEE — equal cell widths
//  for equal character counts, a misspelling arriving intact — rather than
//  asserting the no-op, which would prove nothing and would keep passing if
//  the medium ever stopped holding up its end.
//
//  Created by Wade Tregaskis
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Renders this view's text with a monospaced font — mirrors SwiftUI's
    /// `monospaced(_:)`.
    ///
    /// Already true, and not by choice: a terminal draws into a grid of equal
    /// cells, so every glyph advances the same distance. The modifier exists so
    /// SwiftUI source compiles and expresses the same intent; it has nothing to
    /// change.
    ///
    /// - Parameter isActive: Ignored — the guarantee holds either way. A
    ///   terminal cannot render *proportionally*, so `false` cannot mean what
    ///   it means in SwiftUI.
    /// - Returns: This view, unchanged.
    public func monospaced(_ isActive: Bool = true) -> some View {
        self
    }

    /// Renders digits with uniform width — mirrors SwiftUI's
    /// `monospacedDigit()`.
    ///
    /// SwiftUI needs this because a proportional font gives `1` and `8`
    /// different widths, so a changing number jitters. In a cell grid they are
    /// one cell each already, which is why a `ProgressView`'s percentage or a
    /// `Table`'s numeric column has never had to ask.
    ///
    /// - Returns: This view, unchanged.
    public func monospacedDigit() -> some View {
        self
    }

    /// Sets the font design of the text in this view — mirrors SwiftUI's
    /// `fontDesign(_:)`.
    ///
    /// Both designs ``Font/Design`` offers are the terminal's own face, so
    /// either is already in force, and `nil` asks for the default, which it
    /// is.
    ///
    /// - Parameter design: The font design, or `nil` for the default.
    /// - Returns: This view, unchanged.
    public func fontDesign(_ design: Font.Design?) -> some View {
        self
    }

    /// Disables autocorrection for text input in this view — mirrors SwiftUI's
    /// `autocorrectionDisabled(_:)`.
    ///
    /// There is none to disable. Nothing between the key event and the
    /// binding rewrites what was typed: TUIkit has no autocorrection,
    /// autocapitalisation or spell-check, and a terminal supplies none either.
    /// A field holds exactly the characters that arrived.
    ///
    /// It still records what was asked in ``EnvironmentValues/autocorrectionDisabled``,
    /// as SwiftUI's does, for an app's own views to read.
    ///
    /// - Parameter disable: Recorded, and otherwise moot — text is never
    ///   corrected, so `false` cannot turn a correction back on.
    /// - Returns: This view, with the request recorded in its environment.
    public func autocorrectionDisabled(_ disable: Bool = true) -> some View {
        environment(\.autocorrectionDisabled, disable)
    }

    /// Isolates the geometry — position and size — of this view from its
    /// parent — mirrors SwiftUI's `geometryGroup()`.
    ///
    /// SwiftUI needs this because each of its leaves animates its own frame, so
    /// a view inserted mid-animation can fly in from somewhere unrelated to its
    /// parent. TUIkit never interpolates a leaf's frame: an animation drives a
    /// modifier's VALUE (padding, frame, offset — `AnimatableGeometry`), and the
    /// whole tree is laid out again from it every tick, so a parent's children
    /// move locked to it already.
    ///
    /// - Returns: This view, unchanged.
    public func geometryGroup() -> some View {
        self
    }

    /// Offsets this view off its container's corner insets — mirrors SwiftUI's
    /// `containerCornerOffset(_:sizeToFit:)`.
    ///
    /// A container's corner insets are the areas its corners take from the
    /// content: window controls, rounded corners. Here they are zero, and truly
    /// so — a corner glyph sits in a border cell, never in the content area, and
    /// window chrome is taken off the content area before anything is laid out
    /// — so there is nothing to offset by, on any edge.
    ///
    /// - Parameters:
    ///   - edges: The edges to offset from. Moot: every inset is zero.
    ///   - sizeToFit: Whether to shrink rather than move. Moot likewise.
    /// - Returns: This view, unchanged.
    public func containerCornerOffset(_ edges: Edge.Set, sizeToFit: Bool = false) -> some View {
        self
    }

    /// Sets whether this view mirrors its contents horizontally when the layout
    /// direction is right-to-left — mirrors SwiftUI's
    /// `flipsForRightToLeftLayoutDirection(_:)`.
    ///
    /// The layout direction is always left-to-right here
    /// (``EnvironmentValues/layoutDirection`` is read-only until TUIkit supports
    /// right-to-left), and in a left-to-right layout SwiftUI leaves the view
    /// alone too — measured, `true` draws identically to no modifier. When
    /// right-to-left lands, this must mirror.
    ///
    /// - Parameter enabled: Whether to mirror in a right-to-left layout.
    /// - Returns: This view, unchanged.
    public func flipsForRightToLeftLayoutDirection(_ enabled: Bool) -> some View {
        self
    }

    /// Flashes the scroll indicators of the scrollable views in this hierarchy
    /// when they first appear — mirrors SwiftUI's
    /// `scrollIndicatorsFlash(onAppear:)`.
    ///
    /// A flash exists because an overlay scroller is hidden until something
    /// scrolls, so a person cannot otherwise tell the content goes on. A
    /// terminal's indicators are not overlays: a scroll view whose content
    /// overflows draws its bar, or its "N more" lines, on its first frame and on
    /// every frame after, as macOS's legacy scrollers are. SwiftUI flashes only
    /// the indicators configured to be visible; those are the ones drawn here,
    /// and they are already in view.
    ///
    /// - Parameter onAppear: Whether to flash on appearing. Moot: they show.
    /// - Returns: This view, unchanged.
    public func scrollIndicatorsFlash(onAppear: Bool) -> some View {
        self
    }

    /// Flashes the scroll indicators of the scrollable views in this hierarchy
    /// when `value` changes — mirrors SwiftUI's `scrollIndicatorsFlash(trigger:)`.
    ///
    /// Already shown, for the reason ``scrollIndicatorsFlash(onAppear:)`` gives.
    ///
    /// - Parameter value: The value whose change asks for a flash.
    /// - Returns: This view, unchanged.
    public func scrollIndicatorsFlash(trigger value: some Equatable) -> some View {
        self
    }
}

// MARK: - Autocorrection, as an environment value

private struct AutocorrectionDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether autocorrection has been disabled for this subtree — what
    /// ``View/autocorrectionDisabled(_:)`` last said, `false` by default.
    ///
    /// TUIkit never corrects text either way (see the modifier), so this is a
    /// record of the request, which SwiftUI's environment also carries.
    public var autocorrectionDisabled: Bool {
        get { self[AutocorrectionDisabledKey.self] }
        set { self[AutocorrectionDisabledKey.self] = newValue }
    }
}
