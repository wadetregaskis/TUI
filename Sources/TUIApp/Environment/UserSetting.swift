//  🖥️ TUI — A Terminal UI framework for Swift
//  UserSetting.swift
//
//  TUI's own settings as they are kept between runs: each one's key, its value
//  as saved, and one level's worth of them — the person's for this program, or
//  for every program.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUITerminalHost

// MARK: - The Display Options

/// A display option the View menu and the settings panel's View tab choose
/// among: what the app's palette, appearance and control style managers hold.
package enum DisplayOption: CaseIterable, Hashable, Sendable {
    case palette
    case borderStyle
    case controlStyle

    /// The option as a scene states it for itself.
    package var sceneOption: SceneDisplayOptions {
        switch self {
        case .palette: .palette
        case .borderStyle: .appearance
        case .controlStyle: .controlStyle
        }
    }

    /// What the View menu and the panel call it.
    package var title: LocalizationKey.Menu {
        switch self {
        case .palette: .palette
        case .borderStyle: .borderStyle
        case .controlStyle: .controlStyle
        }
    }

    /// The identifiers of the built-in options, in the order they are offered.
    package var identifiers: [String] {
        switch self {
        case .palette: PaletteRegistry.all.map(\.id)
        case .borderStyle: AppearanceRegistry.all.map(\.id)
        case .controlStyle: ControlStyle.standardStyles.map(\.id)
        }
    }

    /// TUI's default: the first option offered, which each manager starts at.
    package var defaultIdentifier: String { identifiers[0] }
}

// MARK: - The Settings

/// One of TUI's own settings, as it is kept: a display option or a check.
///
/// Its ``key`` names it in the person's file of settings for all programs
/// (`defaults.json`) and, after `TUISettings.`, in a program's own store. The
/// keys are a published format: never rename one.
package enum UserSetting: Hashable, Sendable {
    case display(DisplayOption)
    case preference(ViewPreference)

    /// Every setting, in the order the panel lists them: the View tab's, then
    /// the Accessibility tab's.
    package static let allCases: [Self] =
        DisplayOption.allCases.map(Self.display)
        + ViewPreference.inTab(.view).map(Self.preference)
        + ViewPreference.inTab(.accessibility).map(Self.preference)

    /// The setting's name where it is kept.
    package var key: String {
        switch self {
        case .display(.palette): "palette"
        case .display(.borderStyle): "borderStyle"
        case .display(.controlStyle): "controlStyle"
        case .preference(let preference): preference.key
        }
    }

    /// The setting `key` names, or `nil` for a key TUI does not know.
    package init?(key: String) {
        guard let setting = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = setting
    }

    /// The key it is kept under in a program's own store.
    package var programStoreKey: String { "TUISettings.\(key)" }

    /// Whether `value` is one this setting can take: a check's `Bool`, or the
    /// identifier of one of a display option's built-in options.
    package func accepts(_ value: SettingValue) -> Bool {
        switch (self, value) {
        case (.preference, .bool): true
        case (.display(let option), .identifier(let id)): option.identifiers.contains(id)
        default: false
        }
    }
}

extension ViewPreference {
    /// The preference's name where it is kept (``UserSetting/key``).
    package var key: String {
        switch self {
        case .differentiateWithoutColor: "differentiateWithoutColor"
        case .reduceMotion: "reduceMotion"
        case .reduceTransparency: "reduceTransparency"
        case .increaseContrast: "increaseContrast"
        case .focusBreathing: "focusBreathing"
        case .spelledOutKeys: "spelledOutKeys"
        case .focusFollowsPointer: "focusFollowsPointer"
        case .arrowsFollowLayout: "arrowsFollowLayout"
        }
    }

    /// TUI's default, where nothing else says: the focus breathes, and
    /// everything else is off.
    package var defaultValue: Bool { self == .focusBreathing }

    /// The host's accessibility setting for this preference, where it has one.
    package var accessibility: AccessibilityPreferences? {
        switch self {
        case .reduceMotion: .reduceMotion
        case .reduceTransparency: .reduceTransparency
        case .differentiateWithoutColor: .differentiateWithoutColor
        case .increaseContrast: .increaseContrast
        case .focusBreathing, .spelledOutKeys, .focusFollowsPointer, .arrowsFollowLayout: nil
        }
    }

    /// What the user's variables state, by preference, from what the app
    /// runner read of them: each accessibility preference `requested` (`1`)
    /// or `declined` (`0`), the names under `TUI_KEY_SYMBOLS=0`, a still
    /// focus under `TUI_BREATHING=0`. A preference no variable states is
    /// left out.
    package static func stated(
        requestedAccessibility requested: AccessibilityPreferences,
        declinedAccessibility declined: AccessibilityPreferences, keyNotation: KeyNotation, focusBreathes: Bool
    ) -> [Self: Bool] {
        var stated: [Self: Bool] = [:]
        for preference in allCases {
            guard let accessibility = preference.accessibility else { continue }
            if requested.contains(accessibility) {
                stated[preference] = true
            } else if declined.contains(accessibility) {
                stated[preference] = false
            }
        }
        if keyNotation == .spelledOut { stated[.spelledOutKeys] = true }
        if !focusBreathes { stated[.focusBreathing] = false }
        return stated
    }
}

// MARK: - A Value

/// A setting's value as it is kept: a check's, or a display option's
/// identifier.
package enum SettingValue: Hashable, Sendable {
    case bool(Bool)
    case identifier(String)
}

// MARK: - One Level

/// The settings one level sets — the person's for this program, or for all
/// programs — each one it sets with its value; a setting it leaves out it
/// does not set.
package struct SettingsLayer: Equatable, Sendable {
    /// What the level sets, by setting.
    package var values: [UserSetting: SettingValue] = [:]

    package init(_ values: [UserSetting: SettingValue] = [:]) {
        self.values = values
    }

    /// The value the level sets for `setting`, or `nil` where it sets none.
    package subscript(setting: UserSetting) -> SettingValue? {
        get { values[setting] }
        set { values[setting] = newValue }
    }

    /// Whether the level turns `preference` on or off, or `nil` where it
    /// says nothing.
    package func isOn(_ preference: ViewPreference) -> Bool? {
        guard case .bool(let isOn) = values[.preference(preference)] else { return nil }
        return isOn
    }

    /// The identifier the level chooses for `option`, or `nil` where it says
    /// nothing.
    package func identifier(_ option: DisplayOption) -> String? {
        guard case .identifier(let id) = values[.display(option)] else { return nil }
        return id
    }
}
