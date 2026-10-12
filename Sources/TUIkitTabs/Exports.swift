//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitTabs re-exports the modules it is built on, as each module of the
// split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitTabs` gives an app tab
// views (`TabView`, `Tab`, `TabSection`, `TabContent` with its builder and
// modifiers, the tab strip, sidebar and customization, and the tab styles):
// TUIkitFoundation, and TUIkitLists (a
// `.sidebarAdaptable` tab view lists its tabs in a `List`, and a tab body is
// painted on the lists' lifted surface), so `List` comes with it too. Beside
// what it gives an importer, it keeps their names, and through
// TUIkitFoundation's own re-exports the lower and side modules', in scope in
// every file of this module, as they were while TUIkitFoundation (until step
// B6) and then TUIkitLists (until step C3) compiled these files; each file
// imports TUIkitFoundation itself as well, and TUIkitLists where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella,
// Sources/TUIkit, re-exports this module beside TUIkitFoundation, and so does
// TUIkitColorPicker, whose panel is a `TabView`.
@_exported import TUIkitFoundation
@_exported import TUIkitLists
