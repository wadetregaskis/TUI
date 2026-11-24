//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutOverlay.swift
//
//  The list of the keys in force now, on F1: what an app gets for nothing, and
//  how it declines it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIPresentation

// MARK: - Public API

extension Scene {
    /// Turns off the list of keyboard shortcuts that F1 shows, and the Help
    /// menu's item for it. F1 then goes unanswered, like any key nothing takes.
    ///
    /// An app that binds F1 itself doesn't need this: its binding comes first,
    /// and the list stays in the Help menu, if there is one.
    ///
    /// ```swift
    /// WindowGroup { EditorView() }
    ///     .keyboardShortcutOverlayDisabled()
    /// ```
    ///
    /// TUI-specific. A Mac has its menu bar's Help search, and SwiftUI has nothing
    /// to set.
    ///
    /// - Parameter isDisabled: Whether the list is off.
    /// - Returns: A scene whose F1 shows no list.
    public func keyboardShortcutOverlayDisabled(_ isDisabled: Bool = true) -> some Scene {
        _EnvironmentScene(content: self) { $0.keyboardShortcutOverlayDisabled = isDisabled }
    }
}

// MARK: - Environment

private struct KeyboardShortcutOverlayDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the scene turned the list of shortcuts off
    /// (``Scene/keyboardShortcutOverlayDisabled(_:)``): read by the run loop from
    /// the scene's root environment, and by the Help menu.
    package var keyboardShortcutOverlayDisabled: Bool {
        get { self[KeyboardShortcutOverlayDisabledKey.self] }
        set { self[KeyboardShortcutOverlayDisabledKey.self] = newValue }
    }
}

// MARK: - The list

/// The keys in force when the list was asked for, by section.
struct ShortcutOverlayListing: Equatable {
    /// One section's heading, and its keys and what they are called.
    struct Section: Equatable {
        let title: String
        var rows: [ListedShortcut]
    }

    private(set) var sections: [Section] = []

    /// The keys named so far, each spelled as ``add(_:to:)`` compares them.
    private var seen = Set<String>()

    /// Adds `row` under `title`, in the section of that name if there is one,
    /// unless an earlier row names its key: one key, one row, the first being
    /// the one with a name people know it by (a menu's Quit before the status
    /// bar's).
    ///
    /// Compared in upper case, so a letter pressed alone is one key whichever
    /// case it is written in (``KeyLetterCase``); Shift is a `⇧` of its own.
    mutating func add(_ row: ListedShortcut, to title: String) {
        guard !row.key.isEmpty, !row.title.isEmpty, seen.insert(row.key.uppercased()).inserted else { return }
        append(row, to: title)
    }

    /// Adds one row for `keys`, called `title`, under `section`: a
    /// labelled `onKeyPress`, whose keys share its label (A-KEYHELP-1). Each
    /// key an earlier row names is left out of it, by ``add(_:to:)``'s rule,
    /// and the row with them; the rest are spelled side by side.
    mutating func add(keys: [String], title: String, to section: String) {
        guard !title.isEmpty else { return }
        let fresh = keys.filter { !$0.isEmpty && seen.insert($0.uppercased()).inserted }
        guard !fresh.isEmpty else { return }
        append(ListedShortcut(key: fresh.joined(separator: " "), title: title), to: section)
    }

    /// Puts `row` under `title`, in the section of that name if there is one.
    private mutating func append(_ row: ListedShortcut, to title: String) {
        if let index = sections.firstIndex(where: { $0.title == title }) {
            sections[index].rows.append(row)
        } else {
            sections.append(Section(title: title, rows: [row]))
        }
    }

    /// The width in cells of the widest key, the width of the keys' column, as
    /// the keys' `Text`s spell them (`spelling`).
    func keyColumnWidth(spelling: TextSpelling) -> Int {
        sections.lazy.flatMap(\.rows).map { TextTransliteration.spelled($0.key, as: spelling).strippedLength }.max() ?? 0
    }
}

extension InputHandler {
    /// What's in force as of the frame last drawn, by the rules a key press goes
    /// by: the shortcuts, the labelled `onKeyPress` handlers, the status bar's
    /// items, and TUI's own keys.
    ///
    /// Taken once, when the list is asked for. With the list up the page is drawn
    /// as a backdrop, and registers nothing.
    func shortcutOverlayListing() -> ShortcutOverlayListing {
        let service = LocalizationService.shared
        var listing = ShortcutOverlayListing()
        let page = service.string(for: LocalizationKey.Menu.shortcutsOnThisScreen)
        // Only the keys this terminal sends as themselves: the undo keys hold
        // what it reports, kept current as the app's environment is.
        let shortcuts = keyboardShortcuts.listing(
            activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal,
            modalSection: focusManager.activeModalSectionID, reporting: undoKeys.reporting)
        // Every key in the case the status bar draws a letter pressed alone
        // in (`K` or `k`; `⇧K` either way), so the list and the bar beside it
        // name a key one way.
        let letterCase = statusBar.itemKeyLetterCase
        for row in shortcuts {
            listing.add(
                ListedShortcut(key: letterCase.spelling(row.key), title: row.title, menu: row.menu),
                to: row.menu ?? page)
        }
        // A labelled `onKeyPress` on the screen, in the page's section, after
        // the shortcuts: a key both bind keeps the shortcut's name, which is
        // what a key reaches while the handler's view does not hold the focus.
        let keyPresses = keyboardShortcuts.keyPressListing(
            activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal,
            modalSection: focusManager.activeModalSectionID)
        for row in keyPresses {
            listing.add(keys: row.keys.map(letterCase.spelling), title: row.title, to: page)
        }

        let bar = service.string(for: LocalizationKey.Menu.shortcutsStatusBar)
        // An item's one-letter key as the bar draws it, not as its string is
        // written: `"k"` is `K` (or `k`), `"K"` is `⇧K`.
        for item in statusBar.currentItems {
            listing.add(ListedShortcut(key: letterCase.statusBarItemKey(item.shortcut), title: item.label), to: bar)
        }

        let general = service.string(for: LocalizationKey.Menu.shortcutsGeneral)
        func addGeneral(_ key: Key, _ title: LocalizationKey.Menu, shift: Bool = false) {
            guard let chord = KeyEvent(key: key, shift: shift).displayString else { return }
            listing.add(ListedShortcut(key: letterCase.spelling(chord), title: service.string(for: title)), to: general)
        }
        addGeneral(.f1, .keyboardShortcuts)
        // The settings panel's key, unless the app has it: its own row, from
        // the page's section above, then holds the key.
        if let settingsPanel, settingsPanel.isAvailable, let key = settingsPanel.key, tooltipState?.helpKey != key {
            addGeneral(key, .settings)
        }
        addGeneral(ScreenRedraw.key, .redraw)
        addGeneral(.tab, .shortcutsNextControl)
        addGeneral(.tab, .shortcutsPreviousControl, shift: true)
        if let tooltipState, tooltipState.hasHelpOnScreen, tooltipState.showsTooltips {
            if let helpKey = tooltipState.helpKey { addGeneral(helpKey, .shortcutsShowTooltip) }
            addGeneral(.f1, .showAllTooltips, shift: true)
        }
        return listing
    }

    /// F1, or the Help menu's item: the list, if the scene hasn't turned it off.
    ///
    /// - Returns: Whether that's what happened.
    @discardableResult
    func showKeyboardShortcutOverlay() -> Bool {
        guard let shortcutOverlay, shortcutOverlay.isEnabled, quitPrompt?.isAsking != true else { return false }
        shortcutOverlay.show(shortcutOverlayListing())
        return true
    }

    /// The last layer's F1, unmodified: takes the list down where it's up, and
    /// otherwise shows it. So anything of the app's on F1 has been asked already:
    /// a handler, a `.keyboardShortcut`, a status-bar item, or the tooltip help
    /// key moved there (`TooltipState.helpKey`).
    ///
    /// Not while an open drop-down holds the keyboard, as with `t` and `a`. A
    /// modal is another matter: the list then says what the modal answers to. A
    /// held key shows it once, and a repeat goes no further either.
    ///
    /// - Returns: Whether `event` was taken.
    func runKeyboardShortcutOverlayKey(_ event: KeyEvent, inputGrabbed: Bool) -> Bool {
        guard event.key == .f1, !event.shift, let shortcutOverlay, tooltipState?.helpKey != .f1 else { return false }
        if shortcutOverlay.isPresented {
            if event.phase != .repeat { shortcutOverlay.dismiss() }
            return true
        }
        guard !inputGrabbed || focusManager.activeSectionIsModal else { return false }
        return event.phase == .repeat ? shortcutOverlay.isEnabled : showKeyboardShortcutOverlay()
    }
}

// MARK: - The state

/// Whether the list is on, what it says and whether it's up: what the input
/// chain, the run loop and the scene presenter share, as ``QuitPrompt`` is for
/// its dialog.
///
/// One per run, made by what runs the app. Not `Sendable`: asked from key
/// handlers and frames, all on the main actor.
final class KeyboardShortcutOverlay {
    /// Whether the list may be shown: the scene's, adopted each frame.
    var isEnabled = true {
        didSet { if !isEnabled, isPresented { dismiss() } }
    }

    /// What the list says, as of when it was asked for.
    private(set) var listing = ShortcutOverlayListing()

    /// Whether the list is up.
    private(set) var isPresented = false

    /// Whether the scene presenter draws the list. It stays on once the list has
    /// been up: closing it takes a frame with the sheet drawn and not presented,
    /// which hands the page its focus back.
    private(set) var isHosted = false

    /// Asks for a frame.
    private let requestFrame: () -> Void

    /// - Parameter requestFrame: Asks for a frame, to show or remove the list.
    init(requestFrame: @escaping () -> Void) {
        self.requestFrame = requestFrame
    }

    /// Puts the list up, saying `listing`.
    func show(_ listing: ShortcutOverlayListing) {
        self.listing = listing
        isPresented = true
        isHosted = true
        requestFrame()
    }

    /// Takes the list down.
    func dismiss() {
        isPresented = false
        requestFrame()
    }

    /// The list, as the scene presenter draws it over the window in front; `nil`
    /// until it has first been asked for.
    @MainActor var overlay: SceneOverlay? {
        guard isHosted else { return nil }
        return SceneOverlay(
            key: "keyboard-shortcut-overlay", configuration: SceneConfiguration(),
            view: AnyView(_KeyboardShortcutOverlaySheet(overlay: self)))
    }
}

// MARK: - The views

/// The list as a sheet over the window in front, held by the presentation layer
/// as any sheet is: its focus section, its Escape and its dimming.
struct _KeyboardShortcutOverlaySheet: View {
    let overlay: KeyboardShortcutOverlay

    var body: some View {
        let overlay = overlay
        EmptyView()
            .sheet(
                isPresented: Binding(
                    get: { overlay.isPresented },
                    set: { if !$0, overlay.isPresented { overlay.dismiss() } })
            ) {
                _KeyboardShortcutOverlayContent(listing: overlay.listing) { overlay.dismiss() }
            }
    }
}

/// The list in a `Dialog` titled Keyboard Shortcuts, as the settings panel
/// is drawn, so it stands apart from the dimmed page: its sections in columns
/// (``_ShortcutOverlayColumnsCore``) as wide as the window allows, the dialog
/// as small as they are and centred, its own scroll view taking them where
/// they are too tall, which the arrow and paging keys scroll; and the Done
/// button in its footer, for the pointer.
///
/// A core, as the settings panel's fitting is: the columns are chosen for the
/// rows the dialog shows of them, and only the space the sheet offers says
/// that. The dialog's body is measured with an unbounded height, to find
/// whether it overflows. No state of its own.
private struct _KeyboardShortcutOverlayContent: View, Renderable, Layoutable {
    let listing: ShortcutOverlayListing
    let done: () -> Void

    var body: Never { fatalError("_KeyboardShortcutOverlayContent renders via Renderable") }

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        let size = fittedSize(
            CellSize(
                width: proposal.width ?? context.availableWidth, height: proposal.height ?? context.availableHeight),
            context)
        return ViewSize.fixed(size.width, size.height)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let available = CellSize(width: context.availableWidth, height: context.availableHeight)
        let size = fittedSize(available, context)
        var fitted = context
        fitted.availableWidth = size.width
        fitted.availableHeight = size.height
        return TUIView.renderToBuffer(dialog(in: available, context), context: fitted)
    }

    /// The dialog at its own size, no larger than `available`.
    private func fittedSize(_ available: CellSize, _ context: RenderContext) -> CellSize {
        let size = measureChild(
            dialog(in: available, context),
            proposal: ProposedViewSize(width: available.width, height: available.height), context: context)
        return CellSize(width: min(size.width, available.width), height: min(size.height, available.height))
    }

    /// The dialog, its columns laid out for the rows of `available` its
    /// border, padding and footer leave: measured, with a one-row body in
    /// their place, so a footer drawn taller (a bordered button) is counted.
    private func dialog(in available: CellSize, _ context: RenderContext) -> some View {
        let chrome = measureChild(
            box { Text(verbatim: " ") }, proposal: ProposedViewSize(width: available.width, height: available.height),
            context: context
        ).height - 1
        let listing = listing
        let keyWidth = listing.keyColumnWidth(spelling: context.environment.textSpelling)
        return box {
            _ShortcutOverlayColumnsCore(
                listing: listing, keyWidth: keyWidth, visibleHeight: max(1, available.height - chrome))
        }
        // As wide as the columns want, up to the window: the columns, not a
        // comfortable line length, are what this dialog is made of.
        .dialogPreferredWidth(max(1, available.width))
    }

    /// The dialog around `content`.
    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let service = LocalizationService.shared
        let done = done
        return Dialog(title: service.string(for: LocalizationKey.Menu.keyboardShortcuts), footerAlignment: .trailing) {
            content()
        } footer: {
            Button(service.string(for: LocalizationKey.Button.done)) { done() }
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// One section, or the part of one a column shows: its heading, in bold, and a
/// row for each key, the keys in a column of their own.
struct ShortcutOverlaySectionView: View {
    let title: String
    let rows: [ListedShortcut]
    let keyWidth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title).bold()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 2) {
                    Text(verbatim: row.key).frame(width: keyWidth, alignment: .trailing)
                    Text(verbatim: row.title)
                }
            }
        }
    }
}
