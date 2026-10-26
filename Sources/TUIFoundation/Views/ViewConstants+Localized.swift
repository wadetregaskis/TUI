//  🖥️ TUI — A Terminal UI framework for Swift
//  ViewConstants+Localized.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling

extension ViewConstants {
    /// What an empty `List` or `Table` shows by default, in the current
    /// language — `label.noItems`, translated in every bundled table.
    ///
    /// Here rather than beside ``emptyListPlaceholder`` because the
    /// localization service is TUIStrings', which this module sees and
    /// `TUIStyling` does not; that constant is the English fallback and
    /// was, until now, what every empty list and table showed whatever the
    /// language.
    public static var localizedEmptyListPlaceholder: String {
        LocalizationService.shared.string(for: LocalizationKey.Label.noItems)
    }
}
