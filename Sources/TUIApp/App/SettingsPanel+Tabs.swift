//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsPanel+Tabs.swift
//
//  TUI's View and Accessibility tabs in the settings panel, at either level
//  of the person's settings — this program's, or all programs' — each
//  setting with a box saying whether that level sets it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIForms
import TUIFoundation

// MARK: - The Level

/// Which of the person's settings TUI's tabs show and change.
enum SettingsLevel {
    /// This program's, as the panel opens: the values in force, a ticked box
    /// for each setting this program keeps.
    case thisProgram
    /// The person's settings for all programs (Settings for All Programs…).
    case allPrograms
}

// MARK: - TUI's Tabs

/// View: the palette, the border style and the control style, then how the
/// focus and the keys behave — Breathing Focus, Spell Out Keys, Focus Follows
/// Pointer, Arrows Follow Layout — as the View menu offers them: one model,
/// so the two agree.
struct _SettingsViewTab: View {
    let environment: EnvironmentValues
    let level: SettingsLevel

    var body: some View {
        Form {
            _SettingsLevelHint(level: level)
            _DisplayOptionRows(environment: environment, level: level)
            _PreferenceRows(preferences: ViewPreference.inTab(.view), environment: environment, level: level)
        }
    }
}

/// Accessibility: Differentiate Without Color, Reduce Motion, Reduce
/// Transparency and Increase Contrast, as the View menu offers them.
struct _SettingsAccessibilityTab: View {
    let environment: EnvironmentValues
    let level: SettingsLevel

    var body: some View {
        Form {
            _SettingsLevelHint(level: level)
            _PreferenceRows(preferences: ViewPreference.inTab(.accessibility), environment: environment, level: level)
        }
    }
}

/// The line at the top of a tab saying what a ticked box means at `level`.
private struct _SettingsLevelHint: View {
    let level: SettingsLevel

    var body: some View {
        let key: LocalizationKey.Menu =
            switch level {
            case .thisProgram: .keptForThisProgramHint
            case .allPrograms: .setForAllProgramsHint
            }
        Text(verbatim: LocalizationService.shared.string(for: key)).foregroundStyle(.secondary)
    }
}

// MARK: - The Rows

/// A check for each of `preferences`, each after its box.
///
/// For this program: the value in force, which a change chooses for the run
/// and saves for the program (``ViewPreferenceOverrides/choose(_:_:)``), as
/// the View menu's checks do; the box ticked where the program keeps it.
/// For all programs: the person's value, or faint, the one it inherits.
/// Disabled outside a running app, which has no settings to hold.
private struct _PreferenceRows: View {
    let preferences: [ViewPreference]
    let environment: EnvironmentValues
    let level: SettingsLevel

    var body: some View {
        let service = LocalizationService.shared
        let overrides = environment.viewPreferenceOverrides
        let level = level
        let environment = environment
        ForEach(preferences, id: \.self) { preference in
            let setting = UserSetting.preference(preference)
            let shown = Self.value(of: preference, at: level, overrides: overrides, environment: environment)
            _SettingRow(
                setting: setting,
                isSetHere: Self.isSetHere(setting, at: level, overrides: overrides, shown: .bool(shown)),
                canSetHere: overrides != nil, level: level
            ) {
                Toggle(
                    service.string(for: preference.title),
                    isOn: Binding(
                        get: { shown },
                        set: { Self.set(setting, to: .bool($0), at: level, overrides: overrides) })
                )
                .focusID("tui.settings.\(setting.key)")
            }
        }
        .disabled(overrides == nil)
    }

    /// What `preference` shows at `level`: the value in force for this
    /// program; the person's for all programs, else what it inherits there.
    private static func value(
        of preference: ViewPreference, at level: SettingsLevel, overrides: ViewPreferenceOverrides?,
        environment: EnvironmentValues
    ) -> Bool {
        switch level {
        case .thisProgram:
            return preference.isOn(in: environment)
        case .allPrograms:
            let setting = UserSetting.preference(preference)
            let value = overrides.map { $0.allPrograms[setting] ?? $0.inheritedBeneathAllPrograms(setting) }
            guard case .bool(let isOn) = value else { return preference.defaultValue }
            return isOn
        }
    }

    /// The box of `setting` at `level`, whose value shown is `shown`.
    static func isSetHere(
        _ setting: UserSetting, at level: SettingsLevel, overrides: ViewPreferenceOverrides?, shown: SettingValue
    ) -> Binding<Bool> {
        Binding(
            get: {
                switch level {
                case .thisProgram: overrides?.isSetForProgram(setting) ?? false
                case .allPrograms: overrides?.allPrograms[setting] != nil
                }
            },
            set: { isSet in
                guard let overrides else { return }
                switch (level, isSet) {
                case (.thisProgram, true): overrides.choose(setting, shown)
                case (.thisProgram, false): overrides.giveBack(setting)
                case (.allPrograms, true): overrides.setForAllPrograms(setting, shown)
                case (.allPrograms, false): overrides.setForAllPrograms(setting, nil)
                }
            })
    }

    /// Sets `setting` to `value` at `level`, which ticks its box.
    static func set(_ setting: UserSetting, to value: SettingValue, at level: SettingsLevel, overrides: ViewPreferenceOverrides?) {
        switch level {
        case .thisProgram: overrides?.choose(setting, value)
        case .allPrograms: overrides?.setForAllPrograms(setting, value)
        }
    }
}

/// The palette, the border style and the control style (``DisplayChoices``),
/// each after its box.
///
/// For this program, each chooses as the View menu's does: into the app's
/// state where it handed `DisplayCommands` some, which the app keeps as it
/// likes, and otherwise through TUI's managers, saved for the program; its
/// box is disabled where the app decides the option itself. For all
/// programs, each chooses into the person's settings for all programs.
private struct _DisplayOptionRows: View {
    let environment: EnvironmentValues
    let level: SettingsLevel

    var body: some View {
        let overrides = environment.viewPreferenceOverrides
        let choices = choices(overrides)
        ForEach(DisplayOption.allCases, id: \.self) { option in
            let setting = UserSetting.display(option)
            let shown = SettingValue.identifier(identifier(option, choices: choices, overrides: overrides))
            let isSetHere = _PreferenceRows.isSetHere(setting, at: level, overrides: overrides, shown: shown)
            _SettingRow(
                setting: setting,
                isSetHere: isSetHere,
                canSetHere: level == .allPrograms
                    ? overrides != nil : choices.choosesThroughSettings(option) || isSetHere.wrappedValue,
                level: level
            ) {
                choices.formRow(option)
            }
        }
    }

    /// The choices at this level: the ones in force for this program, or the
    /// person's for all programs, chosen through bindings into them.
    private func choices(_ overrides: ViewPreferenceOverrides?) -> DisplayChoices {
        guard level == .allPrograms, let overrides else { return DisplayChoices(environment: environment) }
        func id(_ option: DisplayOption) -> String {
            guard case .identifier(let id) = overrides.allPrograms[.display(option)] else {
                return option.defaultIdentifier
            }
            return id
        }
        func set(_ option: DisplayOption, _ id: String) {
            overrides.setForAllPrograms(.display(option), .identifier(id))
        }
        let palette = Binding<any Palette>(
            get: { PaletteRegistry.palette(withId: id(.palette)) ?? PaletteRegistry.all[0] },
            set: { set(.palette, $0.id) })
        let appearance = Binding<Appearance>(
            get: { AppearanceRegistry.all.first { $0.id == id(.borderStyle) } ?? AppearanceRegistry.all[0] },
            set: { set(.borderStyle, $0.id) })
        let controlStyle = Binding<ControlStyle>(
            get: { ControlStyle.standardStyles.first { $0.id == id(.controlStyle) } ?? .automatic },
            set: { set(.controlStyle, $0.id) })
        return DisplayChoices(
            managers: (nil, nil, nil), setByScene: [],
            inForce: (environment.palette, environment.appearance, environment.controlStyle),
            bindings: (palette, appearance, controlStyle))
    }

    /// The identifier `option` shows at this level.
    private func identifier(
        _ option: DisplayOption, choices: DisplayChoices, overrides: ViewPreferenceOverrides?
    ) -> String {
        switch level {
        case .allPrograms:
            guard case .identifier(let id) = overrides?.allPrograms[.display(option)] else {
                return option.defaultIdentifier
            }
            return id
        case .thisProgram:
            return choices.identifierShown(option)
        }
    }
}

/// One of TUI's settings in a row: its box, saying whether `level` sets it,
/// then its control, faint where the level does not and it shows the value
/// inherited. Ticking the box sets the value shown at the level; unticking
/// gives the setting back. The box is a check of its own, before the
/// control in Tab order.
private struct _SettingRow<Control: View>: View {
    let setting: UserSetting
    let isSetHere: Binding<Bool>
    let canSetHere: Bool
    let level: SettingsLevel
    @ViewBuilder let control: () -> Control

    var body: some View {
        let name: LocalizationKey.Menu =
            switch level {
            case .thisProgram: .keepForThisProgram
            case .allPrograms: .setForAllPrograms
            }
        let isSet = isSetHere.wrappedValue
        HStack(alignment: .top, spacing: 1) {
            Toggle(LocalizationService.shared.string(for: name), isOn: isSetHere)
                .focusID("tui.settings.setHere.\(setting.key)")
                .labelsHidden()
                .disabled(!canSetHere)
            VStack(alignment: .leading, spacing: 0) {
                control()
            }
            .foregroundStyle(isSet ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.tertiary)
        }
    }
}
