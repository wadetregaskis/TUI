//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlStyle+Choosing.swift
//
//  The control style as something a person chooses: its name, the styles
//  offered, and the app's control style manager, which holds the choice at
//  the root as the palette and appearance managers hold theirs.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStrings

// MARK: - A Style to Choose

extension ControlStyle: Cyclable {
    /// The style's identifier: its case's name, with a Braille style's
    /// thickness after it where that is more than one dot (`braille2`), as
    /// ``Appearance/braille(thickness:)`` names its appearances.
    public var id: String {
        switch self {
        case .automatic: "automatic"
        case .block: "block"
        case .lines: "lines"
        case .braille(let thickness): thickness == 1 ? "braille" : "braille\(thickness)"
        case .blank: "blank"
        }
    }

    /// The style's name in the app's language: "Lines", "Braille, 2 Dots".
    ///
    /// Localized, where ``Appearance/name`` is not, because this type is in a
    /// module that can see the localization service (``Appearance`` is below
    /// it, so its localized name is ``Appearance/localizedName``). A thickness
    /// TUI names none for falls back to the identifier.
    public var name: String {
        let key = "controlStyle.\(id)"
        let localized = LocalizationService.shared.frameworkString(for: key)
        return localized == key ? id : localized
    }

    /// The styles a person is offered, in order — View ▸ Control Style ▸
    /// (`DisplayCommands`) and the app's ``EnvironmentValues/controlStyleManager``:
    /// the default, filled faces, lines, Braille dots one to four thick, and
    /// none.
    package static let standardStyles: [ControlStyle] = [
        .automatic, .block, .lines,
        .braille(thickness: 1), .braille(thickness: 2), .braille(thickness: 3), .braille(thickness: 4),
        .blank,
    ]
}

// MARK: - The App's Choice

/// Environment key for the control style manager.
private struct ControlStyleManagerKey: EnvironmentKey {
    static var defaultValue: ThemeManager? { nil }
}

extension EnvironmentValues {
    /// The control style manager: the app's choice of ``controlStyle`` at the
    /// root of every frame, as the palette and appearance managers hold its
    /// palette and border appearance.
    ///
    /// ```swift
    /// context.environment.controlStyleManager?.setCurrent(ControlStyle.lines)
    /// ```
    ///
    /// View ▸ Control Style ▸ (`DisplayCommands`) chooses through it. A
    /// `.controlStyle(_:)` or a scene's `.environment(\.controlStyle, …)` wins
    /// over it where it is written, as a scene's `.palette(_:)` wins over the
    /// palette manager.
    ///
    /// `nil` outside a running application, as the other two managers are.
    public var controlStyleManager: ThemeManager? {
        get { self[ControlStyleManagerKey.self] }
        set { self[ControlStyleManagerKey.self] = newValue }
    }
}

extension ThemeManager {
    /// The current item cast to ``ControlStyle``.
    ///
    /// Use this on the control style manager to get a strongly-typed style.
    /// Returns `nil` if the manager does not hold ``ControlStyle`` items.
    public var currentControlStyle: ControlStyle? {
        current as? ControlStyle
    }
}
