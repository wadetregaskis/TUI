//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuColumn.swift
//
//  The seam between a menu's CONTENT model and its CONTROL model.
//
//  A menu's rows are views — that is what gives `Menu` arbitrary `@ViewBuilder`
//  content, `ButtonRole`, per-row `.disabled()` and key equivalents, and it is
//  not negotiable: `.keyboardShortcut` is an environment modifier claimed during
//  the row's own render, so a static tree walk would silently drop it.
//
//  But a menu's HIGHLIGHT wants to be an index, not a focus id. An index is what
//  gives the `Picker` drop-down its jump keys, its windowed scrolling and its
//  hover-moves-highlight for free, and it is what lets a pop-up stop putting its
//  rows into the page's focus ring — where they never belonged, since a menu
//  grabs the keyboard while it is up.
//
//  This file is how both are true at once: rows still render as views, and each
//  one claims an ORDINAL and reports itself to the column instead of to the
//  focus manager.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The sink

/// Collects what a pop-up menu's rows report about themselves as they render.
///
/// One per presented menu, rebuilt each frame. `_ButtonCore` claims an ordinal
/// from it and publishes its action, its enabled state and its resolved
/// shortcut; the menu's controller then reads back which ordinals exist (so the
/// arrows have somewhere to go) and what to run when one is chosen.
///
/// Claims are keyed by ``ViewIdentity`` and first-wins, because one child can
/// contain two Buttons: the first takes the row, and the second falls back to
/// ordinary focus-ring behaviour rather than silently stealing it. Only a render
/// pass claims — see `_ButtonCore`.
///
/// `_ButtonCore` is the ONLY claimer, and that is the design rather than a
/// limitation: a row is not just an action and an enabled flag, it is also the
/// menu-row LOOK — the bar spanning the menu's interior, the key-equivalent
/// column, the hover wash — and all of that lives in `_MenuItemButtonStyle`,
/// which reaches Buttons. So another control joins the column by BEING one for
/// the frame: `_ToggleCore` renders a row `Button` carrying its own on/off mark
/// when this is non-nil, and a `Menu` or a `Picker` renders a row `Button` that
/// opens a submenu (`_MenuSubmenuRow`), publishing the submenu with its ordinal.
@MainActor
final class MenuRowSink {
    /// What one row told the column about itself.
    struct Row {
        let action: () -> Void
        let isEnabled: Bool
        /// The submenu the row opens, for a row that is one (a `Menu` or a
        /// `Picker` written in the menu); `nil` for a row that is a choice.
        let submenu: MenuSubmenu?
    }

    private var claims: [ViewIdentity: Int] = [:]
    private var rows: [Int: Row] = [:]

    /// This row's ordinal — the same one on every pass of the same frame.
    func claimOrdinal(for identity: ViewIdentity) -> Int {
        if let existing = claims[identity] { return existing }
        let ordinal = claims.count
        claims[identity] = ordinal
        return ordinal
    }

    /// Records what the row at `ordinal` does — runs `action`, or opens
    /// `submenu`.
    func publish(ordinal: Int, action: @escaping () -> Void, isEnabled: Bool, submenu: MenuSubmenu? = nil) {
        rows[ordinal] = Row(action: action, isEnabled: isEnabled, submenu: submenu)
    }

    /// The submenu the row at `ordinal` opens, if it is enabled and opens one.
    func submenu(at ordinal: Int) -> MenuSubmenu? {
        guard let row = rows[ordinal], row.isEnabled else { return nil }
        return row.submenu
    }

    /// The rows that open a submenu, by ordinal.
    var submenuRows: [(ordinal: Int, submenu: MenuSubmenu)] {
        rows.compactMap { ordinal, row in row.submenu.map { (ordinal, $0) } }.sorted { $0.ordinal < $1.ordinal }
    }

    /// The ordinals a highlight may rest on, in visual order: rows that
    /// published and are enabled. A `Divider` never publishes; a `.disabled()`
    /// row publishes but declines, exactly as it declines focus on the page.
    var selectableOrdinals: [Int] {
        rows.filter { $0.value.isEnabled }.keys.sorted()
    }

    /// Runs the row at `ordinal`, if it is one that can be chosen. A row that
    /// opens a submenu runs nothing: the controller opens it
    /// (``MenuPopupController/choose(_:byKeyboard:)``).
    func activate(ordinal: Int) {
        guard let row = rows[ordinal], row.isEnabled, row.submenu == nil else { return }
        row.action()
    }

    /// Drops the previous frame's claims. Called once per `renderMenuColumn`, so
    /// the ordinals restart at zero and stay dense frame to frame.
    func beginPass() {
        claims.removeAll(keepingCapacity: true)
        rows.removeAll(keepingCapacity: true)
    }
}

/// The hit-test identity of a pop-up menu's row.
///
/// A menu row is not a focus stop, so this is not a focus id — but the reveal
/// machinery finds a control by matching a region's `focusID`, and windowing a
/// tall menu to its highlighted row is exactly a reveal. Derived from the
/// ordinal alone so the column can name the row it wants revealed BEFORE the
/// rows have drawn.
func menuRowRegionID(_ ordinal: Int) -> String {
    "menu-row-\(ordinal)"
}

/// The ordinal a region id names, or `nil` if it names something else.
///
/// This is what lets a column of VIEWS be sliced back into rows: each row's own
/// region says which line range is its, so the menu never has to guess a row's
/// height or work out what a line is by looking at it.
func menuRowOrdinal(fromRegionID id: String) -> Int? {
    guard id.hasPrefix("menu-row-") else { return nil }
    return Int(id.dropFirst("menu-row-".count))
}

// MARK: - Environment

private struct MenuRowSinkKey: EnvironmentKey {
    static let defaultValue: MenuRowSink? = nil
}

private struct MenuHighlightedOrdinalKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

private struct IsInsideMenuKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The open pop-up menu a row is rendering into, or `nil` on the page.
    ///
    /// Non-nil is what puts a `Button` into menu-row mode: it claims an ordinal
    /// here instead of registering with the focus manager. It is also what makes
    /// a `Toggle` render AS such a row rather than as a checkbox — read on both
    /// the measure and the render, so the column hugs the width it will draw.
    /// Deliberately absent for an inline `Menu`, whose rows ARE page focus stops
    /// — see `Documentation/Controls and presentation/Unifying the menu implementations.md`.
    var menuRowSink: MenuRowSink? {
        get { self[MenuRowSinkKey.self] }
        set { self[MenuRowSinkKey.self] = newValue }
    }

    /// Which ordinal the open menu is highlighting this frame.
    var menuHighlightedOrdinal: Int? {
        get { self[MenuHighlightedOrdinalKey.self] }
        set { self[MenuHighlightedOrdinalKey.self] = newValue }
    }

    /// Whether this view is a row of a menu — of EITHER kind.
    ///
    /// Unlike ``menuRowSink``, which is the pop-up's row-claiming channel and
    /// deliberately absent for an inline menu, this is the plain question "is
    /// the thing around me a menu". A `Button` reads it to say what Return does
    /// here: choosing from a menu rather than activating a button on the page.
    var isInsideMenu: Bool {
        get { self[IsInsideMenuKey.self] }
        set { self[IsInsideMenuKey.self] = newValue }
    }
}

// MARK: - The controller

/// The open pop-up menu's own state: which row is highlighted, and which rows
/// there are to highlight.
///
/// The highlight itself is a ``MenuHighlight``, shared with the `Picker`
/// drop-down and the combo box — the walk is the same walk everywhere, and only
/// the edge rule differs (a `Menu` clamps; only the `Picker` wraps). What is
/// particular to a view-composed pop-up lives here: the sink its rows report
/// to, and the reveal target that scrolls a tall menu to its highlight.
///
/// One per presented menu, living on the presenter's persisted state, so the
/// highlight survives the frames between key presses.
@MainActor
package final class MenuPopupController {
    /// No arguments: spelled out because the implicit initializer is internal and a
    /// menu's popup (TUIkitMenus) makes these, as does the screen selection's Copy
    /// menu (TUIkitChrome).
    package init() {}

    /// Collects what the rows report as they render.
    let sink = MenuRowSink()

    /// The highlighted row, and every gesture that moves it.
    let highlight = MenuHighlight.popUpMenu()

    /// The window scroll, when the menu is taller than the screen can show.
    /// Owned here so it survives the frames between key presses, exactly as a
    /// `Picker` drop-down's does.
    let scroll = ScrollAxis()

    /// The highlighted row's ordinal, or `nil` for "nothing chosen yet".
    var highlightedOrdinal: Int? { highlight.ordinal }

    /// Records that the menu has just been opened.
    ///
    /// - Parameter withSelection: Whether to open with a row already
    ///   highlighted. `false` for a pointer-opened menu (macOS behaviour: the
    ///   pointer has chosen nothing yet, so highlighting a row invites a
    ///   mis-click); `true` when the keyboard opened it, since there is nothing
    ///   else to point with. From the unhighlighted state the first Down takes
    ///   the first row and the first Up the last.
    ///
    /// The first row is the first known selectable ordinal when this menu has
    /// been open before and `0` when it has not — and ordinal 0 is the first
    /// BUTTON either way, since only a Button claims one. A leading `Divider`
    /// costs nothing; a leading `.disabled()` row is caught by
    /// ``MenuHighlight/adopt(selectable:)`` as soon as the frame draws.
    package func opened(withSelection: Bool) {
        closeSubmenu()
        highlight.move(to: withSelection ? (highlight.selectable.first ?? 0) : nil)
    }

    /// Records that the menu has closed, and any submenu open from it.
    package func closed() {
        closeSubmenu()
        highlight.move(to: nil)
    }

    /// Takes the ordinals the frame just published.
    func adoptRenderedRows() {
        highlight.adopt(selectable: sink.selectableOrdinals)
    }

    /// The row a scrolling menu should keep on screen, named the way the row's
    /// own hit-test region is.
    var revealTargetID: String? {
        highlight.ordinal.map(menuRowRegionID)
    }

    /// Runs the highlighted row, or opens the submenu it opens, if there is
    /// one.
    func activateHighlighted() -> Bool {
        guard let ordinal = highlight.ordinal else { return false }
        choose(ordinal, byKeyboard: true)
        return true
    }

    // MARK: - Where the rows were drawn

    /// Each row's first line in the popup as last drawn, by ordinal: what a
    /// submenu opened from the row hangs level with.
    private var drawnLines: [Int: Int] = [:]

    /// Records where the rows were drawn: `firstRows` — each ordinal's first
    /// row of the column — through a window scrolled by `offset`, under the
    /// popup's top border.
    func noteDrawnRows(_ firstRows: [Int: Int], scrolledBy offset: Int) {
        let visible = max(1, scroll.viewportHeight)
        drawnLines = firstRows.mapValues { min(max(1, $0 - offset + 1), visible) }
    }

    /// The line of the popup the row at `ordinal` was drawn on — kept within
    /// the window when the row is scrolled out of it — or `nil` for a row
    /// that was not drawn.
    func drawnLine(ofOrdinal ordinal: Int) -> Int? {
        drawnLines[ordinal]
    }

    // MARK: - Type select

    /// Each row's title as last drawn, by ordinal: what a typed prefix finds
    /// it by (``TypeSelectBuffer/title(ofDrawn:)``).
    private var titles: [Int: String] = [:]

    /// What has been typed to find a row, in whichever menu open from this
    /// one the keys are in.
    private var typeSelected = TypeSelectBuffer()

    /// The menu the prefix was typed in: one typed in another — the keys gone
    /// into a submenu, or back out of one — is forgotten.
    private weak var typedIn: MenuPopupController?

    /// Records the rows' titles, as drawn.
    func noteTitles(_ titles: [Int: String]) {
        self.titles = titles
    }

    // MARK: - Submenus

    /// The submenu open from this menu — on which row, and its own controller
    /// — or `nil`. See `MenuSubmenus.swift`.
    private(set) var openSubmenu: (ordinal: Int, controller: MenuPopupController)?

    /// Chooses the row at `ordinal`: runs it, or — for a row that opens a
    /// submenu — opens that, with its first row highlighted when the keyboard
    /// chose it, as a keyboard-opened menu is, and nothing highlighted when
    /// the pointer did.
    ///
    /// - Returns: Whether that was a choice, which ends a press-and-hold
    ///   gesture; opening a submenu is not one.
    @discardableResult
    func choose(_ ordinal: Int, byKeyboard: Bool) -> Bool {
        guard sink.submenu(at: ordinal) != nil else {
            sink.activate(ordinal: ordinal)
            return true
        }
        highlight.move(to: ordinal)
        openSubmenu(at: ordinal, withSelection: byKeyboard)
        return false
    }

    /// Opens the submenu of the row at `ordinal`, closing any other, and keeps
    /// one that is already open there as it is unless the keyboard is entering
    /// it, when its first row is highlighted.
    func openSubmenu(at ordinal: Int, withSelection: Bool) {
        if let open = openSubmenu, open.ordinal == ordinal {
            if withSelection, open.controller.highlightedOrdinal == nil {
                open.controller.opened(withSelection: true)
            }
            return
        }
        closeSubmenu()
        let child = MenuPopupController()
        child.opened(withSelection: withSelection)
        openSubmenu = (ordinal, child)
    }

    /// Closes the submenu open from this menu, and every one open from it.
    func closeSubmenu() {
        openSubmenu?.controller.closed()
        openSubmenu = nil
    }

    /// The pointer is over the row at `ordinal`: highlight it, open its
    /// submenu if it has one, and close the open one if it is another row's —
    /// as a desktop menu tracks the pointer.
    func pointerEntered(_ ordinal: Int) {
        highlight.point(at: ordinal)
        if sink.submenu(at: ordinal) != nil {
            openSubmenu(at: ordinal, withSelection: false)
        } else {
            closeSubmenu()
        }
    }

    /// The menus open from this one, this one first and the deepest last, as
    /// far as the keyboard reaches: into a submenu once it has a highlight —
    /// the keyboard entered it, or the pointer is in it — and no further while
    /// it has none, which is how a submenu the pointer opened leaves the keys
    /// with the menu it opened from.
    var keyboardChain: [MenuPopupController] {
        var chain = [self]
        while let open = chain[chain.count - 1].openSubmenu, open.controller.highlightedOrdinal != nil {
            chain.append(open.controller)
        }
        return chain
    }
}

extension MenuPopupController {
    /// Whether characters typed now continue a prefix (``typeSelect(_:)``).
    var isTypeSelecting: Bool { typeSelected.isTypeSelecting }

    /// Takes a typed character for type select, in the menu the keys are in
    /// (``keyboardChain``): moves its highlight to the row whose title the
    /// prefix starts — the next one after the highlight for a first character,
    /// the one it is on still for a longer prefix — closing a submenu open
    /// from the row it leaves, as an arrow does.
    ///
    /// - Returns: Whether the key was taken — whether or not a row matched.
    func typeSelect(_ event: KeyEvent) -> Bool {
        let chain = keyboardChain
        let menu = chain[chain.count - 1]
        if typedIn !== menu { typeSelected.reset() }
        guard typeSelected.take(event) else { return false }
        typedIn = menu
        let selectable = menu.highlight.selectable
        let current = menu.highlightedOrdinal.flatMap(selectable.firstIndex(of:))
        guard
            let match = TypeSelectBuffer.match(
                typeSelected.prefix, count: selectable.count, current: current,
                text: { menu.titles[selectable[$0]] })
        else { return true }
        menu.highlight.move(to: selectable[match])
        if let open = menu.openSubmenu, open.ordinal != menu.highlightedOrdinal { menu.closeSubmenu() }
        return true
    }
}
