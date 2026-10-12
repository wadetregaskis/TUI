//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUIkitPresentation re-exports the modules it is built on, as each module of
// the split re-exports its direct dependencies (Documentation/Historical/Module
// split plan, revision 4, §4), so `import TUIkitPresentation` gives an app
// the presentations (alerts, confirmation dialogs, `Dialog`, sheets,
// full-screen covers and modals):
// TUIkitFoundation, and TUIkitChrome (a presentation draws its notifications
// with Chrome's `notificationHost(width:)`, and a modal docks its presenter's
// focus through Chrome's presentation dock), so `.toolbar`, `.help` and
// `.statusBarItems` come with it too (plan §4). Beside what it gives an
// importer, it keeps their names, and through TUIkitFoundation's own
// re-exports the lower and side modules', in scope in every file of this
// module, as they were while TUIkitFoundation (until step B5) and then
// TUIkitNavigation (until step C1) compiled these files; each file imports
// TUIkitFoundation itself as well, and TUIkitChrome where it uses it
// (CONTRIBUTING.md, "Crossing a module boundary"). The umbrella, Sources/TUIkit,
// re-exports this module beside TUIkitFoundation, and so does
// TUIkitColorPicker.
@_exported import TUIkitChrome
@_exported import TUIkitFoundation
