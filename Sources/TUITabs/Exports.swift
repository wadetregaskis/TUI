//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUITabs re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUITabs` gives an app tab
// views (`TabView`, `Tab`, `TabSection`, `TabContent` with its builder and
// modifiers, the tab strip, sidebar and customization, and the tab styles):
// TUIFoundation, and TUILists (a
// `.sidebarAdaptable` tab view lists its tabs in a `List`, and a tab body is
// painted on the lists' lifted surface), so `List` comes with it too; and,
// since 2026-10-23 (decisions A21, owner's A21-TABPOPOVER option 1),
// TUIPresentation, whose adapting presenter a tab's popover is shown with,
// so that it becomes a sheet in a compact size class as a view's popover
// does, and `.presentationCompactAdaptation` on its content comes with it
// too (TUIPresentation re-exports TUIChrome in turn). Beside
// what it gives an importer, it keeps their names, and through
// TUIFoundation's own re-exports the lower and side modules', in scope in
// every file of this module, as they were while TUIFoundation (until step
// B6) and then TUILists (until step C3) compiled these files; each file
// imports TUIFoundation itself as well, and TUILists where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella,
// Sources/TUI, re-exports this module beside TUIFoundation, and so does
// TUIColorPicker, whose panel is a `TabView`.
@_exported import TUIFoundation
@_exported import TUILists
@_exported import TUIPresentation
