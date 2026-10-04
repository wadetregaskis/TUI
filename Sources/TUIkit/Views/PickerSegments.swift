//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerSegments.swift
//
//  The segmented and palette picker styles: the options side by side, as
//  buttons that touch, the selected one marked.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Styles

/// A picker style that presents the options in a segmented control: side by
/// side and touching, the selected one drawn prominent.
///
/// Each segment is a button, so each is a focus stop: Tab walks them and
/// Return or Space picks one, as does a click. (SwiftUI's segmented control is
/// one stop whose segments the arrows walk; decisions B13.)
public struct SegmentedPickerStyle: PickerStyle, Equatable {
    /// Creates a segmented picker style.
    public init() {}
}

/// A picker style that presents the options as a row of compact elements.
///
/// Laid out as the segmented style is, with the selected option marked as
/// ``View/paletteSelectionEffect(_:)`` says.
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

    /// The default selection appearance: the selected item drawn prominent.
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
    /// `.automatic` draws the selected item prominent; `.custom` draws no
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

// MARK: - The strip

/// The options as buttons side by side and touching, the selected one drawn
/// prominent — unless a palette's selection effect says otherwise.
struct _PickerSegments<SelectionValue: Hashable>: View {
    let entries: [_PickerEntry<SelectionValue>]
    let selection: Binding<SelectionValue>
    let isPalette: Bool
    var isMixed = false

    @Environment(\.paletteSelectionEffect) private var effect

    var body: some View {
        // A segmented control has no dividers, which are a menu's.
        let options = entries.compactMap { entry -> (tag: SelectionValue, label: AnyView)? in
            guard case .option(let tag, let label) = entry else { return nil }
            return (tag, label)
        }
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(tag: options[index].tag, label: options[index].label)
            }
        }
    }

    /// One option: a button that selects it.
    @ViewBuilder
    private func segment(tag: SelectionValue, label: AnyView) -> some View {
        let isSelected = !isMixed && tag == selection.wrappedValue
        let marks = !isPalette || effect.drawsSelection
        let button = Button {
            selection.wrappedValue = tag
        } label: {
            if isPalette, isSelected, let variant = effect.selectedVariant {
                label.symbolVariant(variant)
            } else {
                label
            }
        }
        if isSelected, marks {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

// MARK: - Environment without reflection

extension _PickerSegments: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _effect.resolveEnvironment(environment)
    }
}
