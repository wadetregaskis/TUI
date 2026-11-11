//  🖥️ TUI — A Terminal UI framework for Swift
//  DisplayCommands.swift
//
//  TUI's standard command set for display options: View ▸ Palette ▸,
//  Border Style ▸ and Control Style ▸ (owner ruling A-MENUBAR-1, option 3).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUIFoundation

// MARK: - Display Commands

/// A built-in set of commands for choosing how the app is drawn: View ▸
/// Palette ▸, Border Style ▸ and Control Style ▸, each a submenu of the
/// built-in choices with the one in force checked.
///
/// Every menu bar's View menu has the three already, among TUI's own
/// preferences at its foot, as the settings panel's View tab does
/// (`CommandGroupPlacement.accessibility`). Declaring these moves them to the
/// top of the View menu, in place of TUI's own, and is how an app that holds
/// one of the options in its own state hands that state to them — and to the
/// settings panel's View tab, which then chooses into it too.
///
/// TUI-specific: SwiftUI's apps take their colours and controls from the
/// platform. Kept apart from SwiftUI's own sets (``ToolbarCommands``,
/// ``SidebarCommands``), which it is written beside:
///
/// ```swift
/// WindowGroup { ContentView() }
///     .commands {
///         DisplayCommands()
///         ToolbarCommands()
///     }
/// ```
///
/// **With no arguments** it acts on the app's own managers — the palette and
/// appearance managers the `t` and `a` keys cycle (`\.paletteManager`,
/// `\.appearanceManager`), and the control style manager
/// (``EnvironmentValues/controlStyleManager``) — so a choice is drawn
/// everywhere at once, the window's bars included.
///
/// **An app that holds one of them itself** — keeps its palette in `@State`
/// and applies it with `.palette(_:)` or `.theme(_:)` at the scene, its border
/// with `.appearance(_:)`, its control style with
/// `.environment(\.controlStyle, …)` — overrides that manager, so a choice of
/// the manager's would show nothing. Its submenu is then disabled, showing
/// the scene's choice checked where it is one of the built-in ones, with help
/// saying why: TUI offers no item that does nothing. To have the menu
/// choose for such an app, pass its state as a binding, and the submenu
/// writes the choice there:
///
/// ```swift
/// @State private var palette: any Palette = SystemPalette(.green)
///
/// WindowGroup { ContentView() }
///     .palette(palette)
///     .commands { DisplayCommands(palette: $palette) }
/// ```
///
/// What counts as the scene's own is what its modifiers state for the window
/// in front: a `.palette(_:)` or `.theme(_:)`, an `.appearance(_:)` with an
/// appearance (`nil` leaves the manager in charge), an `.environment(_:_:)` of
/// `\.palette`, `\.appearance` or `\.controlStyle`, or an environment modifier
/// of one of those on the window group's root view. A modifier written deeper
/// in the content, round one page, is the page's: the menu cannot see it, and
/// the manager's choice still shows everywhere else.
///
/// The submenus sit in a section of their own at the top of the View menu,
/// before ``ToolbarCommands``' items.
public struct DisplayCommands: Commands {
    @Environment(\.paletteManager) private var paletteManager
    @Environment(\.appearanceManager) private var appearanceManager
    @Environment(\.controlStyleManager) private var controlStyleManager
    /// Which of the three the window in front's scene states for itself.
    @Environment(\.displayOptionsSetByScene) private var setByScene
    /// What is in force, shown checked where the scene states it.
    @Environment(\.palette) private var paletteInForce
    @Environment(\.appearance) private var appearanceInForce
    @Environment(\.controlStyle) private var controlStyleInForce

    private let palette: Binding<any Palette>?
    private let appearance: Binding<Appearance>?
    private let controlStyle: Binding<ControlStyle>?

    /// Creates the display commands, each choosing through the app's manager
    /// unless a binding is given for it.
    ///
    /// - Parameters:
    ///   - palette: The app's palette, which View ▸ Palette ▸ loads a built-in
    ///     palette into; `nil` for the palette manager.
    ///   - appearance: The app's border appearance, which View ▸ Border Style ▸
    ///     sets; `nil` for the appearance manager.
    ///   - controlStyle: The app's control style, which View ▸ Control Style ▸
    ///     sets; `nil` for the control style manager.
    public init(
        palette: Binding<any Palette>? = nil,
        appearance: Binding<Appearance>? = nil,
        controlStyle: Binding<ControlStyle>? = nil
    ) {
        self.palette = palette
        self.appearance = appearance
        self.controlStyle = controlStyle
    }

    public var body: some Commands {
        CommandGroup(before: .toolbar) {
            Section { choices.pickers }
        }
        DisplayChoicesOffered(bindings: .init(palette: palette, appearance: appearance, controlStyle: controlStyle))
    }

    /// The submenus' model, which the settings panel's View tab shares
    /// (``DisplayChoices``), choosing into the same bindings.
    private var choices: DisplayChoices {
        DisplayChoices(
            managers: (paletteManager, appearanceManager, controlStyleManager), setByScene: setByScene,
            inForce: (paletteInForce, appearanceInForce, controlStyleInForce),
            bindings: (palette, appearance, controlStyle))
    }
}

// MARK: - Offered

/// What ``DisplayCommands`` tells the collector: that the commands offer the
/// three submenus, so the View menu's own are left out, and the app's state
/// they choose into, which the settings panel's View tab chooses into too.
/// Adds no item.
struct DisplayChoicesOffered: Commands, _CommandsPrimitive {
    let bindings: DisplayChoices.Bindings

    var body: Never { fatalError("DisplayChoicesOffered hands its commands over itself") }

    func collectCommands(into collector: inout CommandsCollector) {
        collector.offersDisplayChoices = true
        collector.displayBindings = bindings
    }
}
