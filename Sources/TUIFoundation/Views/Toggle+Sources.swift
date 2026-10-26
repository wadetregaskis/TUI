//  🖥️ TUI — A Terminal UI framework for Swift
//  Toggle+Sources.swift
//
//  SwiftUI's toggles over a collection: one toggle standing for many values,
//  on when they all are, off when none is, and mixed in between.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One binding standing for every binding in `sources`: `true` when all of
/// them are, and setting it sets them all — so a mixed toggle, which reads as
/// not on, turns everything on, as a macOS mixed checkbox does.
///
/// With no sources the toggle is off, and setting it does nothing.
@MainActor
private func collectiveBinding(_ bindings: [Binding<Bool>]) -> Binding<Bool> {
    Binding(
        get: { !bindings.isEmpty && bindings.allSatisfy(\.wrappedValue) },
        set: { value in
            for binding in bindings { binding.wrappedValue = value }
        })
}

extension Toggle {
    /// Creates a toggle representing a collection of values with a custom
    /// label.
    ///
    /// ```swift
    /// Toggle(sources: $alarms, isOn: \.isOn) {
    ///     Text("Enable all alarms")
    /// }
    /// ```
    ///
    /// The toggle is on when every source is, off when none is, and mixed when
    /// some are: a checkbox draws a mixed mark (`⊟`, or `[-]`), a switch — which
    /// has no mixed position on macOS either — draws as off, and a custom style
    /// sees ``ToggleStyleConfiguration/isMixed``. Toggling a mixed toggle turns
    /// every source on.
    ///
    /// - Parameters:
    ///   - sources: The values the toggle stands for.
    ///   - isOn: The key path from a source to its on/off binding.
    ///   - label: A view describing the purpose of the toggle.
    public init<C: RandomAccessCollection>(
        sources: C, isOn: KeyPath<C.Element, Binding<Bool>>, @ViewBuilder label: () -> Label
    ) {
        // Read now: a toggle is made afresh in every evaluation of the body that
        // holds it, so this is the state the frame draws.
        let bindings = sources.map { $0[keyPath: isOn] }
        self.init(isOn: collectiveBinding(bindings), label: label)
        let values = bindings.map(\.wrappedValue)
        if values.contains(true), values.contains(false) {
            proxy.insert(.isMixed)
        }
    }
}

extension Toggle where Label == Text {
    /// Creates a toggle representing a collection of values with a localized
    /// title.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the toggle's title.
    ///   - sources: The values the toggle stands for.
    ///   - isOn: The key path from a source to its on/off binding.
    public init<C: RandomAccessCollection>(
        _ titleKey: LocalizedStringKey, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>
    ) {
        self.init(sources: sources, isOn: isOn) { Text(titleKey) }
    }

    /// Creates a toggle representing a collection of values with a title,
    /// displayed as written.
    ///
    /// - Parameters:
    ///   - title: The toggle's title.
    ///   - sources: The values the toggle stands for.
    ///   - isOn: The key path from a source to its on/off binding.
    @_disfavoredOverload
    public init<S: StringProtocol, C: RandomAccessCollection>(
        _ title: S, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>
    ) {
        self.init(sources: sources, isOn: isOn) { Text(title) }
    }
}

extension Toggle where Label == TUIFoundation.Label<Text, _SymbolIcon> {
    /// Creates a toggle representing a collection of values, labelled with a
    /// localized title and an SF Symbol.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the toggle's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - sources: The values the toggle stands for.
    ///   - isOn: The key path from a source to its on/off binding.
    public init<C: RandomAccessCollection>(
        _ titleKey: LocalizedStringKey, systemImage: String, sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) {
        self.init(sources: sources, isOn: isOn) { TUIFoundation.Label(titleKey, systemImage: systemImage) }
    }

    /// Creates a toggle representing a collection of values, labelled with a
    /// title displayed as written and an SF Symbol.
    ///
    /// - Parameters:
    ///   - title: The toggle's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - sources: The values the toggle stands for.
    ///   - isOn: The key path from a source to its on/off binding.
    @_disfavoredOverload
    public init<S: StringProtocol, C: RandomAccessCollection>(
        _ title: S, systemImage: String, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>
    ) {
        self.init(sources: sources, isOn: isOn) { TUIFoundation.Label(title, systemImage: systemImage) }
    }
}
