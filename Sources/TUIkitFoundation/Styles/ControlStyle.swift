//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlStyle.swift
//
//  How controls' chrome is drawn, apart from how boxes are bordered: the
//  second axis beside `Appearance` (owner, 2026-10-23: Block the default
//  control style, Rounded the default border style).
//
//  Created by Wade Tregaskis
//  License: MIT

/// How a control's chrome is drawn — a bordered button's face, a pop-up
/// picker's closed control, a combo box, a text field's caps — apart from
/// how boxes are bordered, which ``Appearance`` says.
///
/// TUI-specific. SwiftUI's controls take their look from the platform; in a
/// terminal TUIkit draws them, in one of a few families of glyphs, and an
/// app may want its boxes in one and its controls in another — rounded
/// borders around filled buttons, the default.
///
/// ```swift
/// ContentView()
///     .controlStyle(.lines)   // buttons in the border's own lines
/// ```
public enum ControlStyle: Hashable, Sendable {
    /// Filled faces, unless the appearance draws its borders in Braille dots
    /// or not at all, whose controls follow it (``Appearance/braille`` and
    /// ``Appearance/blank`` are looks of the whole interface). **The
    /// default.**
    case automatic

    /// Filled faces: a band of colour with the label on it, quadrant-cornered
    /// on three rows where the terminal draws Block Elements the full line.
    case block

    /// Faces of lines, in the glyphs of the appearance's border — rounded
    /// under ``Appearance/rounded``, heavy under ``Appearance/heavy`` — and
    /// rounded lines where the appearance's border is not drawn in lines.
    case lines

    /// Dotted outlines, `thickness` Braille dots thick (1 to 4).
    case braille(thickness: Int)

    /// The label alone, with no chrome.
    case blank

    /// One-dot Braille outlines.
    public static var braille: Self { .braille(thickness: 1) }
}

// MARK: - Environment

private struct ControlStyleKey: EnvironmentKey {
    static let defaultValue = ControlStyle.automatic
}

extension EnvironmentValues {
    /// How controls' chrome is drawn in this subtree — see
    /// ``View/controlStyle(_:)``.
    public var controlStyle: ControlStyle {
        get { self[ControlStyleKey.self] }
        set { self[ControlStyleKey.self] = newValue }
    }

    /// Whether the glass drawn here is a control's — a glass button's — whose
    /// rim is the control's face and so takes the ``controlStyle``; any other
    /// glass is a surface, rimmed in the appearance's border as a box is.
    var glassIsAControl: Bool {
        get { self[GlassIsAControlKey.self] }
        set { self[GlassIsAControlKey.self] = newValue }
    }
}

private struct GlassIsAControlKey: EnvironmentKey {
    static let defaultValue = false
}

extension View {
    /// Sets how every control in this view's subtree draws its chrome:
    /// filled, in lines, in Braille dots or not at all, whatever the boxes
    /// around it are bordered in.
    ///
    /// TUI-specific: SwiftUI's controls take their look from the platform.
    ///
    /// - Parameter style: The control style.
    /// - Returns: A view whose controls draw in `style`.
    public func controlStyle(_ style: ControlStyle) -> some View {
        environment(\.controlStyle, style)
    }
}
