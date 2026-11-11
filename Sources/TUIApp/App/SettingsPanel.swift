//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsPanel.swift
//
//  The settings panel every app has, on F2: the app's `Settings` scene's
//  tabs, then TUI's View and Accessibility tabs. Its state, its key, and what
//  the scene presenter draws it from.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The State

/// Whether the settings panel is up, which tab it shows, and the key it
/// opens on: what the input chain and the scene presenter share, as
/// ``KeyboardShortcutOverlay`` is for the list of shortcuts.
///
/// The owner's (2026-11-08): "we should never force apps to have a menu bar
/// … Having other ways to adjust view settings, like themes, palettes,
/// accessibility settings, would be good." One per run, made by what runs the
/// app. Nothing it holds is
/// saved: TUI's own choices last for the run (``ViewPreferenceOverrides``).
/// Not `Sendable`: asked from key handlers and frames, all on the main actor.
final class SettingsPanel {
    /// The key that opens and closes the panel: F2 unless a scene moved it
    /// (`Scene.settingsPanelKey(_:)`); adopted each frame.
    var key: Key? = SettingsPanel.defaultKey

    /// F2: TUI's keys together at the start of the row, after F1's list of
    /// shortcuts (the owner, 2026-11-08).
    static let defaultKey = Key.f2

    /// Whether the panel has a tab to show; adopted each frame. A panel
    /// with none closes.
    var isAvailable = true {
        didSet { if !isAvailable, isPresented { dismiss() } }
    }

    /// Whether the panel is up.
    private(set) var isPresented = false

    /// Whether the scene presenter draws the panel. It stays on once the
    /// panel has been up: closing it takes a frame with the sheet drawn and
    /// not presented, which hands the page its focus back.
    private(set) var isHosted = false

    /// The tab shown, by its place in the strip.
    private(set) var selection = 0

    /// Asks for a frame.
    private let requestFrame: () -> Void

    /// - Parameter requestFrame: Asks for a frame, to show or remove the
    ///   panel, or change its tab.
    init(requestFrame: @escaping () -> Void) {
        self.requestFrame = requestFrame
    }

    /// Puts the panel up, where it has a tab to show.
    func present() {
        guard isAvailable, !isPresented else { return }
        isPresented = true
        isHosted = true
        requestFrame()
    }

    /// Takes the panel down.
    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        requestFrame()
    }

    /// Shows the tab at `index` in the strip.
    func select(_ index: Int) {
        guard selection != index else { return }
        selection = index
        requestFrame()
    }
}

// MARK: - The Key

extension InputHandler {
    /// The last layer's settings key, F2 unless the scene moved it: takes the
    /// panel down where it's up, and otherwise puts it up. So anything of the
    /// app's on the key has been asked already — a handler, a
    /// `.keyboardShortcut`, a status-bar item — as for F1's list
    /// (``runKeyboardShortcutOverlayKey(_:inputGrabbed:)``), and the tooltip
    /// help key, where the app moved it there, keeps it.
    ///
    /// Not over another modal surface, an open drop-down or the quit
    /// question: the panel is a sheet of its own, and opens over the page. A
    /// held key opens it once. Nor while F1's list is up, over the panel or
    /// not: the list holds the keyboard, and the key would close a panel
    /// out of sight beneath it.
    ///
    /// - Returns: Whether `event` was taken.
    func runSettingsPanelKey(_ event: KeyEvent, inputGrabbed: Bool) -> Bool {
        guard let settingsPanel, let key = settingsPanel.key, event.key == key, !event.shift,
            tooltipState?.helpKey != key, shortcutOverlay?.isPresented != true
        else { return false }
        if settingsPanel.isPresented {
            if event.phase != .repeat { settingsPanel.dismiss() }
            return true
        }
        guard settingsPanel.isAvailable, !inputGrabbed, !focusManager.activeSectionIsModal,
            quitPrompt?.isAsking != true
        else { return false }
        if event.phase != .repeat { settingsPanel.present() }
        return true
    }
}

// MARK: - What the Presenter Draws

extension ScenePresenter {
    /// The app's `Settings` scene, if it declares one.
    var settingsEntry: SceneCatalog.OverlayEntry? {
        overlayEntries.first { $0.scene.isSettings }
    }

    /// What the app's scenes state of the panel, in the order they are asked:
    /// the `Settings` scene's, then the window scenes' as declared. The first
    /// to state a thing decides it.
    private var settingsPanelStatements: [SceneConfiguration] {
        (settingsEntry.map { [$0.configuration] } ?? []) + entries.map(\.configuration)
    }

    /// What the app said of TUI's `tab`: shown, unless a scene said otherwise.
    func builtInSettingsTab(_ tab: BuiltInSettingsTab) -> BuiltInSettingsTabChoice {
        settingsPanelStatements.lazy.compactMap { $0.builtInSettingsTabs[tab] }.first ?? .shown
    }

    /// The key the panel opens on: F2, unless a scene moved it or took it
    /// away.
    var settingsPanelKey: Key? {
        for configuration in settingsPanelStatements {
            if let stated = configuration.settingsPanelKey { return stated }
        }
        return SettingsPanel.defaultKey
    }

    /// Whether the panel has a tab to show: the app's `Settings` scene, or
    /// one of TUI's it left in. What ``EnvironmentValues/openSettings``, the
    /// menu bar's Settings… and the panel's keys go by.
    var hasSettings: Bool {
        settingsEntry != nil || BuiltInSettingsTab.allCases.contains { builtInSettingsTab($0).isShown }
    }

    /// Presents the panel over the window in front, if it has a tab to show;
    /// where it is up already, it stays.
    func presentSettings() {
        settingsPanel.present()
    }

    /// The panel, as the presenter draws it over the window in front; `nil`
    /// until it has first been put up.
    var settingsPanelOverlay: SceneOverlay? {
        guard settingsPanel.isHosted else { return nil }
        var appTabs: @MainActor (RenderContext) -> [SettingsPanelTab] = { _ in [] }
        if let entry = settingsEntry {
            // The `Settings` scene's statements reach its own content alone,
            // as they did its sheet: its tabs, and the walk that finds them,
            // which may evaluate the body of a view of the app's own. Found
            // where the panel draws, so that body's `@State` is bound there.
            let configuration = entry.configuration
            let scene = entry.scene
            appTabs = { context in
                var walk = context.withChildIdentity(type: _SettingsContentWalk.self)
                configuration.applyRootOverrides(to: &walk.environment)
                return scene.settingsTabs(in: walk).map { tab in
                    SettingsPanelTab(
                        title: tab.title, isBuiltIn: false,
                        content: AnyView(_SceneConfiguredContent(configuration: configuration, content: tab.content)))
                }
            }
        }
        let builtIn = BuiltInSettingsTab.allCases.map { ($0, builtInSettingsTab($0)) }
        return SceneOverlay(
            key: "settings-panel", configuration: SceneConfiguration(),
            view: AnyView(_SettingsPanelSheet(panel: settingsPanel, appTabs: appTabs, builtIn: builtIn)))
    }
}

/// One tab of the panel: its title — `nil` for the app's name — whether it
/// is one of TUI's, and its content.
struct SettingsPanelTab {
    let title: String?
    let isBuiltIn: Bool
    let content: AnyView
}

// MARK: - A Scene's Statements, on Its Content

/// `content` under a scene's root statements — its `.environment`, its
/// palette — as an overlay scene's view is drawn (``_SceneOverlayHost``):
/// the `Settings` scene's, on its tabs alone.
private struct _SceneConfiguredContent: View, Renderable, Layoutable {
    let configuration: SceneConfiguration
    let content: AnyView

    var body: Never { fatalError("_SceneConfiguredContent renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: configured(context))
    }

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: configured(context))
    }

    private func configured(_ context: RenderContext) -> RenderContext {
        var context = context
        configuration.applyRootOverrides(to: &context.environment)
        return context
    }
}
