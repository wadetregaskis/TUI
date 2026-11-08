//  🖥️ TUI — A Terminal UI framework for Swift
//  ViewPreferenceOverrides.swift
//
//  What the person chose in the menu bar's View menu for this run: the
//  accessibility and display preferences they turned on or off there, which
//  win over the system's setting, the `TUI_*` variable and the app's own
//  scene modifiers until the app quits. Never saved.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - The Preferences

/// A preference the View menu turns on or off for the rest of the run
/// (``ViewPreferenceOverrides``), each a `Bool` in the frame's environment.
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
        }
    }
}

// MARK: - The Choices

/// What the person chose in the View menu for this run, one choice per
/// ``ViewPreference``, or none where they left it as it came.
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
