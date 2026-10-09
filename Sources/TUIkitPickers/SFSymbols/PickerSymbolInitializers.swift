//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerSymbolInitializers.swift
//
//  Picker's share of the SF Symbol shorthand; why the shorthand exists, and
//  how it degrades, is in `ControlSymbolInitializers.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - Picker

extension Picker where Label == TUIkitFoundation.Label<Text, _SymbolIcon> {
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
        self.init(
            titleKey.localized, systemImage: systemImage,
            selection: selection, content: content)
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
            TUIkitFoundation.Label(title, systemImage: systemImage)
        }
    }
}
