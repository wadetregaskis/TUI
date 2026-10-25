//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentClassAuditTests.swift
//
//  Every class a framework environment key holds, with why comparing it by
//  identity cannot serve a row stale (Option C, C2b's audit). An environment
//  stamp compares a class by identity; a class whose drawn state changed in
//  place, with nothing written, would leave a row re-checked as unchanged.
//  A key whose value is a class and is not here fails, so a new one gets a
//  decision before Option C can serve under it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@MainActor
@Suite("Every class in the framework's environment has a decision")
struct EnvironmentClassAuditTests {

    /// The decision for each class, and its reason.
    private static let decisions: [String: String] = [
        // A new object every render of its provider: a stamp holding it never
        // equals the next render's, so nothing below it is ever re-checked as
        // unchanged. Safe; it loses the saving where it is set.
        "AssignedFocusID": "new each render (an offer the first focusable claims)",
        "FocusHandoffOffer": "new each render (an offer the first focusable claims)",
        "PreferredFocusOffer": "new each render (an offer the first focusable claims)",
        "KeyboardShortcutAssignment": "new each render of the shortcut modifier",
        "MenuSubmenu": "new each render of a submenu row",
        "GlassEffectGathering": "new each render of the glass container",
        "ScrollPositionBinding": "new each render of the provider",
        // Services and mailboxes: kept by the app, posted into or called at
        // event time; a row draws nothing from their state.
        "DepartedUndoSteps": "service: handed to a text field's handler for event time",
        "UndoManager": "service: handed to a text field's handler for event time",
        "TerminalBell": "service: rung at event time",
        "TypedClipboard": "service: read at event time",
        "KeysAfterFrame": "service: keys queued for after the frame",
        "ButtonKeyExtras": "provider-kept (@State); its key closures are used at event time, nothing is drawn from it",
        "MenuOpenAction": "provider-kept (@State); called at event time to open a menu",
        "DismissalGate": "provider-kept (state storage); asked at event time whether a dismissal may proceed",
        "MenuRowSink": "mailbox kept by the menu's controller: rows publish into it",
        "_TabMenuOpeners": "mailbox: each tab files its menu's opener into it every frame",
        "SearchSelectionBox": "provider-kept box, its binding refreshed every render; the field reads it where it draws",
        "ModifierKeyMonitor": "service: its state is read through the monitor's own invalidation",
        "ScrollToRegistry": "mailbox: scroll targets are registered into it",
        "TerminalImageStore": "mailbox: pictures are registered into it for the writer",
        "PresentedWindowSlot": "app level: read by the presented window's root, not by rows",
        "SceneOverlayList": "app level: read by the scene's root, not by rows",
        "ScreenSelection": "chrome level: read by the window's chrome host, not by rows",
        // Kept by their provider across frames, and drawn from by views below:
        // every in-place change of what they draw is invalidated explicitly.
        "DragAndDropSession": "provider-kept; lifting and landing invalidate the view (RenderCycle.md, cache invalidation)",
        "TooltipState": "provider-kept; the hover that makes a view the candidate invalidates it",
        "ThemeManager": "provider-kept; a theme change clears the whole cache",
        "NavigationBarItems": "provider-kept; its items are drawn by the stack's bar, not by the rows below",
        "WindowChromeState": "provider-kept; its bars are drawn by the chrome host, not by the rows below",
        // Declared neutral at the key (EnvironmentStampTests lists them).
        "AnimationScheduler": "neutral key", "CursorTimer": "neutral key", "FocusManager": "neutral key",
        "KeyEventDispatcher": "neutral key", "KeyboardShortcutRegistry": "neutral key", "LifecycleManager": "neutral key",
        "MouseEventDispatcher": "neutral key", "PreferenceStorage": "neutral key", "RenderCache": "neutral key",
        "RowEditRestrictions": "neutral key", "StateStorage": "neutral key", "StatusBarState": "neutral key",
        "VolatileReadTracker": "neutral key",
    ]

    @Test("Each class a framework environment key holds is in the table, and the table names no other")
    func everyClassDecided() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var texts: [String] = []
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" && file.path.contains("/TUIkit") {
            texts.append(try String(contentsOf: file, encoding: .utf8))
        }
        let all = texts.joined(separator: "\n")
        var classes: Set<String> = []
        for match in all.matches(of: /(?:final )?class (\w+)\b/) { classes.insert(String(match.1)) }
        var held: Set<String> = []
        for match in all.matches(of: /struct \w+: EnvironmentKey[^{]*\{[^}]*?defaultValue: (\w+)/) {
            let type = String(match.1)
            if classes.contains(type) { held.insert(type) }
        }
        let undecided = held.subtracting(Self.decisions.keys)
        #expect(undecided.isEmpty, "classes in the environment with no decision: \(undecided.sorted())")
    }
}
