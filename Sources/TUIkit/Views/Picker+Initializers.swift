//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Picker+Initializers.swift
//
//  SwiftUI's Picker initialisers that take a custom current-value label, and
//  those that select for a collection of values.
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

// MARK: - A collection of selections

/// One binding standing for every selection in `bindings`: it reads the
/// first and writes them all, so picking an option sets every source to it.
/// Never read for an empty collection — the picker then builds nothing that
/// asks (``Picker/hasNoSources``).
@MainActor
private func collectiveSelection<Value: Hashable>(_ bindings: [Binding<Value>]) -> Binding<Value> {
    Binding(
        get: {
            guard let first = bindings.first else {
                preconditionFailure("an empty Picker(sources:) reads no selection")
            }
            return first.wrappedValue
        },
        set: { value in
            for binding in bindings { binding.wrappedValue = value }
        })
}

extension Picker {
    /// This picker over the selections `sources` hold: mixed when they
    /// disagree, empty when there are none. Read when the picker is made, which
    /// is every evaluation of the body holding it.
    fileprivate init<C: RandomAccessCollection>(
        sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        content: () -> Content, label: () -> Label, currentValueLabel: AnyView?
    ) {
        let bindings = sources.map { $0[keyPath: selection] }
        self.init(selection: collectiveSelection(bindings), content: content, label: label)
        self.currentValueLabel = currentValueLabel
        hasNoSources = bindings.isEmpty
        isMixed = Set(bindings.map(\.wrappedValue)).count > 1
    }

    /// Creates a picker that selects for a collection of values, with a custom
    /// label.
    ///
    /// The picker shows the value every source holds; where they disagree it
    /// marks no option, and picking one sets every source to it. Over an empty
    /// collection it draws its label and an empty, disabled control.
    ///
    /// - Parameters:
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - label: A view builder for the picker's label.
    public init<C: RandomAccessCollection>(
        sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label
    ) {
        self.init(sources: sources, selection: selection, content: content, label: label, currentValueLabel: nil)
    }

    /// Creates a picker that selects for a collection of values, with a custom
    /// label and a view the collapsed control shows as its current value.
    ///
    /// - Parameters:
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - label: A view builder for the picker's label.
    ///   - currentValueLabel: A view builder for the current value's label.
    public init<C: RandomAccessCollection>(
        sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            sources: sources, selection: selection, content: content, label: label,
            currentValueLabel: AnyView(currentValueLabel()))
    }
}

extension Picker where Label == Text {
    /// Creates a picker that selects for a collection of values, with a
    /// localized label.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's label.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    public init<C: RandomAccessCollection>(
        _ titleKey: LocalizedStringKey, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(sources: sources, selection: selection, content: content, label: { Text(titleKey) })
    }

    /// Creates a picker that selects for a collection of values, with a
    /// localized label and a view the collapsed control shows as its current
    /// value.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's label.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    public init<C: RandomAccessCollection>(
        _ titleKey: LocalizedStringKey, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content, @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            sources: sources, selection: selection, content: content, label: { Text(titleKey) },
            currentValueLabel: currentValueLabel)
    }

    /// Creates a picker that selects for a collection of values, with a label
    /// displayed as written.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    @_disfavoredOverload
    public init<C: RandomAccessCollection, S: StringProtocol>(
        _ title: S, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(sources: sources, selection: selection, content: content, label: { Text(title) })
    }

    /// Creates a picker that selects for a collection of values, with a label
    /// displayed as written and a view the collapsed control shows as its
    /// current value.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    @_disfavoredOverload
    public init<C: RandomAccessCollection, S: StringProtocol>(
        _ title: S, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content, @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            sources: sources, selection: selection, content: content, label: { Text(title) },
            currentValueLabel: currentValueLabel)
    }
}

extension Picker where Label == TUIkit.Label<Text, _SymbolIcon> {
    /// Creates a picker that selects for a collection of values, labelled with
    /// a localized title and an SF Symbol.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    public init<C: RandomAccessCollection>(
        _ titleKey: LocalizedStringKey, systemImage: String, sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>, @ViewBuilder content: () -> Content
    ) {
        self.init(
            sources: sources, selection: selection, content: content,
            label: { TUIkit.Label(titleKey, systemImage: systemImage) })
    }

    /// Creates a picker that selects for a collection of values, labelled with
    /// a localized title and an SF Symbol, with a view the collapsed control
    /// shows as its current value.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    public init<C: RandomAccessCollection>(
        _ titleKey: LocalizedStringKey, systemImage: String, sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>, @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            sources: sources, selection: selection, content: content,
            label: { TUIkit.Label(titleKey, systemImage: systemImage) }, currentValueLabel: currentValueLabel)
    }

    /// Creates a picker that selects for a collection of values, labelled with
    /// a title displayed as written and an SF Symbol.
    ///
    /// - Parameters:
    ///   - title: The picker's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    @_disfavoredOverload
    public init<C: RandomAccessCollection, S: StringProtocol>(
        _ title: S, systemImage: String, sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>, @ViewBuilder content: () -> Content
    ) {
        self.init(
            sources: sources, selection: selection, content: content,
            label: { TUIkit.Label(title, systemImage: systemImage) })
    }

    /// Creates a picker that selects for a collection of values, labelled with
    /// a title displayed as written and an SF Symbol, with a view the collapsed
    /// control shows as its current value.
    ///
    /// - Parameters:
    ///   - title: The picker's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - sources: The values the picker selects for.
    ///   - selection: The key path from a source to its selection binding.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - currentValueLabel: A view builder for the current value's label.
    @_disfavoredOverload
    public init<C: RandomAccessCollection, S: StringProtocol>(
        _ title: S, systemImage: String, sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>, @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> some View
    ) {
        self.init(
            sources: sources, selection: selection, content: content,
            label: { TUIkit.Label(title, systemImage: systemImage) }, currentValueLabel: currentValueLabel)
    }
}
