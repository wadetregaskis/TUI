//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerStyle+Variants.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A picker style that collapses to a single line and opens a drop-down
/// list of options when activated.
///
/// `Equatable` on the same terms as ``AutomaticPickerStyle``, and this is the
/// half that earns the cross-type comparison: replacing it with an inline style
/// turns one line into a row per option, so the swap must read as a change.
public struct MenuPickerStyle: PickerStyle, Equatable {
    /// Creates a menu picker style.
    public init() {}
}

/// A picker style that presents the options inline as a selectable list.
///
/// > Note: In TUIkit this renders identically to ``RadioGroupPickerStyle``.
///
/// `Equatable` on the same terms as ``AutomaticPickerStyle``. Note that the
/// identical rendering does not make it compare equal to
/// ``RadioGroupPickerStyle`` — see ``PickerStyle``.
public struct InlinePickerStyle: PickerStyle, Equatable {
    /// Creates an inline picker style.
    public init() {}
}

/// A picker style that presents the options as a radio-button group.
///
/// `Equatable` on the same terms as ``AutomaticPickerStyle``.
public struct RadioGroupPickerStyle: PickerStyle, Equatable {
    /// Creates a radio-group picker style.
    public init() {}
}

// MARK: - PickerStyle Static Accessors

extension PickerStyle where Self == AutomaticPickerStyle {
    /// The default picker style — a drop-down menu in TUIkit.
    public static var automatic: AutomaticPickerStyle { AutomaticPickerStyle() }
}

extension PickerStyle where Self == MenuPickerStyle {
    /// A picker style that opens a drop-down list of options.
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}

extension PickerStyle where Self == InlinePickerStyle {
    /// A picker style that presents the options inline as a list.
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}

extension PickerStyle where Self == RadioGroupPickerStyle {
    /// A picker style that presents the options as a radio-button group.
    public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() }
}

// MARK: - PickerStyle Resolution

extension PickerStyle {
    /// Whether this style should render as a collapsing drop-down menu.
    ///
    /// ``AutomaticPickerStyle`` and ``MenuPickerStyle`` resolve to the menu
    /// presentation; ``InlinePickerStyle`` and ``RadioGroupPickerStyle``
    /// resolve to the inline radio list.
    var resolvesToMenu: Bool {
        self is MenuPickerStyle || self is AutomaticPickerStyle
    }
}

// MARK: - Picker Style Modifier

extension View {
    /// Sets the style for pickers within this view.
    ///
    /// ```swift
    /// Picker("Theme", selection: $theme) {
    ///     Text("Light").tag(Theme.light)
    ///     Text("Dark").tag(Theme.dark)
    /// }
    /// .pickerStyle(.radioGroup)
    /// ```
    ///
    /// - Parameter style: The picker style to apply.
    /// - Returns: A view whose pickers use the specified style.
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        environment(\.pickerStyle, style)
    }
}

// MARK: - Radio group layout

private struct HorizontalRadioGroupLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether radio-group pickers below lay their options out in a row —
    /// what ``View/horizontalRadioGroupLayout()`` sets.
    var horizontalRadioGroupLayout: Bool {
        get { self[HorizontalRadioGroupLayoutKey.self] }
        set { self[HorizontalRadioGroupLayoutKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for radio group style pickers within this view to be
    /// horizontally positioned with the radio buttons inside the layout.
    ///
    /// ```swift
    /// Picker("Size", selection: $size) {
    ///     Text("S").tag(Size.small)
    ///     Text("M").tag(Size.medium)
    ///     Text("L").tag(Size.large)
    /// }
    /// .pickerStyle(.radioGroup)
    /// .horizontalRadioGroupLayout()
    /// // Size  (•) S  ( ) M  ( ) L
    /// ```
    ///
    /// Left and Right then walk the options, as in any horizontal radio group.
    ///
    /// - Returns: A view whose radio-group pickers lay out in a row.
    public func horizontalRadioGroupLayout() -> some View {
        environment(\.horizontalRadioGroupLayout, true)
    }
}
