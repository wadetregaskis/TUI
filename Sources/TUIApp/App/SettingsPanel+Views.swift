//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsPanel+Views.swift
//
//  The settings panel drawn: a sheet over the window in front, its tabs in a
//  segmented strip that stays put, the tab shown in a scroll view under it,
//  and TUI's View and Accessibility tabs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIForms
import TUIFoundation
import TUIPickers
import TUIPresentation

// MARK: - The Sheet

/// The panel as a sheet over the window in front, held by the presentation
/// layer as any sheet is — its focus section, its Escape and its dimming — as
/// the list of shortcuts is (``_KeyboardShortcutOverlaySheet``).
struct _SettingsPanelSheet: View {
    let panel: SettingsPanel
    /// The app's tabs, found where the panel is drawn
    /// (``ScenePresenter/settingsPanelOverlay``).
    let appTabs: @MainActor (RenderContext) -> [SettingsPanelTab]
    let builtIn: [(tab: BuiltInSettingsTab, choice: BuiltInSettingsTabChoice)]

    var body: some View {
        let panel = panel
        let appTabs = appTabs
        EmptyView()
            .sheet(
                isPresented: Binding(
                    get: { panel.isPresented },
                    set: { if !$0, panel.isPresented { panel.dismiss() } })
            ) {
                _FittedToContent(
                    content: _ContextReader { context in
                        _SettingsPanelContent(
                            panel: panel,
                            tabs: appTabs(context)
                                + builtIn.compactMap { Self.tab($0.tab, $0.choice, context.environment) })
                    })
            }
    }

    /// TUI's `tab`, as the app chose: its own content, the app's in its
    /// place, or none.
    private static func tab(
        _ tab: BuiltInSettingsTab, _ choice: BuiltInSettingsTabChoice, _ environment: EnvironmentValues
    ) -> SettingsPanelTab? {
        let title = LocalizationService.shared.string(for: tab == .view ? .view : LocalizationKey.Menu.accessibility)
        switch choice {
        case .hidden:
            return nil
        case .replaced(let content):
            return SettingsPanelTab(title: title, isBuiltIn: true, content: content)
        case .shown:
            let content =
                switch tab {
                case .view: AnyView(_SettingsViewTab(choices: DisplayChoices(environment: environment)))
                case .accessibility: AnyView(_SettingsAccessibilityTab(environment: environment))
                }
            return SettingsPanelTab(title: title, isBuiltIn: true, content: content)
        }
    }
}

// MARK: - The Panel

/// The tab strip — a segmented control, with a heavier rule between the
/// app's tabs and TUI's — the tab shown under it in a `ScrollView`, which the
/// arrow and paging keys scroll while it overflows, and the Done button, for
/// the pointer, as the list of shortcuts has.
private struct _SettingsPanelContent: View {
    let panel: SettingsPanel
    let tabs: [SettingsPanelTab]

    var body: some View {
        let service = LocalizationService.shared
        let panel = panel
        let shown = tabs.isEmpty ? 0 : min(max(panel.selection, 0), tabs.count - 1)
        let firstBuiltIn = tabs.firstIndex { $0.isBuiltIn } ?? tabs.count
        // Done at the trailing edge of the strip and the tab, whichever is
        // wider, without widening the panel past them.
        VStack(alignment: .trailing, spacing: 1) {
            VStack(alignment: .leading, spacing: 1) {
                if tabs.count > 1 {
                    Picker(
                        service.string(for: LocalizationKey.Menu.settingsPanel),
                        selection: Binding(get: { shown }, set: { panel.select($0) })
                    ) {
                        ForEach(0..<firstBuiltIn, id: \.self) { index in
                            Text(verbatim: Self.title(of: tabs[index])).tag(index)
                        }
                        if firstBuiltIn > 0, firstBuiltIn < tabs.count { Divider() }
                        ForEach(firstBuiltIn..<tabs.count, id: \.self) { index in
                            Text(verbatim: Self.title(of: tabs[index])).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if !tabs.isEmpty {
                    ScrollView {
                        tabs[shown].content.id(shown)
                    }
                }
            }
            Button(service.string(for: LocalizationKey.Button.done)) { panel.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 1)
    }

    /// A tab's title in the strip: its own, or the app's name.
    private static func title(of tab: SettingsPanelTab) -> String {
        tab.title ?? QuitPrompt.applicationName
    }
}

// MARK: - TUI's Tabs

/// View: the palette, the border style and the control style, as the menu
/// bar's `DisplayCommands` offers them — one model (``DisplayChoices``), so
/// the two agree.
private struct _SettingsViewTab: View {
    let choices: DisplayChoices

    var body: some View {
        Form {
            choices.pickers
        }
    }
}

/// Accessibility: the View menu's checks, each turning its preference on or
/// off for the rest of the run over the system's setting, the `TUI_*`
/// variable and the scene's modifiers — the same choices the menu makes
/// (``ViewPreferenceOverrides``), so the two agree. Never saved.
private struct _SettingsAccessibilityTab: View {
    let environment: EnvironmentValues

    var body: some View {
        let service = LocalizationService.shared
        let overrides = environment.viewPreferenceOverrides
        let on = Set(ViewPreference.allCases.filter { $0.isOn(in: environment) })
        Form {
            ForEach(ViewPreference.allCases, id: \.self) { preference in
                Toggle(
                    service.string(for: preference.title),
                    isOn: Binding(get: { on.contains(preference) }, set: { overrides?[preference] = $0 }))
            }
        }
        .disabled(overrides == nil)
    }
}

// MARK: - Reading the Context

/// `content`, made from the context it is drawn in: the environment TUI's
/// tabs read what is in force from, as the menu bar's items are made from the
/// environment the bar is drawn in, and the identity the app's tabs are found
/// at, where the body of a view of the app's own holding its tab view binds
/// its `@State`. No state of its own.
private struct _ContextReader<Content: View>: View, Renderable, Layoutable {
    let content: @MainActor (RenderContext) -> Content

    var body: Never { fatalError("_ContextReader renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content(context), context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content(context), proposal: proposal, context: context)
    }
}

/// `content` at its ideal size, or the space it is given where that is less:
/// the panel as small as the tab shown, up to the terminal, where the tab
/// scrolls under the strip. Its scroll view and its Done row would otherwise
/// take all a sheet offers, as they should once the space is short. No state
/// of its own.
private struct _FittedToContent<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never { fatalError("_FittedToContent renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let size = fittedSize(available: CellSize(width: context.availableWidth, height: context.availableHeight), context)
        var fitted = context
        fitted.availableWidth = size.width
        fitted.availableHeight = size.height
        return TUIView.renderToBuffer(content, context: fitted)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let available = CellSize(
            width: proposal.width ?? context.availableWidth, height: proposal.height ?? context.availableHeight)
        let size = fittedSize(available: available, context)
        return ViewSize.fixed(size.width, size.height)
    }

    /// The content's ideal size, no larger than `available`.
    private func fittedSize(available: CellSize, _ context: RenderContext) -> CellSize {
        let ideal = measureChild(content, proposal: .unspecified, context: context)
        return CellSize(width: min(ideal.width, available.width), height: min(ideal.height, available.height))
    }
}
