//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandGroupPlacement.swift
//
//  The standard groups of the menu bar's standard menus, which a
//  `CommandGroup` adds to or replaces.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Command Group Placement

/// The standard locations that you can place new command groups relative to —
/// mirrors SwiftUI's `CommandGroupPlacement`.
///
/// The names of these placements aren't visible in the user interface, but
/// each belongs to one of the standard menus, as on macOS (measured on macOS
/// 15.8 with SwiftUI's own main menu read back: the session notes'
/// `O13/probe/menus.swift`): the app's menu, File, Edit, Format, View, Window
/// and Help. A menu shows its groups in the order below, each set off from the
/// next by a separator, and a standard menu with nothing in any of its groups
/// is not drawn.
///
/// What each group holds before an app changes it is TUIkit's: the commands a
/// terminal app has — About and Quit in the app's menu, Undo, Redo, Cut, Copy
/// and Paste in the Edit menu, each doing what its key does. A terminal app has
/// no documents, no windows to arrange and no services menu, so the other
/// groups are empty, and an app fills them with ``CommandGroup``.
/// `commandsRemoved()` takes TUIkit's away.
public struct CommandGroupPlacement: Hashable, Sendable {
    /// Which group: also the order of the groups across the menu bar.
    let group: Group

    /// The groups, in the order the menu bar shows them.
    enum Group: Int, CaseIterable, Comparable, Sendable {
        case appInfo, appSettings, systemServices, appVisibility, appTermination
        case newItem, saveItem, importExport, printItem
        case undoRedo, pasteboard, textEditing
        case textFormatting
        case toolbar, sidebar
        case windowSize, windowArrangement, windowList, singleWindowList
        case help

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The standard menu the group is in.
        var menu: StandardMenu {
            switch self {
            case .appInfo, .appSettings, .systemServices, .appVisibility, .appTermination: .app
            case .newItem, .saveItem, .importExport, .printItem: .file
            case .undoRedo, .pasteboard, .textEditing: .edit
            case .textFormatting: .format
            case .toolbar, .sidebar: .view
            case .windowSize, .windowArrangement, .windowList, .singleWindowList: .window
            case .help: .help
            }
        }
    }

    init(_ group: Group) {
        self.group = group
    }

    /// Placement for commands that provide information about the app, the
    /// terms of the user's license agreement, and so on.
    ///
    /// By default, this group includes "About" the app, an alert with the
    /// app's name and, where it is bundled with one, its version.
    public static let appInfo = Self(.appInfo)

    /// Placement for commands that expose app settings and preferences.
    ///
    /// By default, this group includes "Settings…" (⌘, unless the scene's
    /// `.keyboardShortcut` says otherwise), which presents the app's
    /// `Settings` scene, where the app declares one.
    public static let appSettings = Self(.appSettings)

    /// Placement for commands that expose services other apps provide.
    ///
    /// Empty by default: a terminal app has no Services menu.
    public static let systemServices = Self(.systemServices)

    /// Placement for commands that control the visibility of running apps.
    ///
    /// Empty by default: hiding apps is the terminal's business.
    public static let appVisibility = Self(.appVisibility)

    /// Placement for commands that result in app termination.
    ///
    /// By default, this group includes "Quit" the app, which quits as the
    /// app's quit key does (`StatusBarState.quitShortcut`, `q` unless the app
    /// moved it) once the menu has closed — so it quits exactly when the key
    /// would, whatever has the focus.
    public static let appTermination = Self(.appTermination)

    /// Placement for commands that create and open different kinds of
    /// documents.
    ///
    /// Empty by default.
    public static let newItem = Self(.newItem)

    /// Placement for commands that save open documents and close windows.
    ///
    /// Empty by default.
    public static let saveItem = Self(.saveItem)

    /// Placement for commands that relate to importing and exporting data
    /// using formats that the app doesn't natively support.
    ///
    /// Empty by default.
    public static let importExport = Self(.importExport)

    /// Placement for commands related to printing app content.
    ///
    /// Empty by default.
    public static let printItem = Self(.printItem)

    /// Placement for commands that control the Undo Manager.
    ///
    /// By default, this group includes Undo and Redo, on the app's
    /// `UndoManager`, titled with the step's action name, each disabled with
    /// no step to take, and showing the scene's undo and redo keys
    /// (`Scene.undoShortcuts(_:)`).
    public static let undoRedo = Self(.undoRedo)

    /// Placement for commands that interact with the Clipboard and manipulate
    /// content that is currently selected in the app's view hierarchy.
    ///
    /// By default, this group includes Cut, Copy and Paste, which press ⌘X,
    /// ⌘C and ⌘V — through the scene's `commandKey` — once the menu has closed:
    /// what those keys do to the focused view (a text field's own cut, copy
    /// and paste, a view's `onCopyCommand`).
    public static let pasteboard = Self(.pasteboard)

    /// Placement for commands that manipulate and transform text selections.
    ///
    /// Empty by default; ``TextEditingCommands`` adds Find… and Find Next.
    public static let textEditing = Self(.textEditing)

    /// Placement for commands that manipulate and transform the styles
    /// applied to text selections.
    ///
    /// Empty by default.
    public static let textFormatting = Self(.textFormatting)

    /// Placement for commands that manipulate the toolbar.
    ///
    /// Empty by default; ``ToolbarCommands`` adds Hide Toolbar.
    public static let toolbar = Self(.toolbar)

    /// Placement for commands that control the app's sidebar and full-screen
    /// modes.
    ///
    /// Empty by default; ``SidebarCommands`` adds Show Sidebar and
    /// ``InspectorCommands`` Show Inspector.
    public static let sidebar = Self(.sidebar)

    /// Placement for commands that control the size of the window.
    ///
    /// Empty by default: the terminal sizes its window.
    public static let windowSize = Self(.windowSize)

    /// Placement for commands that arrange all of an app's windows.
    ///
    /// By default, for an app that can have more than one window open, this
    /// group includes "Close Window", which closes the window in front when
    /// another is open behind it; empty for an app of one window.
    public static let windowArrangement = Self(.windowArrangement)

    /// Placement for commands that describe and reveal the app's open windows.
    ///
    /// By default, for an app that can have more than one window open, this
    /// group lists the open windows, the one in front checked; choosing one
    /// brings it to the front. Empty for an app of one window.
    public static let windowList = Self(.windowList)

    /// Placement for commands that describe and reveal any windows that the
    /// app defines.
    ///
    /// By default, for an app that can have more than one window open, this
    /// group lists its `Window` scenes; choosing one opens it, or brings its
    /// window to the front.
    public static let singleWindowList = Self(.singleWindowList)

    /// Placement for commands that present documentation and helpful
    /// information to people.
    ///
    /// Empty by default.
    public static let help = Self(.help)
}

// MARK: - The Standard Menus

/// The menu bar's standard menus, in the order the bar shows them; the app's
/// own menus (``CommandMenu``) go between View and Window, as SwiftUI puts
/// them.
enum StandardMenu: Int, CaseIterable, Comparable, Sendable {
    case app, file, edit, format, view, window, help

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The groups the menu holds, in order.
    var groups: [CommandGroupPlacement.Group] {
        CommandGroupPlacement.Group.allCases.filter { $0.menu == self }
    }
}
