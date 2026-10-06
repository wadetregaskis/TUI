//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarItem.swift
//
//  Status bar supporting types: items, protocol, builder, order, alignment,
//  style, shortcut symbols, and system items.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Status Bar Alignment

/// The horizontal alignment of items within the status bar.
public enum StatusBarAlignment: Sendable {
    /// Items are aligned to the left (leading edge).
    case leading

    /// Items are aligned to the right (trailing edge).
    case trailing

    /// Items are centered horizontally.
    case center

    /// Items are evenly distributed across the full width.
    case justified
}

// MARK: - Status Bar Item Order

/// Defines the display order of status bar items.
///
/// Items are sorted by their order value (ascending). Lower values appear first (left).
/// System items appear on the right side with high order values.
///
/// # Order Ranges
///
/// - `0-99`: Reserved for leading items
/// - `100-899`: User-defined items (default: 500)
/// - `900-999`: Reserved for system items (quit, help, theme) on the right
///
/// # System Item Layout (from right edge)
///
/// ```
/// [user items...] [q quit] [? help] [t theme]
/// ```
///
/// # Example
///
/// ```swift
/// // Custom item appears on the left (before system items)
/// StatusBarItem(shortcut: "s", label: "save", order: .default)
/// ```
public struct StatusBarItemOrder: Comparable, Sendable {
    /// The numeric sort value (lower values appear first).
    public let value: Int

    /// Creates a status bar item order with the given sort value.
    ///
    /// - Parameter value: The numeric sort value.
    public init(_ value: Int) {
        self.value = value
    }

    /// Compares two orders by their numeric value.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    // MARK: - User Item Orders

    /// Default order for user-defined items (appears on the left).
    public static let `default` = Self(500)

    /// Order for items that should appear early (leftmost user items).
    public static let early = Self(100)

    /// Order for items that should appear late (rightmost user items, before system items).
    public static let late = Self(800)

    // MARK: - System Item Orders (right side)

    /// Order for the quit item (leftmost of system items).
    /// Appears as: `[...user items] [q quit] [a appearance] [t theme]`
    /// The two common keys the status bar carries by default, ahead of the
    /// app-wide ones: they change meaning with the focus, so they read best
    /// nearest the page's own items.
    public static let escapeKey = Self(850)

    /// See ``escapeKey``.
    public static let returnKey = Self(860)

    /// The app's undo, shown while there is a step to undo — see
    /// ``StatusBarState/showUndoItems``.
    public static let undo = Self(870)

    /// The app's redo, beside ``undo``.
    public static let redo = Self(875)

    public static let quit = Self(900)

    /// Order for the appearance item (middle system item).
    public static let appearance = Self(910)

    /// Order for the theme item (rightmost).
    public static let theme = Self(920)
}

// MARK: - Status Bar Item Protocol

/// A protocol for items that can be displayed in a status bar.
///
/// Implement this protocol to create custom status bar items.
/// The default `StatusBarItem` already conforms to this protocol.
public protocol StatusBarItemProtocol: Sendable {
    /// The unique identifier for this item.
    var id: String { get }

    /// The shortcut key(s) to display (e.g., "q", "↑↓", "⎋").
    var shortcut: String { get }

    /// A short description (one word, e.g., "quit", "nav", "close").
    var label: String { get }

    /// The key event that triggers this item's action.
    ///
    /// Return nil if the item is purely informational (no action).
    var triggerKey: Key? { get }

    /// The display order of this item.
    ///
    /// Items are sorted by order (ascending). Lower values appear first.
    var order: StatusBarItemOrder { get }

    /// Whether this item matches a given key event.
    ///
    /// Override this for complex matching (e.g., arrow keys).
    func matches(_ event: KeyEvent) -> Bool

    /// Executes the item's action, if it has one.
    ///
    /// Called by the keyboard handler when the trigger key fires
    /// and by the mouse-click handler when the item is clicked.
    /// Default no-op so informational-only conformers don't need
    /// to implement it.
    func execute()

    /// Whether this item should appear in the rendered status
    /// bar. Items that bind a key purely for the keyboard
    /// dispatch path (e.g. a Shift-variant of an existing
    /// shortcut, surfaced visually as "c|C" by its sibling) can
    /// return `false` to stay invisible while still firing on
    /// the keyboard.
    var displayInStatusBar: Bool { get }
}

// Default implementations
extension StatusBarItemProtocol {
    /// Default order for user-defined items.
    public var order: StatusBarItemOrder { .default }

    /// Whether this item's trigger key matches the given key event.
    ///
    /// Returns `false` if the item has no trigger key (informational only).
    ///
    /// - Parameter event: The key event to match against.
    /// - Returns: `true` if the event matches this item's trigger key.
    public func matches(_ event: KeyEvent) -> Bool {
        guard let trigger = triggerKey else { return false }
        return event.key == trigger
    }

    /// Default `execute()` is a no-op so informational-only
    /// conformers don't need to override.
    public func execute() {}

    /// Default: items are shown in the status bar.
    public var displayInStatusBar: Bool { true }
}

// MARK: - Status Bar Item

/// A status bar item displaying a shortcut and its description.
///
/// # Example
///
/// ```swift
/// StatusBarItem(shortcut: "q", label: "quit") {
///     app.quit()
/// }
///
/// StatusBarItem(shortcut: "↑↓", label: "nav", key: .up) // Info only, no action
///
/// // With custom order
/// StatusBarItem(shortcut: "s", label: "save", order: .early) {
///     save()
/// }
/// ```
public struct StatusBarItem: StatusBarItemProtocol, Identifiable, @unchecked Sendable {
    /// The unique identifier for this item.
    public let id: String

    /// The shortcut key(s) displayed to the user (e.g. `"q"`, `"↑↓"`).
    public let shortcut: String

    /// The descriptive label shown next to the shortcut (e.g. `"quit"`, `"nav"`).
    public let label: String

    /// The key that triggers this item's action, or `nil` for informational items.
    public let triggerKey: Key?

    /// The sort order controlling horizontal position in the status bar.
    public let order: StatusBarItemOrder

    /// Whether this item should appear in the rendered status
    /// bar. Hidden items still fire on their trigger key — used
    /// to bind a Shift-variant of a visible shortcut without
    /// adding a separate row to the bar.
    public let displayInStatusBar: Bool

    /// The action to perform when the shortcut is triggered.
    private let action: (() -> Void)?

    /// Whether a key can fire the item: `false` for one that only names a
    /// key bound elsewhere in the input chain (see
    /// ``init(id:naming:label:order:action:)``), and `true` for every item
    /// made through the public initializers.
    let matchesKeys: Bool

    /// Whether a held key's repeats run the action again: `true` unless the
    /// framework says otherwise — a presentation's ESC item while Escape
    /// presses a cancel button that does not repeat
    /// (`DismissalGate.escapeRepeats`). A repeat that does not run it is
    /// still taken, as the keyboard-shortcut registry takes one.
    var repeats = true

    /// Creates a status bar item with a localized label and an action.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. Only `label` is: `shortcut` is the key *glyph*
    /// (`"q"`, `"⎋"`, `"⌃Q"`), which the item also derives its trigger key and
    /// identity from. ``Shortcut`` names the keys as every other key TUIkit
    /// names is named.
    ///
    /// - Parameters:
    ///   - shortcut: The shortcut key(s) to display.
    ///   - labelKey: The key for a short description (one word).
    ///   - key: The key that triggers the action (derived from shortcut if not provided).
    ///   - order: The display order (default: `.default`).
    ///   - displayInStatusBar: Whether the item is rendered in the status bar
    ///     (default: `true`).
    ///   - action: The action to perform.
    public init(
        shortcut: String,
        label labelKey: LocalizedStringKey,
        key: Key? = nil,
        order: StatusBarItemOrder = .default,
        displayInStatusBar: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.init(
            shortcut: shortcut,
            label: labelKey.localized,
            key: key,
            order: order,
            displayInStatusBar: displayInStatusBar,
            action: action
        )
    }

    /// Creates a status bar item with an action, labelled as written.
    ///
    /// - Parameters:
    ///   - shortcut: The shortcut key(s) to display.
    ///   - label: A short description (one word).
    ///   - key: The key that triggers the action (derived from shortcut if not provided).
    ///   - order: The display order (default: `.default`).
    ///   - displayInStatusBar: Whether the item is rendered in
    ///     the status bar (default: `true`). Use `false` to bind
    ///     a key without displaying a separate row — useful for
    ///     Shift-variants whose display is already covered by a
    ///     sibling item like `"c|C"`.
    ///   - action: The action to perform.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        shortcut: String,
        label: S,
        key: Key? = nil,
        order: StatusBarItemOrder = .default,
        displayInStatusBar: Bool = true,
        action: (() -> Void)? = nil
    ) {
        // Identity is the shortcut alone, NOT shortcut + label.
        // Status-bar items often render dynamic labels (e.g.
        // "Color: ANSI 16" → "Color: ANSI 256" after the action
        // cycles a value), and the hover state machine is
        // identity-based — `statusBarState.hoveredItemID` is set
        // on .entered and compared against `item.id` on the
        // next render. If id included the label, the post-
        // action render would compute a fresh id ("c|C-Color:
        // ANSI 256") that no longer matches the stored
        // hoveredItemID ("c|C-Color: ANSI 16"), and the hover
        // underline would silently drop until the user moved
        // the cursor out and back in. Shortcut is the right
        // stable key — at most one visible status-bar item
        // exists per shortcut (StatusBar dedupes by shortcut
        // when merging user and system items).
        self.id = shortcut
        self.shortcut = shortcut
        self.label = String(label)
        self.order = order
        self.displayInStatusBar = displayInStatusBar
        self.action = action
        self.matchesKeys = true

        // Derive trigger key from shortcut if not explicitly provided
        if let explicitKey = key {
            self.triggerKey = explicitKey
        } else if let mappedKey = Self.keyFromShortcut(shortcut) {
            // First try to map special symbols to keys
            self.triggerKey = mappedKey
        } else if shortcut.count == 1, let char = shortcut.first {
            // Single character becomes a character key
            self.triggerKey = .character(char)
        } else {
            self.triggerKey = nil
        }
    }

    /// Creates an informational status bar item (no action) with a localized
    /// label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - shortcut: The shortcut key(s) to display.
    ///   - labelKey: The key for a short description.
    ///   - order: The display order (default: `.default`).
    public init(
        shortcut: String, label labelKey: LocalizedStringKey,
        order: StatusBarItemOrder = .default
    ) {
        self.init(shortcut: shortcut, label: labelKey.localized, order: order)
    }

    /// Creates an informational status bar item (no action), labelled as
    /// written.
    ///
    /// - Parameters:
    ///   - shortcut: The shortcut key(s) to display.
    ///   - label: A short description.
    ///   - order: The display order (default: `.default`).
    ///
    /// Generic over `StringProtocol` for the same reason as
    /// ``init(shortcut:label:key:order:displayInStatusBar:action:)-(_,S,_,_,_,_)``.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        shortcut: String, label: S, order: StatusBarItemOrder = .default
    ) {
        self.init(
            shortcut: shortcut, label: label, key: nil, order: order,
            displayInStatusBar: true, action: nil)
    }

    /// An item that names a key without binding it: it shows `shortcut`,
    /// performs `action` when clicked, and no key fires it.
    ///
    /// For a key the input chain matches somewhere else, by rules the bar's
    /// vocabulary cannot spell — the app's undo and redo
    /// (``StatusBarState/showUndoItems``), whose keys are chords of any kind
    /// an app chooses. Read as a shortcut, the name would bind a bare key: a
    /// name with an arrow in it matches the plain arrow, and a one-character
    /// name that character, at layer 1, ahead of every view.
    ///
    /// - Parameters:
    ///   - id: The item's identity, for the hover state: given rather than
    ///     taken from `shortcut`, which can be empty, or the same for two
    ///     items.
    ///   - shortcut: The key's name, shown and never matched.
    ///   - label: A short description, as written.
    ///   - order: The display order.
    ///   - action: What a click performs.
    init(
        id: String, naming shortcut: String, label: String, order: StatusBarItemOrder,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.shortcut = shortcut
        self.label = label
        self.order = order
        self.displayInStatusBar = true
        self.action = action
        self.triggerKey = nil
        self.matchesKeys = false
    }

    /// Whether this item has an action to execute.
    public var hasAction: Bool {
        action != nil
    }
}

// MARK: - Public API

extension StatusBarItem {
    /// Executes the item's action.
    public func execute() {
        action?()
    }

    /// Override matching for special cases.
    ///
    /// The shortcut vocabulary spells BARE keys only — there is no "^a" — so
    /// an item on "a" means plain `a`, never Ctrl+A or Alt+A. Those chords
    /// belong to later dispatch layers (`.selectAll` row shortcuts,
    /// Ctrl/Option+arrow row moves), and status-bar items match at layer 1,
    /// ahead of them all: matching modifier-blind starved every later layer
    /// of its chords (an action-bearing "a" item swallowed a List's Ctrl+A).
    /// Shift is the one modifier a shortcut CAN spell — as an uppercase
    /// letter — so character triggers keep matching by case, and every other
    /// trigger requires the modifier-free chord (Shift+↑ is extend-selection,
    /// Shift+Tab is backtab; neither is the bare item).
    ///
    /// An item that only names a key bound elsewhere — the app's undo and
    /// redo — matches none.
    public func matches(_ event: KeyEvent) -> Bool {
        guard matchesKeys, !event.ctrl, !event.alt else { return false }

        // Handle arrow key combinations like "↑↓"
        if !event.shift {
            if shortcut.contains("↑") && event.key == .up { return true }
            if shortcut.contains("↓") && event.key == .down { return true }
            if shortcut.contains("←") && event.key == .left { return true }
            if shortcut.contains("→") && event.key == .right { return true }
        }

        // Standard matching
        guard let trigger = triggerKey else { return false }

        // For character keys, do case-sensitive matching
        // "n" only matches 'n', "N" only matches 'N' (Shift+n)
        if case .character(let triggerChar) = trigger,
            case .character(let eventChar) = event.key
        {
            return triggerChar == eventChar
        }

        return event.key == trigger && !event.shift
    }
}

// MARK: - Private Helpers

extension StatusBarItem {
    // The complexity is the shortcut-alias switch itself; multiple smaller
    // lookups would just fragment the table. Block-style suppression keeps
    // the doc comment attached to the declaration.
    // swiftlint:disable cyclomatic_complexity
    /// Maps common shortcut symbols to Key values.
    ///
    /// The space bar's name is a word in the app's language (``Shortcut/space``),
    /// so telling it apart is a lookup in the localization tables, under their
    /// lock — and every item is built afresh each frame. So it is asked last,
    /// of a shortcut no fixed spelling claimed, and never of one printable
    /// ASCII character, which is that key whatever the space bar is called:
    /// the framework's own items (`q`, `a`, `t`, `⎋`, `↩`) and an app's
    /// one-key items never ask. In the switch, it was asked of every item that
    /// was not Escape, Return, Tab or a delete key.
    ///
    /// - Parameters:
    ///   - shortcut: What the item shows.
    ///   - spaceBarName: The space bar's name; a parameter so a test can see
    ///     whether it was asked.
    static func keyFromShortcut(
        _ shortcut: String, spaceBarName: () -> String = { KeySymbols.spaceBar }
    ) -> Key? {
        switch shortcut {
        // Special keys
        case Shortcut.escape, "esc", "escape":
            return .escape
        case Shortcut.enter, "enter", "return":
            return .enter
        case Shortcut.tab, "tab":
            return .tab
        case Shortcut.backspace, "backspace", "del":
            return .backspace
        case Shortcut.delete:
            return .delete
        case "space":
            return .space

        // Arrow keys
        case Shortcut.arrowUp:
            return .up
        case Shortcut.arrowDown:
            return .down
        case Shortcut.arrowLeft:
            return .left
        case Shortcut.arrowRight:
            return .right

        // Navigation keys
        case Shortcut.home:
            return .home
        case Shortcut.end:
            return .end
        case Shortcut.pageUp:
            return .pageUp
        case Shortcut.pageDown:
            return .pageDown

        // Function keys
        case Shortcut.f1:
            return .f1
        case Shortcut.f2:
            return .f2
        case Shortcut.f3:
            return .f3
        case Shortcut.f4:
            return .f4
        case Shortcut.f5:
            return .f5
        case Shortcut.f6:
            return .f6
        case Shortcut.f7:
            return .f7
        case Shortcut.f8:
            return .f8
        case Shortcut.f9:
            return .f9
        case Shortcut.f10:
            return .f10
        case Shortcut.f11:
            return .f11
        case Shortcut.f12:
            return .f12

        default:
            break
        }
        if shortcut.utf8.count == 1, let byte = shortcut.utf8.first, (0x21...0x7E).contains(byte) {
            return nil
        }
        return shortcut == spaceBarName() ? .space : nil
    }
    // swiftlint:enable cyclomatic_complexity
}
