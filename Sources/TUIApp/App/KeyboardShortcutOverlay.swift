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
    /// Compared in upper case, because the status bar writes a bare letter in
    /// the case it types and a menu row writes a capital.
    mutating func add(_ row: ListedShortcut, to title: String) {
        guard !row.key.isEmpty, !row.title.isEmpty, seen.insert(row.key.uppercased()).inserted else { return }
        if let index = sections.firstIndex(where: { $0.title == title }) {
            sections[index].rows.append(row)
        } else {
            sections.append(Section(title: title, rows: [row]))
        }
    }

    /// The width in cells of the widest key, the width of the keys' column.
    var keyColumnWidth: Int {
        sections.lazy.flatMap(\.rows).map(\.key.strippedLength).max() ?? 0
    }
}

extension InputHandler {
    /// What's in force as of the frame last drawn, by the rules a key press goes
    /// by: the shortcuts, the status bar's items, and TUI's own keys.
    ///
    /// Taken once, when the list is asked for. With the list up the page is drawn
    /// as a backdrop, and registers nothing.
    func shortcutOverlayListing() -> ShortcutOverlayListing {
        let service = LocalizationService.shared
        var listing = ShortcutOverlayListing()
        let page = service.string(for: LocalizationKey.Menu.shortcutsOnThisScreen)
        let shortcuts = keyboardShortcuts.listing(
            activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal,
            modalSection: focusManager.activeModalSectionID)
        for row in shortcuts { listing.add(row, to: row.menu ?? page) }

        let bar = service.string(for: LocalizationKey.Menu.shortcutsStatusBar)
        for item in statusBar.currentItems {
            listing.add(ListedShortcut(key: item.shortcut, title: item.label), to: bar)
        }

        let general = service.string(for: LocalizationKey.Menu.shortcutsGeneral)
        func addGeneral(_ key: Key, _ title: LocalizationKey.Menu, shift: Bool = false) {
            guard let chord = KeyEvent(key: key, shift: shift).displayString else { return }
            listing.add(ListedShortcut(key: chord, title: service.string(for: title)), to: general)
        }
        addGeneral(.f1, .keyboardShortcuts)
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

/// The list's heading, its sections in a `ScrollView`, which the arrow and paging
/// keys scroll while it overflows, and the Done button, for the pointer.
private struct _KeyboardShortcutOverlayContent: View {
    let listing: ShortcutOverlayListing
    let done: () -> Void

    var body: some View {
        let service = LocalizationService.shared
        let keyWidth = listing.keyColumnWidth
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: service.string(for: LocalizationKey.Menu.keyboardShortcuts)).bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(listing.sections.enumerated()), id: \.offset) { _, section in
                        ShortcutOverlaySectionView(section: section, keyWidth: keyWidth)
                    }
                }
            }
            HStack {
                Spacer()
                Button(service.string(for: LocalizationKey.Button.done)) { done() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 1)
    }
}

/// One section: its heading, in bold, and a row for each key, the keys in a
/// column of their own.
private struct ShortcutOverlaySectionView: View {
    let section: ShortcutOverlayListing.Section
    let keyWidth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: section.title).bold()
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 2) {
                    Text(verbatim: row.key).frame(width: keyWidth, alignment: .trailing)
                    Text(verbatim: row.title)
                }
            }
        }
    }
}
