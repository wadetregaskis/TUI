//  🖥️ TUI — A Terminal UI framework for Swift
//  ViewPreferenceOverrides.swift
//
//  What the person chose in the View menu or the settings panel for this
//  run: the accessibility and display preferences they turned on or off
//  there, which win over the system's setting, the `TUI_*` variable and the
//  app's own scene modifiers until the app quits. Never saved. And the list
//  of every setting the two offer, with its value type.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
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

/// What the person chose in the View menu or the settings panel for this run,
/// one choice per ``ViewPreference``, or none where they left it as it came:
/// the one model the two are drawn from, so they always agree.
///
/// **Every setting the two offer**, each with its value type and where the
/// choice is held — the list a store that keeps them between runs would go
/// by:
///
/// | Setting | Value | Held by |
/// |---|---|---|
/// | Palette | a palette's id (`String`, `PaletteRegistry`) | the palette manager, or the app's state (``displayBindings``) |
/// | Border Style | an appearance's id (`String`, `AppearanceRegistry`) | the appearance manager, or the app's state |
/// | Control Style | `ControlStyle` | the control style manager, or the app's state |
/// | each ``ViewPreference`` | `Bool` | this, by preference |
///
/// The first three are ``DisplayChoices``; the View tab lists them, then the
/// preferences of its tab (``ViewPreference/tab``), and the Accessibility tab
/// the rest. The View menu lists the same, in the same order.
///
/// A choice wins over everything that otherwise decides the preference: the
/// host's setting, the user's `TUI_*` variable and the scene's own modifiers
/// (`.reduceMotion(_:)`, `.focusBreathing(_:)`, `.keyNotation(_:)`,
/// `.focusFollowsPointer(_:)`). It is applied last of the scene's root
/// statements (``SceneConfiguration/applyRootOverrides(to:)``), so it reaches
/// the page, the bars and every window alike; a view that writes one of the
/// values for its own subtree still decides there, as anywhere.
///
/// Held by the app's render loop and so gone when the app quits: nothing is
/// saved, and the next run starts from the settings again (owner, 2026-11-08:
/// "for now let's not persist them"). Each app has its own, reached through
/// the environment (``EnvironmentValues/viewPreferenceOverrides``).
@MainActor
package final class ViewPreferenceOverrides {
    /// The choices made, by preference.
    private var choices: [ViewPreference: Bool] = [:]

    /// Asks for the frame that draws a new choice.
    private let renderTrigger: () -> Void

    /// The app's own state for the display options, where the scene's
    /// commands hand some to `DisplayCommands`: what a choice of the settings
    /// panel's View tab goes to, as the View menu's does. Posted by the menu
    /// bar as it collects the commands, after the content has drawn, so the
    /// panel goes by the last frame's — the same bindings, frame after frame.
    package var displayBindings = DisplayChoices.Bindings()

    /// Choices for an app whose frames `renderTrigger` asks for.
    package init(renderTrigger: @escaping () -> Void = {}) {
        self.renderTrigger = renderTrigger
    }

    /// The choice made for `preference`, or `nil` for none. Setting one asks
    /// for a frame.
    package subscript(preference: ViewPreference) -> Bool? {
        get { choices[preference] }
        set {
            guard choices[preference] != newValue else { return }
            choices[preference] = newValue
            renderTrigger()
        }
    }

    /// Writes every choice made into `environment`, over what was there.
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
