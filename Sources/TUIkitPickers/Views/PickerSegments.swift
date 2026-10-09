//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerSegments.swift
//
//  The segmented and palette picker styles, and a palette's selection
//  effect. `_PickerSegmentsCore` draws them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Styles

/// A picker style that presents the options in a segmented control: one face,
/// `▐ S │ M │ L ▌`, the selected option drawn in the accent.
///
/// The control is one focus stop, as macOS's is. Left and Right move a cursor
/// among the segments without choosing, wrapping at the ends; Space chooses the
/// segment under it, as does a click (measured on macOS 15.8). Return chooses
/// too, as it does in a radio group — on macOS it does nothing.
public struct SegmentedPickerStyle: PickerStyle, Equatable {
    /// Creates a segmented picker style.
    public init() {}
}

/// A picker style that presents the options as a row of compact elements.
///
/// Drawn and keyed as the segmented style is, with the selected option marked
/// as ``View/paletteSelectionEffect(_:)`` says.
public struct PalettePickerStyle: PickerStyle, Equatable {
    /// Creates a palette picker style.
    public init() {}
}

extension PickerStyle where Self == SegmentedPickerStyle {
    /// A picker style that presents the options in a segmented control.
    public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() }
}

extension PickerStyle where Self == PalettePickerStyle {
    /// A picker style that presents the options as a row of compact elements.
    public static var palette: PalettePickerStyle { PalettePickerStyle() }
}

extension PickerStyle {
    /// Whether this style lays the options out side by side as segments.
    var resolvesToSegments: Bool {
        self is SegmentedPickerStyle || self is PalettePickerStyle
    }
}

// MARK: - Selection effect

/// The selection effect to apply to a palette item.
public struct PaletteSelectionEffect: Equatable, Sendable {
    private enum Kind: Equatable, Sendable {
        case automatic
        case custom
        case symbolVariant(SymbolVariants)
    }

    private let kind: Kind

    /// The default selection appearance: the selected item drawn in the accent.
    public static let automatic = Self(kind: .automatic)

    /// No selection appearance of the picker's own: the items' content is all
    /// that shows which is selected.
    public static let custom = Self(kind: .custom)

    /// The selected item's SF Symbols drawn in `variant` — `.fill`, say — and
    /// no other selection appearance.
    ///
    /// - Parameter variant: The symbol variant for the selected item.
    /// - Returns: The selection effect.
    public static func symbolVariant(_ variant: SymbolVariants) -> Self {
        Self(kind: .symbolVariant(variant))
    }

    /// Whether the picker draws the selected item prominent.
    var drawsSelection: Bool { kind == .automatic }

    /// The symbol variant the selected item takes, if any.
    var selectedVariant: SymbolVariants? {
        if case .symbolVariant(let variant) = kind { return variant }
        return nil
    }
}

private struct PaletteSelectionEffectKey: EnvironmentKey {
    static let defaultValue = PaletteSelectionEffect.automatic
}

extension EnvironmentValues {
    /// The palette pickers' selection effect — see
    /// ``View/paletteSelectionEffect(_:)``.
    var paletteSelectionEffect: PaletteSelectionEffect {
        get { self[PaletteSelectionEffectKey.self] }
        set { self[PaletteSelectionEffectKey.self] = newValue }
    }
}

extension View {
    /// Specifies the selection effect to apply to a palette item.
    ///
    /// `.automatic` draws the selected item in the accent; `.custom` draws no
    /// selection of its own, leaving the items' content to show it; and
    /// `.symbolVariant(_:)` draws the selected item's symbols in that variant
    /// instead.
    ///
    /// - Parameter effect: The selection effect.
    /// - Returns: A view whose palette pickers use `effect`.
    public func paletteSelectionEffect(_ effect: PaletteSelectionEffect) -> some View {
        environment(\.paletteSelectionEffect, effect)
    }
}
