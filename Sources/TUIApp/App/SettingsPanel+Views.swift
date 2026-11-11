//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsPanel+Views.swift
//
//  The settings panel drawn: a sheet over the window in front, its tabs in a
//  segmented strip that stays put, the tab shown in a scroll view under it,
//  and Done — with Settings for All Programs… beside it, which turns TUI's
//  tabs (SettingsPanel+Tabs.swift) to the person's settings for every program.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
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
                        let level: SettingsLevel = panel.editsAllPrograms ? .allPrograms : .thisProgram
                        let tui = builtIn.compactMap { Self.tab($0.tab, $0.choice, level, context.environment) }
                        // For all programs, TUI's own tabs alone, as TUI
                        // draws them: the app's are this program's.
                        let tabs =
                            switch level {
                            case .thisProgram: appTabs(context) + tui
                            case .allPrograms: tui.filter { $0.levels }
                            }
                        return _SettingsPanelContent(
                            panel: panel, tabs: tabs, offersAllPrograms: tui.contains { $0.levels })
                    })
            }
    }

    /// TUI's `tab`, as the app chose: its own content at `level`, the app's in
    /// its place, or none.
    private static func tab(
        _ tab: BuiltInSettingsTab, _ choice: BuiltInSettingsTabChoice, _ level: SettingsLevel,
        _ environment: EnvironmentValues
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
                case .view: AnyView(_SettingsViewTab(environment: environment, level: level))
                case .accessibility: AnyView(_SettingsAccessibilityTab(environment: environment, level: level))
                }
            return SettingsPanelTab(title: title, isBuiltIn: true, levels: true, content: content)
        }
    }
}

// MARK: - The Panel

/// The panel's box — a `Dialog` titled Settings, as every presented panel
/// of TUI's is drawn, so it stands apart from the dimmed page — holding the
/// tab strip — a segmented control, with a heavier rule between the app's
/// tabs and TUI's — the tab shown under it in a `ScrollView`, which the arrow
/// and paging keys scroll while it overflows, and the Done button in its
/// footer, for the pointer, as the list of shortcuts has.
private struct _SettingsPanelContent: View {
    let panel: SettingsPanel
    let tabs: [SettingsPanelTab]
    /// Whether one of TUI's own tabs is shown, which Settings for All
    /// Programs… turns to the person's settings for all programs.
    let offersAllPrograms: Bool

    var body: some View {
        let service = LocalizationService.shared
        let panel = panel
        let shown = tabs.isEmpty ? 0 : min(max(panel.selection, 0), tabs.count - 1)
        let firstBuiltIn = tabs.firstIndex { $0.isBuiltIn } ?? tabs.count
        let title: LocalizationKey.Menu = panel.editsAllPrograms ? .settingsForAllProgramsTitle : .settingsPanel
        Dialog(title: service.string(for: title), footerAlignment: .trailing) {
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
        } footer: {
            // Done leaves the settings for all programs, back to this
            // program's; then it closes the panel.
            if panel.editsAllPrograms {
                Button(service.string(for: LocalizationKey.Button.done)) { panel.showThisProgram() }
                    .keyboardShortcut(.cancelAction)
            } else {
                ButtonRow {
                    if offersAllPrograms {
                        Button(service.string(for: LocalizationKey.Menu.settingsForAllPrograms)) {
                            panel.showAllPrograms()
                        }
                        .focusID("tui.settings.allPrograms")
                    }
                    Button(service.string(for: LocalizationKey.Button.done)) { panel.dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    /// A tab's title in the strip: its own, or the app's name.
    private static func title(of tab: SettingsPanelTab) -> String {
        tab.title ?? QuitPrompt.applicationName
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

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
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

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
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
