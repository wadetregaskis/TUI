//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisplayCommands.swift
//
//  TUIkit's standard command set for display options: View ▸ Palette ▸,
//  Border Style ▸ and Control Style ▸ (owner ruling A-MENUBAR-1, option 3).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitChrome
import TUIkitFoundation
import TUIkitPickers

// MARK: - Display Commands

/// A built-in set of commands for choosing how the app is drawn: View ▸
/// Palette ▸, Border Style ▸ and Control Style ▸, each a submenu of the
/// built-in choices with the one in force checked.
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
/// saying why: TUIkit offers no item that does nothing. To have the menu
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
            Section {
                submenu(.palette, selection: paletteSelection, availability: availability(.palette)) {
                    ForEach(0..<PaletteRegistry.all.count, id: \.self) { index in
                        Text(verbatim: PaletteRegistry.all[index].name).tag(PaletteRegistry.all[index].id)
                    }
                }
                submenu(.borderStyle, selection: appearanceSelection, availability: availability(.appearance)) {
                    ForEach(0..<AppearanceRegistry.all.count, id: \.self) { index in
                        Text(verbatim: AppearanceRegistry.all[index].localizedName).tag(AppearanceRegistry.all[index].id)
                    }
                }
                submenu(.controlStyle, selection: controlStyleSelection, availability: availability(.controlStyle)) {
                    ForEach(0..<ControlStyle.standardStyles.count, id: \.self) { index in
                        Text(verbatim: ControlStyle.standardStyles[index].name).tag(ControlStyle.standardStyles[index])
                    }
                }
            }
        }
    }
}

// MARK: - The Submenus

extension DisplayCommands {
    /// Whether a choice of `option` would show, and if not, whether the scene
    /// is why.
    private enum Availability {
        /// Through the binding, or the manager.
        case available
        /// The scene states its own, which a manager's choice would not show
        /// through.
        case setByScene
        /// No binding and no manager: outside a running app.
        case unavailable
    }

    /// Whether a choice of `option` shows: always through a binding, and
    /// through the manager unless the scene states its own.
    private func availability(_ option: SceneDisplayOptions) -> Availability {
        let (bound, managed): (Bool, Bool) =
            switch option {
            case .palette: (palette != nil, paletteManager != nil)
            case .appearance: (appearance != nil, appearanceManager != nil)
            default: (controlStyle != nil, controlStyleManager != nil)
            }
        if bound { return .available }
        if setByScene.contains(option) { return .setByScene }
        return managed ? .available : .unavailable
    }

    /// A `Picker` over `options`, titled `title`: a submenu with the selected
    /// option checked. Where a choice would not show it is disabled — a
    /// submenu of disabled items, which still opens, as macOS draws a disabled
    /// picker — with help saying so where the scene is why.
    @ViewBuilder
    private func submenu<Selection: Hashable, Options: View>(
        _ title: LocalizationKey.Menu, selection: Binding<Selection>, availability: Availability,
        @ViewBuilder options: () -> Options
    ) -> some View {
        let service = LocalizationService.shared
        let picker = Picker(service.string(for: title), selection: selection, content: options)
        switch availability {
        case .available:
            picker
        case .setByScene:
            picker
                .disabled(true)
                .help(Text(verbatim: service.string(for: LocalizationKey.Menu.displaySetByApp)))
        case .unavailable:
            picker.disabled(true)
        }
    }

    /// The palette chosen, by its id: the binding's, or the manager's — or,
    /// where the scene states its own, that one's, which is what is drawn.
    private var paletteSelection: Binding<String> {
        if let palette {
            return Binding(
                get: { palette.wrappedValue.id },
                set: { id in PaletteRegistry.palette(withId: id).map { palette.wrappedValue = $0 } })
        }
        let manager = paletteManager
        let stated = setByScene.contains(.palette) ? paletteInForce.id : nil
        return Binding(
            get: { stated ?? manager?.current.id ?? "" },
            set: { id in PaletteRegistry.palette(withId: id).map { manager?.setCurrent($0) } })
    }

    /// The border appearance chosen, by its id, as ``paletteSelection``.
    private var appearanceSelection: Binding<String> {
        if let appearance {
            return Binding(
                get: { appearance.wrappedValue.id },
                set: { id in
                    AppearanceRegistry.all.first { $0.id == id }.map { appearance.wrappedValue = $0 }
                })
        }
        let manager = appearanceManager
        let stated = setByScene.contains(.appearance) ? appearanceInForce.id : nil
        return Binding(
            get: { stated ?? manager?.current.id ?? "" },
            set: { id in AppearanceRegistry.all.first { $0.id == id }.map { manager?.setCurrent($0) } })
    }

    /// The control style chosen, as ``paletteSelection``.
    private var controlStyleSelection: Binding<ControlStyle> {
        if let controlStyle { return controlStyle }
        let manager = controlStyleManager
        let stated = setByScene.contains(.controlStyle) ? controlStyleInForce : nil
        return Binding(
            get: { stated ?? manager?.currentControlStyle ?? .automatic },
            set: { manager?.setCurrent($0) })
    }
}
