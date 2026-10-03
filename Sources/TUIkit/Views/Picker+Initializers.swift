//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Picker+Initializers.swift
//
//  SwiftUI's Picker initialisers that take a custom current-value label.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A current-value label

extension Picker {
    /// Creates a picker with a custom label, and a view the collapsed control
    /// shows as its current value.
    ///
    /// A menu-style picker shows `currentValueLabel` in place of the selected
    /// option's label; the inline and radio-group styles show every option,
    /// the current one marked, and do not use it.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - label: A view builder for the picker's label.
    ///   - currentValueLabel: A view builder for the current value's label.
    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(selection: selection, content: content, label: label)
        self.currentValueLabel = AnyView(currentValueLabel())
    }
}

extension Picker where Label == Text {
    /// Creates a picker with a localized label, and a view the collapsed
    /// control shows as its current value.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's label.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            selection: selection, content: content, label: { Text(titleKey) },
            currentValueLabel: currentValueLabel)
    }

    /// Creates a picker with a text label, displayed as written, and a view the
    /// collapsed control shows as its current value.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            selection: selection, content: content, label: { Text(title) },
            currentValueLabel: currentValueLabel)
    }
}

// MARK: - A title and an SF Symbol

// The forms without a current-value label are with the other controls' SF
// Symbol initialisers, in `ControlSymbolInitializers.swift`.
extension Picker where Label == TUIkit.Label<Text, _SymbolIcon> {
    /// Creates a picker whose label is a localized title and an SF Symbol, and
    /// a view the collapsed control shows as its current value.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            selection: selection, content: content,
            label: { TUIkit.Label(titleKey, systemImage: systemImage) },
            currentValueLabel: currentValueLabel)
    }

    /// Creates a picker whose label is a title, displayed as written, and an SF
    /// Symbol, and a view the collapsed control shows as its current value.
    ///
    /// - Parameters:
    ///   - title: The picker's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            selection: selection, content: content,
            label: { TUIkit.Label(title, systemImage: systemImage) },
            currentValueLabel: currentValueLabel)
    }
}
