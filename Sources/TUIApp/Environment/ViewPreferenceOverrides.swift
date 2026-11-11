//  🖥️ TUI — A Terminal UI framework for Swift
//  ViewPreferenceOverrides.swift
//
//  TUI's own settings, level by level: what the person chose in the View
//  menu or the settings panel this run, which wins over everything until the
//  app quits and is saved for the program; what they saved for this program;
//  and what they saved for all programs. And the list of every setting the
//  two offer, with its value type.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUITerminalHost
import TUIView

// MARK: - The Preferences

/// A preference the View menu and the settings panel turn on or off for the
/// rest of the run (``ViewPreferenceOverrides``), each a `Bool` in the frame's
/// environment.
package enum ViewPreference: CaseIterable, Hashable, Sendable {
    /// ``EnvironmentValues/accessibilityDifferentiateWithoutColor``: the
    /// no-colour cues drawn over the colours.
    case differentiateWithoutColor
    /// ``EnvironmentValues/accessibilityReduceMotion``.
    case reduceMotion
    /// ``EnvironmentValues/accessibilityReduceTransparency``.
    case reduceTransparency
    /// ``EnvironmentValues/colorSchemeContrast`` at `.increased`.
    case increaseContrast
    /// ``EnvironmentValues/focusBreathes``: the focus breathes, or holds
    /// still (`TUI_BREATHING`).
    case focusBreathing
    /// ``EnvironmentValues/keyNotation`` at ``KeyNotation/spelledOut``
    /// (`TUI_KEY_SYMBOLS=0`).
    case spelledOutKeys
    /// Whether a pointer move gives the focus to the control it lands on
    /// (`TUI_FOCUS_FOLLOWS_POINTER`, `Scene.focusFollowsPointer(_:)`).
    case focusFollowsPointer
    /// ``EnvironmentValues/arrowFocus`` at ``ArrowFocus/geometric``: an arrow
    /// a control leaves unused goes to the nearest control that way, rather
    /// than the next in Tab order (`TUI_ARROW_FOCUS=geometric`). An
    /// experiment, off unless the user turns it on.
    case arrowsFollowLayout

    /// Whether the preference is on in `environment`: what the View menu
    /// checks.
    package func isOn(in environment: EnvironmentValues) -> Bool {
        switch self {
        case .differentiateWithoutColor: environment.accessibilityDifferentiateWithoutColor
        case .reduceMotion: environment.accessibilityReduceMotion
        case .reduceTransparency: environment.accessibilityReduceTransparency
        case .increaseContrast: environment.colorSchemeContrast == .increased
        case .focusBreathing: environment.focusBreathes
        case .spelledOutKeys: environment.keyNotation == .spelledOut
        case .focusFollowsPointer: environment.focusFollowsPointer ?? false
        case .arrowsFollowLayout: environment.arrowFocus == .geometric
        }
    }

    /// The settings panel's tab it is in: View for how the focus and the keys
    /// behave, Accessibility for the four the system's own settings answer.
    /// The View menu lists them in the same order, the View tab's first.
    package var tab: BuiltInSettingsTab {
        switch self {
        case .differentiateWithoutColor, .reduceMotion, .reduceTransparency, .increaseContrast: .accessibility
        case .focusBreathing, .spelledOutKeys, .focusFollowsPointer, .arrowsFollowLayout: .view
        }
    }

    /// The preferences in `tab`, in the order the panel and the View menu
    /// list them.
    package static func inTab(_ tab: BuiltInSettingsTab) -> [Self] {
        allCases.filter { $0.tab == tab }
    }

    /// What the View menu and the settings panel's Accessibility tab call it.
    package var title: LocalizationKey.Menu {
        switch self {
        case .differentiateWithoutColor: .differentiateWithoutColor
        case .reduceMotion: .reduceMotion
        case .reduceTransparency: .reduceTransparency
        case .increaseContrast: .increaseContrast
        case .focusBreathing: .focusBreathing
        case .spelledOutKeys: .spelledOutKeys
        case .focusFollowsPointer: .focusFollowsPointer
        case .arrowsFollowLayout: .arrowsFollowLayout
        }
    }

    /// Turns the preference on or off in `environment`.
    func set(_ isOn: Bool, in environment: inout EnvironmentValues) {
        switch self {
        case .differentiateWithoutColor: environment.accessibilityDifferentiateWithoutColor = isOn
        case .reduceMotion: environment.accessibilityReduceMotion = isOn
        case .reduceTransparency: environment.accessibilityReduceTransparency = isOn
        case .increaseContrast: environment.colorSchemeContrast = isOn ? .increased : .standard
        case .focusBreathing: environment.focusBreathes = isOn
        case .spelledOutKeys: environment.keyNotation = isOn ? .spelledOut : .symbols
        case .focusFollowsPointer: environment.focusFollowsPointer = isOn
        case .arrowsFollowLayout: environment.arrowFocus = isOn ? .geometric : .tabOrder
        }
    }
}

// MARK: - The Choices

/// TUI's own settings for this app, level by level: what the person chose in
/// the View menu or the settings panel this run, what they saved for this
/// program, and what they saved for all programs. The one model the two are
/// drawn from, so they always agree.
///
/// **Every setting the two offer** (``UserSetting``), each with its value
/// type and where the choice is held:
///
/// | Setting | Value | Held by |
/// |---|---|---|
/// | Palette | a palette's id (`String`, `PaletteRegistry`) | the palette manager, or the app's state (``displayBindings``) |
/// | Border Style | an appearance's id (`String`, `AppearanceRegistry`) | the appearance manager, or the app's state |
/// | Control Style | a `ControlStyle`'s id (`String`) | the control style manager, or the app's state |
/// | each ``ViewPreference`` | `Bool` | this, by preference |
///
/// **Seven layers decide each, highest first** (the owner's USET-ORDER,
/// 2026-11-10): this run's choice; the user's `TUI_*` variable; the scene's
/// own statements; what the person saved for this program; what they saved
/// for all programs; the computer's setting; TUI's default. The variable,
/// the two saved levels and the computer's setting are resolved together at
/// the root of each frame (``valueBeneathCode(_:statedByVariable:system:)``);
/// the scene's statements are applied over that root (so a scene's
/// `.reduceMotion(true)` adds the aid even under `TUI_REDUCE_MOTION=0`, and
/// its `.focusFollowsPointer(_:)` replaces the variable's, as each always
/// has); and this run's choices last, in
/// ``SceneConfiguration/applyRootOverrides(to:)``, so they reach the page,
/// the bars and every window alike. A view that writes one of the values for
/// its own subtree still decides there, as anywhere. A display option goes
/// to its manager rather than through the root (``follow(_:)``), and a scene
/// that states its own decides it outright.
///
/// A choice made this run is saved for the program as it is made (USET-SAVE),
/// under `TUISettings.<key>` in the program's store, so the next run starts
/// from it, at the fourth layer. The settings for all programs are a file of
/// the person's (``AllProgramsSettingsFile``), read at launch and when the
/// terminal regains the focus. A loop given no store keeps nothing: a test's,
/// unless it gives one. Each app has its own, reached through the environment
/// (``EnvironmentValues/viewPreferenceOverrides``).
@MainActor
package final class ViewPreferenceOverrides {
    /// The choices made this run, by preference.
    private var choices: [ViewPreference: Bool] = [:]

    /// The display options chosen this run through TUI's managers.
    private var displayChoices: [DisplayOption: String] = [:]

    /// What the person saved for this program, as read when the store was
    /// adopted and changed since.
    package private(set) var program = SettingsLayer()

    /// What the person saved for all programs, as last read from their file.
    package private(set) var allPrograms = SettingsLayer()

    /// Where this program's settings are kept: the store an `@AppStorage` that
    /// names none uses, in a running app; `nil` keeps nothing.
    private var programStore: (any StorageBackend)?

    /// The person's file of settings for all programs; `nil` reads and
    /// writes none.
    private var allProgramsFile: AllProgramsSettingsFile?

    /// The app's managers of the display options, which a choice of one goes
    /// to.
    private let managers: [DisplayOption: ThemeManager]

    /// Asks for the frame that draws a new choice.
    private let renderTrigger: () -> Void

    /// The app's own state for the display options, where the scene's
    /// commands hand some to `DisplayCommands`: what a choice of the settings
    /// panel's View tab goes to, as the View menu's does. Posted by the menu
    /// bar as it collects the commands, after the content has drawn, so the
    /// panel goes by the last frame's — the same bindings, frame after frame.
    package var displayBindings = DisplayChoices.Bindings()

    /// The host's own accessibility settings, where the user is at this
    /// machine: the computer's setting, the sixth layer. Written by the render
    /// loop at the root of each frame.
    package var hostAccessibility: AccessibilityPreferences = []

    /// Choices for an app whose display options `managers` hold and whose
    /// frames `renderTrigger` asks for, keeping nothing until it adopts a
    /// store (``adopt(programStore:allProgramsFile:)``).
    package init(managers: [DisplayOption: ThemeManager] = [:], renderTrigger: @escaping () -> Void = {}) {
        self.managers = managers
        self.renderTrigger = renderTrigger
    }

    /// Keeps this program's settings in `programStore` and reads the person's
    /// for all programs from `allProgramsFile`, starting from what each holds:
    /// the display managers move to the options saved. A value the store holds
    /// that no setting can take is left out.
    package func adopt(programStore: (any StorageBackend)?, allProgramsFile: AllProgramsSettingsFile?) {
        self.programStore = programStore
        self.allProgramsFile = allProgramsFile
        program = SettingsLayer()
        if let programStore {
            for setting in UserSetting.allCases {
                let key = setting.programStoreKey
                let value: SettingValue? =
                    switch setting {
                    case .preference: programStore.entry(forKey: key, as: Bool.self).value.map(SettingValue.bool)
                    case .display: programStore.entry(forKey: key, as: String.self).value.map(SettingValue.identifier)
                    }
                if let value, setting.accepts(value) { program[setting] = value }
            }
        }
        allPrograms = allProgramsFile?.read() ?? SettingsLayer()
        DisplayOption.allCases.forEach(follow)
        renderTrigger()
    }

    /// Reads the person's file of settings for all programs again, where it
    /// may have changed: another program writes it too. A change draws a frame.
    package func reloadAllPrograms() {
        guard let allProgramsFile else { return }
        let read = allProgramsFile.read()
        guard read != allPrograms else { return }
        allPrograms = read
        DisplayOption.allCases.forEach(follow)
        renderTrigger()
    }

    // MARK: This Run, and This Program

    /// The choice made this run for `preference`, or `nil` for none. Setting
    /// one chooses it (``choose(_:_:)``); setting `nil` gives it back
    /// (``giveBack(_:)``).
    package subscript(preference: ViewPreference) -> Bool? {
        get { choices[preference] }
        set {
            if let newValue {
                choose(.preference(preference), .bool(newValue))
            } else {
                giveBack(.preference(preference))
            }
        }
    }

    /// Chooses `value` for `setting` this run, and saves it for this program:
    /// what the View menu and the settings panel do. A display option goes to
    /// its manager.
    package func choose(_ setting: UserSetting, _ value: SettingValue) {
        guard setting.accepts(value) else { return }
        switch (setting, value) {
        case (.preference(let preference), .bool(let isOn)):
            choices[preference] = isOn
            programStore?.setValue(isOn, forKey: setting.programStoreKey)
        case (.display(let option), .identifier(let id)):
            displayChoices[option] = id
            programStore?.setValue(id, forKey: setting.programStoreKey)
        default:
            return
        }
        program[setting] = value
        if case .display(let option) = setting { follow(option) }
        renderTrigger()
    }

    /// Whether this program sets `setting`: the person chose it this run, or
    /// saved it for the program in an earlier one. What the settings panel's
    /// "set here" box shows for this program.
    package func isSetForProgram(_ setting: UserSetting) -> Bool {
        switch setting {
        case .preference(let preference) where choices[preference] != nil: true
        case .display(let option) where displayChoices[option] != nil: true
        default: program[setting] != nil
        }
    }

    /// Gives `setting` back for this program: forgets this run's choice and
    /// what was saved for the program, so the program's code, the variable,
    /// the settings for all programs or the computer's setting decide it again.
    package func giveBack(_ setting: UserSetting) {
        switch setting {
        case .preference(let preference): choices[preference] = nil
        case .display(let option): displayChoices[option] = nil
        }
        program[setting] = nil
        programStore?.removeValue(forKey: setting.programStoreKey)
        if case .display(let option) = setting { follow(option) }
        renderTrigger()
    }

    // MARK: All Programs

    /// Sets `setting` to `value` in the person's settings for all programs,
    /// or gives it back there where `value` is `nil`: shown at once wherever
    /// this run and this program leave the setting to them.
    package func setForAllPrograms(_ setting: UserSetting, _ value: SettingValue?) {
        if let value, !setting.accepts(value) { return }
        allPrograms[setting] = value
        allProgramsFile?.write(value, for: setting)
        if case .display(let option) = setting { follow(option) }
        renderTrigger()
    }

    // MARK: Resolving

    /// What decides `preference` beneath the scene's own statements: the
    /// user's variable for this launch, `statedByVariable`; else what the
    /// person saved for this program; else for all programs; else the
    /// computer's setting (``hostAccessibility``). `nil` where none of them
    /// says, which leaves TUI's default (``ViewPreference/defaultValue``).
    package func valueBeneathCode(_ preference: ViewPreference, statedByVariable: Bool?) -> Bool? {
        statedByVariable ?? program.isOn(preference) ?? allPrograms.isOn(preference) ?? system(preference)
    }

    /// What `setting` inherits where the person's settings for all programs
    /// leave it unset: the computer's setting, else TUI's default. What the
    /// settings panel shows, faint, for a setting they don't set.
    package func inheritedBeneathAllPrograms(_ setting: UserSetting) -> SettingValue {
        switch setting {
        case .preference(let preference): .bool(system(preference) ?? preference.defaultValue)
        case .display(let option): .identifier(option.defaultIdentifier)
        }
    }

    /// The computer's setting for `preference`: on where the host's own
    /// accessibility setting is, and otherwise none.
    private func system(_ preference: ViewPreference) -> Bool? {
        guard let accessibility = preference.accessibility, hostAccessibility.contains(accessibility) else {
            return nil
        }
        return true
    }

    /// Moves `option`'s manager to the option the layers choose: this run's,
    /// else this program's, else all programs', else TUI's default. A scene
    /// that states its own is drawn with it all the same.
    private func follow(_ option: DisplayOption) {
        guard let manager = managers[option] else { return }
        let id =
            displayChoices[option] ?? program.identifier(option) ?? allPrograms.identifier(option)
            ?? option.defaultIdentifier
        guard manager.current.id != id, let item = manager.items.first(where: { $0.id == id }) else { return }
        manager.setCurrent(item)
    }

    /// Writes every choice made this run into `environment`, over what was
    /// there.
    package func apply(to environment: inout EnvironmentValues) {
        for (preference, isOn) in choices { preference.set(isOn, in: &environment) }
    }
}

// MARK: - Environment

/// Environment key for the app's View menu choices.
private struct ViewPreferenceOverridesKey: EnvironmentKey {
    static var defaultValue: ViewPreferenceOverrides? { nil }
}

extension EnvironmentValues {
    /// What the person chose in the View menu for this run, or `nil` outside
    /// a running app. The render loop writes it at the root of every frame.
    package var viewPreferenceOverrides: ViewPreferenceOverrides? {
        get { self[ViewPreferenceOverridesKey.self] }
        set { self[ViewPreferenceOverridesKey.self] = newValue }
    }
}
