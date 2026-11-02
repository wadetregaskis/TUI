//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutRegistry.swift
//
//  The per-frame registry keyboard shortcuts register their actions in. Split
//  out of `KeyboardShortcut.swift`, which had grown past the file-length
//  guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Registry

/// The per-frame registry of semantic shortcut actions.
///
/// Buttons carrying a ``KeyboardShortcut`` register their action here during
/// the render pass; ``InputHandler`` triggers the matching action when a
/// Return/Escape falls through the focused control. Cleared at the start of
/// every render pass, so only what's actually on screen can be triggered —
/// and when overlapping surfaces each register (a dialog over a page), the
/// LAST registration wins, which render order makes the topmost surface.
///
/// Below the app's shortcuts sits a tier of framework DEFAULTS
/// (``registerDefault(_:holdsFocus:action:)``), for shortcuts the framework
/// binds for itself, such as a split view's sidebar chord. Any app shortcut on
/// the same trigger beats a default whatever the registration order: under the
/// default `.commandKey(.control)`, SwiftUI's ⌃⌘S and an app's plain ⌘S are the
/// same ⌃S, and the app means its own. This is `RowShortcuts`' rule, "defaults
/// first, then the overrides on top".
///
/// A shortcut registered inside a PANE — a live sheet docked under the page,
/// whose content renders through `renderingPane(_:context:_:)` — is that
/// pane's: it fires while the focus is in the pane, and only then. The page's
/// own (registered outside every pane) fire while the focus is on the page;
/// while it is in a pane, a key equivalent the pane does not bind still
/// reaches the page's, as a key goes up a responder chain, but Return and
/// Escape — the default and cancel actions — are the pane's alone: a field in
/// the sheet that lets Return through must not press the page's default
/// button. A framework default is its pane's by the same rule. Where no pane
/// is drawn, nothing here changes.
///
/// It also knows what each shortcut is called, for the list of what is in force
/// (``listing(activePane:reachesPage:modalSection:)``): a control says, as it
/// registers, and a menu row that only shows a key something else binds says so
/// too (``noteHint(_:title:menu:section:)``).
///
/// Not `Sendable`, like its sibling per-frame services (`MouseEventDispatcher`,
/// `KeyEventDispatcher`): touched only from the main run loop (render pass
/// registration + input dispatch).
package final class KeyboardShortcutRegistry {
    /// An app shortcut's action, whether a held key's repeats run it again,
    /// and when in the frame it was registered (``registrationCount``).
    struct Entry {
        let repeats: Bool
        let action: () -> Void
        let serial: Int
        /// Where it was declared, which decides whether it fires while a modal
        /// holds the keyboard (``Scope``).
        var scope = Scope()
        /// What it is called, where it says.
        var name: Name?
    }

    /// What a shortcut is called, for the list of what is in force.
    struct Name {
        /// The control's words. A closure, because a control with a view for a
        /// label has to draw it to read it, which only the list needs.
        let title: () -> String
        /// The menu it is on (``currentCommandMenu``), or `nil` for the page's.
        let menu: String?
        /// Its place in the frame's registrations.
        let serial: Int
        /// Whether a menu row showing the key names it better: a scene's key
        /// (``registerCommand(_:commandChord:title:action:)``), which the menu
        /// bar's item only shows, and which only says what it is for an app
        /// with no menu bar.
        var yieldsToHint = false
    }

    /// Where a shortcut was declared: the focus section. While a modal section
    /// holds the keyboard only the shortcuts declared in it fire, as nothing
    /// behind an app-modal alert does on macOS, and as neither a window's key
    /// equivalents nor its menu commands do behind its sheet (measured
    /// 2026-10-27, decisions A-MODALS-1). A shortcut declared outside the
    /// presenting view used to fire behind a sheet, though the dimming says the
    /// page is inert. (The menu bar's commands were already inert there: the
    /// menu bar is drawn as a backdrop under a modal, and registers nothing.)
    struct Scope {
        var section: String?

        /// Whether a shortcut of this scope fires while `modalSection` holds the
        /// keyboard (`nil`: no modal does).
        func fires(under modalSection: String?) -> Bool {
            guard let modalSection else { return true }
            return section == modalSection
        }
    }

    /// The app's shortcuts registered outside every pane.
    private var actions: [KeyboardShortcut.Trigger: Entry] = [:]

    /// The app's shortcuts registered inside each pane, by the pane.
    private var paneActions: [String: [KeyboardShortcut.Trigger: Entry]] = [:]

    /// The pane whose content is rendering now, if any: set around it by
    /// `renderingPane(_:context:_:)`, so what registers meanwhile is the
    /// pane's.
    package var currentPane: String? { get { _currentPane } set { _currentPane = newValue } }

    /// ``currentPane``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _currentPane: String?

    /// The menu whose commands are registering now, if any: set around them by
    /// the menu bar, so what registers meanwhile is listed under it.
    package var currentCommandMenu: String? {
        get { _currentCommandMenu }
        set { _currentCommandMenu = newValue }
    }

    /// ``currentCommandMenu``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _currentCommandMenu: String?

    /// How many shortcuts this frame has registered so far: a mark a presenter
    /// takes before its content renders, and hands back to
    /// ``entry(for:registeredAfter:)`` once it has.
    private(set) var registrationCount = 0

    /// A framework default, and whether the view that registered it held the
    /// focus.
    private struct Default {
        let holdsFocus: Bool
        let action: () -> Void
        var scope = Scope()
        var name: Name?
    }

    /// The keys menu rows show and something else binds (``noteHint(_:title:menu:section:)``).
    private var hints: [KeyboardShortcut.Trigger: (name: Name, scope: Scope)] = [:]

    /// The framework defaults registered outside every pane, consulted only
    /// when no app shortcut has the trigger.
    private var defaults: [KeyboardShortcut.Trigger: Default] = [:]

    /// The framework defaults registered inside each pane, by the pane.
    private var paneDefaults: [String: [KeyboardShortcut.Trigger: Default]] = [:]

    /// Clears the frame's registrations (called from the render loop).
    package func beginRenderPass() {
        actions.removeAll(keepingCapacity: true)
        if !paneActions.isEmpty { paneActions.removeAll() }
        currentPane = nil
        defaults.removeAll(keepingCapacity: true)
        if !paneDefaults.isEmpty { paneDefaults.removeAll() }
        if !hints.isEmpty { hints.removeAll(keepingCapacity: true) }
        currentCommandMenu = nil
        registrationCount = 0
    }

    /// Registers `action` for `shortcut`; the last registration in a frame wins
    /// — except over the window's own while the menu bar's commands register
    /// (``registeringCommands(_:)``).
    ///
    /// - Parameter repeats: Whether a held key's repeats run the action again.
    ///   A repeat is told from a press only where the terminal speaks the kitty
    ///   keyboard protocol; in a legacy encoding every repeat is a press and
    ///   runs it. A repeat that does not run it is still taken, so it reaches
    ///   nothing else: holding a button's shortcut never falls through to
    ///   whatever the key means further down.
    /// - Parameter commandChord: The shortcut as written, with its ⌘, where it
    ///   also fires on a real ⌘ (``KeyboardShortcut/commandChord(matching:)``):
    ///   the same action is registered on that trigger too. `nil` — the
    ///   default, and every shortcut's unless the app asked — registers
    ///   nothing more.
    /// - Parameter title: What the control is called, for the list of what is
    ///   in force. `nil` leaves it off the list.
    func register(
        _ shortcut: KeyboardShortcut, commandChord: KeyboardShortcut? = nil, repeats: Bool = true,
        section: String? = nil, title: (() -> String)? = nil, action: @escaping () -> Void
    ) {
        registrationCount += 1
        let entry = Entry(
            repeats: repeats, action: action, serial: registrationCount,
            scope: Scope(section: section), name: name(title))
        insert(entry, on: shortcut.trigger)
        if let commandChord { insert(entry, on: commandChord.trigger) }
    }

    /// `title`, as a name registered now.
    private func name(_ title: (() -> String)?) -> Name? {
        title.map { Name(title: $0, menu: currentCommandMenu, serial: registrationCount) }
    }

    /// Records that a menu row shows `shortcut`, called `title`, without binding
    /// it (`View.keyboardShortcutHint(_:)`): whatever does bind the key does what
    /// the row does, so the key is in force under the row's name. A binding that
    /// says what it is called comes first.
    ///
    /// - Parameter menu: The section to list it under, where that is not
    ///   ``currentCommandMenu``.
    package func noteHint(
        _ shortcut: KeyboardShortcut, title: @escaping () -> String, menu: String? = nil, section: String? = nil
    ) {
        registrationCount += 1
        let name = Name(title: title, menu: menu ?? currentCommandMenu, serial: registrationCount)
        hints[shortcut.trigger] = (name, Scope(section: section))
    }

    /// Puts `entry` on `trigger`, in the pane rendering now or on the page —
    /// unless the menu bar's commands are registering and something already
    /// holds the trigger (``registeringCommands(_:)``).
    private func insert(_ entry: Entry, on trigger: KeyboardShortcut.Trigger) {
        if let currentPane {
            if registersCommands, paneActions[currentPane]?[trigger] != nil { return }
            paneActions[currentPane, default: [:]][trigger] = entry
        } else {
            if registersCommands, actions[trigger] != nil { return }
            actions[trigger] = entry
        }
    }

    /// Registers `action` for `shortcut`, which `KeyboardShortcut.resolved(commandKey:)`
    /// has resolved: for a framework command outside a view — a scene's
    /// `.keyboardShortcut` (TUIApp) — inside ``registeringCommands(_:)``,
    /// so the window's own shortcut on the key keeps it. A held key does not
    /// repeat it. `commandChord` and `title` are ``register(_:commandChord:repeats:section:title:action:)``'s.
    package func registerCommand(
        _ shortcut: KeyboardShortcut, commandChord: KeyboardShortcut? = nil, title: (() -> String)? = nil,
        action: @escaping () -> Void
    ) {
        register(shortcut, commandChord: commandChord, repeats: false, title: title, action: action)
        if let entry = actions[shortcut.trigger], entry.serial == registrationCount {
            actions[shortcut.trigger]?.name?.yieldsToHint = true
        }
    }

    /// Whether what registers now is the menu bar's commands — see
    /// ``registeringCommands(_:)``.
    private var registersCommands = false

    /// Runs `body`, in which what registers is the menu bar's commands: a
    /// command's shortcut is registered unless the window's content already
    /// registered one on its trigger this frame, which keeps it.
    ///
    /// The menu bar's commands render after the content, so that a command
    /// reading the focused view's `@FocusedValue` reads this frame's, and
    /// "the last registration wins" would have handed every shared chord to
    /// the menu bar. AppKit documents the other order: a key equivalent goes
    /// to the key window's views first, and to the main menu only if none
    /// takes it (Cocoa Event Handling Guide, "The Path of Key Events").
    /// UNMEASURED in SwiftUI itself: the lane's probe
    /// (`Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`) could not make its window key on this machine,
    /// and with no key window the menu took the key.
    package func registeringCommands<Result>(_ body: () -> Result) -> Result {
        let outer = registersCommands
        registersCommands = true
        defer { registersCommands = outer }
        return body()
    }

    /// What `shortcut` runs, and whether a held key repeats it, if its
    /// registration — the last this frame on its trigger — came after `mark`,
    /// a ``registrationCount`` taken earlier in the frame: a shortcut
    /// registered by whatever rendered in between, and not since overridden.
    ///
    /// How a presenter finds its content's cancel button
    /// (``DismissalGate/cancelButton``).
    ///
    /// Among the shortcuts of the pane rendering now (``currentPane``), or of
    /// the page outside every pane: a live sheet's content registers in its
    /// pane, and its presenter asks while the pane is still rendering.
    func entry(for shortcut: KeyboardShortcut, registeredAfter mark: Int) -> Entry? {
        let table = currentPane.map { paneActions[$0] ?? [:] } ?? actions
        guard let entry = table[shortcut.trigger], entry.serial > mark else { return nil }
        return entry
    }

    /// The app's shortcut on `trigger` that fires while the focus is in
    /// `activePane` (`nil`: on the page): the pane's own; else, for anything
    /// but Return and Escape, the page's — see the type's discussion.
    ///
    /// Not the page's while `reachesPage` is false: a modal presented from
    /// inside the pane — an alert over a live sheet — holds the keyboard, and
    /// the page behind it, live as it is, must not fire from under it.
    private func appEntry(
        for trigger: KeyboardShortcut.Trigger, activePane: String?, reachesPage: Bool = true,
        modalSection: String? = nil
    ) -> Entry? {
        Self.paneScoped(trigger, page: actions, panes: paneActions, activePane: activePane, reachesPage: reachesPage)
            .flatMap { $0.scope.fires(under: modalSection) ? $0 : nil }
    }

    /// The framework default on `trigger` that fires while the focus is in
    /// `activePane`, by the rule an app shortcut fires by (``appEntry``).
    ///
    /// The page's, from inside a pane, only where the page's app shortcuts
    /// reach: a split view on the page registers its sidebar chord as a
    /// default, and an alert opened in a live sheet must hold it as it holds
    /// the page's own ⌃N.
    private func defaultEntry(
        for trigger: KeyboardShortcut.Trigger, activePane: String?, reachesPage: Bool, modalSection: String?
    ) -> Default? {
        Self.paneScoped(trigger, page: defaults, panes: paneDefaults, activePane: activePane, reachesPage: reachesPage)
            .flatMap { $0.scope.fires(under: modalSection) ? $0 : nil }
    }

    /// What fires on `trigger` with the focus in `activePane` (`nil`: on the
    /// page), of what was registered on the `page` and in the `panes`: the
    /// pane's own; else, for anything but Return and Escape, the page's,
    /// where `reachesPage`.
    private static func paneScoped<Value>(
        _ trigger: KeyboardShortcut.Trigger, page: [KeyboardShortcut.Trigger: Value],
        panes: [String: [KeyboardShortcut.Trigger: Value]], activePane: String?, reachesPage: Bool
    ) -> Value? {
        guard let activePane else { return page[trigger] }
        if let value = panes[activePane]?[trigger] { return value }
        switch trigger {
        case .defaultAction, .cancelAction: return nil
        case .key: return reachesPage ? page[trigger] : nil
        }
    }

    /// The shortcuts that would fire now, among those that say what they are
    /// called, in the order they registered: what was on the screen when the
    /// frame was drawn, by the rules ``trigger(for:activePane:reachesPage:modalSection:)``
    /// fires by, so each key appears once, under whatever a press would reach.
    ///
    /// Only what registers here. An `onKeyPress` or `onKeyEvent` handler is a
    /// closure that nothing can ask what it answers to.
    package func listing(
        activePane: String? = nil, reachesPage: Bool = true, modalSection: String? = nil
    ) -> [ListedShortcut] {
        var triggers = Set(actions.keys).union(defaults.keys).union(hints.keys)
        if let activePane {
            if let own = paneActions[activePane] { triggers.formUnion(own.keys) }
            if let own = paneDefaults[activePane] { triggers.formUnion(own.keys) }
        }
        var named: [(trigger: KeyboardShortcut.Trigger, name: Name)] = []
        for trigger in triggers {
            let app = appEntry(
                for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)
            let bound =
                app == nil
                ? defaultEntry(
                    for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)?.name
                : app?.name
            let hint = hints[trigger].flatMap { $0.scope.fires(under: modalSection) ? $0.name : nil }
            if let name = (bound?.yieldsToHint == true ? hint : nil) ?? bound ?? hint {
                named.append((trigger, name))
            }
        }
        return named.sorted { $0.name.serial < $1.name.serial }.map {
            ListedShortcut(key: Self.keyName(of: $0.trigger), title: $0.name.title(), menu: $0.name.menu)
        }
    }

    /// `trigger` as it is drawn.
    private static func keyName(of trigger: KeyboardShortcut.Trigger) -> String {
        switch trigger {
        case .defaultAction: KeySymbols.key(.enter)
        case .cancelAction: KeySymbols.key(.escape)
        case .key(let key, let modifiers): KeySymbols.chord(Key(key), modifiers)
        }
    }

    /// Registers a framework default for `shortcut`, which fires only when no
    /// app shortcut has the same trigger, however the two were ordered.
    ///
    /// Among defaults on one trigger, one registered by a view that holds the
    /// focus (`holdsFocus`) beats one that does not, and otherwise the FIRST
    /// registration wins. First, not last as for app shortcuts, because a
    /// framework control registering after its content has rendered finishes
    /// after anything nested inside it: the innermost of several nested
    /// focus-holding views registers first.
    ///
    /// Like an app shortcut, a default registered inside a pane is the pane's
    /// (``currentPane``).
    ///
    /// - Parameter title: What it is called, for the list of what is in force.
    ///   `nil` leaves it off the list.
    package func registerDefault(
        _ shortcut: KeyboardShortcut, holdsFocus: Bool = false, section: String? = nil,
        title: (() -> String)? = nil, action: @escaping () -> Void
    ) {
        let trigger = shortcut.trigger
        let existing = currentPane.map { paneDefaults[$0]?[trigger] } ?? defaults[trigger]
        if let existing, existing.holdsFocus || !holdsFocus { return }
        registrationCount += 1
        let entry = Default(
            holdsFocus: holdsFocus, action: action, scope: Scope(section: section), name: name(title))
        if let currentPane {
            paneDefaults[currentPane, default: [:]][trigger] = entry
        } else {
            defaults[trigger] = entry
        }
    }

    /// Runs the action matching a fallen-through key event, if any.
    ///
    /// Unmodified Return/Escape drive the two semantic roles; a character key
    /// drives a key equivalent whose modifiers match exactly what the terminal
    /// reported. Exactly, not "at least": a shortcut on plain "q" must not fire
    /// on Ctrl-Q. The event → trigger rule itself is
    /// ``KeyboardShortcut/trigger(for:)``, shared with the row-shortcut table.
    ///
    /// - Parameters:
    ///   - activePane: The pane the focus is in (`FocusManager.activePaneID`),
    ///     or `nil` on the page.
    ///   - reachesPage: Whether a key equivalent the pane does not bind may
    ///     reach the page's: not while a modal section holds the focus.
    ///   - modalSection: The modal section holding the keyboard
    ///     (`FocusManager.activeModalSectionID`), whose own shortcuts are then the
    ///     only ones that fire (``Scope``).
    package func trigger(
        for event: KeyEvent, activePane: String? = nil, reachesPage: Bool = true, modalSection: String? = nil
    ) -> Bool {
        triggerOne(event, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)
    }

    /// ``trigger(for:activePane:reachesPage:modalSection:)`` for `event` as it
    /// is.
    private func triggerOne(
        _ event: KeyEvent, activePane: String?, reachesPage: Bool, modalSection: String?
    ) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        let entry = appEntry(for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)
        if event.phase == .repeat, let entry, !entry.repeats { return true }
        guard
            let action = entry?.action
                ?? defaultEntry(
                    for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection)?.action
        else { return false }
        AmbientApp.renderState?.noteControlActivated()
        action()
        return true
    }

    /// Whether an app shortcut is registered for `event`: what ``trigger(for:)``
    /// would match, without running anything.
    ///
    /// App shortcuts only. A framework default never takes a key from the
    /// control holding the focus, so it has no say here.
    ///
    /// For `InputHandler`, which asks it before offering a focused text control
    /// one of its editing chords. An app shortcut on the chord takes the key
    /// instead; see `TextEditingCommand.givesWayToKeyboardShortcuts`.
    package func hasAppShortcut(
        for event: KeyEvent, activePane: String? = nil, reachesPage: Bool = true, modalSection: String? = nil
    ) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return appEntry(for: trigger, activePane: activePane, reachesPage: reachesPage, modalSection: modalSection) != nil
    }

    /// Whether any shortcut is registered for `event`, the app's or a
    /// framework default: what ``trigger(for:)`` would match, without
    /// running anything. For the user's quit key, which the driver keeps
    /// unless a binding the framework can see is on a chord its byte could be
    /// for (`InputHandler.quitKeyBindings(byte:hostAliases:)`).
    ///
    /// On the page or in any pane, wherever the focus is: the driver's quit
    /// is set once a frame, for the whole screen, so a pane's binding masks it
    /// as the page's does. Which of them the key then reaches is the pane
    /// rule's (``trigger(for:activePane:reachesPage:)``).
    package func hasShortcut(for event: KeyEvent) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return actions[trigger] != nil || defaults[trigger] != nil
            || paneActions.values.contains { $0[trigger] != nil }
            || paneDefaults.values.contains { $0[trigger] != nil }
    }
}

// MARK: - Listing

/// One shortcut in force: its key as it is drawn, what it is called, and the
/// menu it is on, or `nil` for the page's.
package struct ListedShortcut: Equatable, Sendable {
    package let key: String
    package let title: String
    package let menu: String?

    package init(key: String, title: String, menu: String? = nil) {
        self.key = key
        self.title = title
        self.menu = menu
    }
}
