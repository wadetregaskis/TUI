//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIPresentation re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIPresentation` gives an app
// the presentations (alerts, confirmation dialogs, `Dialog`, sheets,
// full-screen covers and modals):
// TUIFoundation, and TUIChrome (a presentation draws its notifications
// with Chrome's `notificationHost(width:)`, and a modal docks its presenter's
// focus through Chrome's presentation dock), so `.toolbar`, `.help` and
// `.statusBarItems` come with it too (plan §4). Beside what it gives an
// importer, it keeps their names, and through TUIFoundation's own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIFoundation (until step B5) and then
// TUINavigation (until step C1) compiled these files; each file imports
// TUIFoundation itself as well, and TUIChrome where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUI,
// re-exports this module beside TUIFoundation, and so does
// TUIColorPicker.
@_exported import TUIChrome
@_exported import TUIFoundation
