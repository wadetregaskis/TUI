//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerSymbolInitializers.swift
//
//  Picker's share of the SF Symbol shorthand; why the shorthand exists, and
//  how it degrades, is in `ControlSymbolInitializers.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - Picker

extension Picker where Label == TUIFoundation.Label<Text, _SymbolIcon> {
    /// Creates a picker with an SF Symbol beside a localized label.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's label.
    ///   - systemImage: The SF Symbol name, e.g. `"paintpalette"`.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            TUIFoundation.Label(titleKey, systemImage: systemImage)
        }
    }

    /// Creates a picker with an SF Symbol beside a label shown as written.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - systemImage: The SF Symbol name, e.g. `"paintpalette"`.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            TUIFoundation.Label(title, systemImage: systemImage)
        }
    }
}
