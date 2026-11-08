//  🖥️ TUI — A Terminal UI framework for Swift
//  DisplayChoices.swift
//
//  The display options a person chooses among — the palette, the border
//  style and the control style — as `Picker`s with the one in force
//  selected: what `DisplayCommands`' submenus are made of.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIChrome
import TUIFoundation
import TUIPickers

// MARK: - Display Choices

/// The palette, border style and control style choices, each a `Picker` of the
/// built-in options with the one in force selected: `DisplayCommands`' View ▸
/// Palette ▸, Border Style ▸ and Control Style ▸.
///
/// Each chooses through a binding where one is given, and otherwise through
/// the app's manager — the palette and appearance managers the `t` and `a`
/// keys cycle, and the control style manager — so a choice is drawn
/// everywhere at once. Where the window in front's scene states its own
/// option (`.palette(_:)`, `.appearance(_:)`, an `.environment` of one of
/// them), a manager's choice would show nothing: that picker is disabled,
/// showing the scene's choice where it is a built-in one, with help saying
/// why.
@MainActor
package struct DisplayChoices {
    /// The managers the choices go to where no binding is given.
    let paletteManager: ThemeManager?
    let appearanceManager: ThemeManager?
    let controlStyleManager: ThemeManager?

    /// Which of the three the window in front's scene states for itself.
    let setByScene: SceneDisplayOptions

    /// What is in force, shown selected where the scene states it.
    let paletteInForce: any Palette
    let appearanceInForce: Appearance
    let controlStyleInForce: ControlStyle

    /// The app's own state, where it holds an option itself.
    let palette: Binding<any Palette>?
    let appearance: Binding<Appearance>?
    let controlStyle: Binding<ControlStyle>?

    /// The choices over `environment`'s managers and what is in force there,
    /// each going to its binding where one is given.
    package init(
        environment: EnvironmentValues, palette: Binding<any Palette>? = nil,
        appearance: Binding<Appearance>? = nil, controlStyle: Binding<ControlStyle>? = nil
    ) {
        self.init(
            managers: (environment.paletteManager, environment.appearanceManager, environment.controlStyleManager),
            setByScene: environment.displayOptionsSetByScene,
            inForce: (environment.palette, environment.appearance, environment.controlStyle),
            bindings: (palette, appearance, controlStyle))
    }

    /// The choices over `managers` — the palette's, the appearance's and the
    /// control style's — with what is `inForce` in the same order, each going
    /// to its binding in `bindings` where one is given.
    package init(
        managers: (ThemeManager?, ThemeManager?, ThemeManager?), setByScene: SceneDisplayOptions,
        inForce: (any Palette, Appearance, ControlStyle),
        bindings: (Binding<any Palette>?, Binding<Appearance>?, Binding<ControlStyle>?)
    ) {
        (paletteManager, appearanceManager, controlStyleManager) = managers
        self.setByScene = setByScene
        (paletteInForce, appearanceInForce, controlStyleInForce) = inForce
        (palette, appearance, controlStyle) = bindings
    }

    /// The three pickers, in the order the View menu lists them.
    @ViewBuilder
    package var pickers: some View {
        picker(.palette, selection: paletteSelection, availability: availability(.palette)) {
            ForEach(0..<PaletteRegistry.all.count, id: \.self) { index in
                Text(verbatim: PaletteRegistry.all[index].name).tag(PaletteRegistry.all[index].id)
            }
        }
        picker(.borderStyle, selection: appearanceSelection, availability: availability(.appearance)) {
            ForEach(0..<AppearanceRegistry.all.count, id: \.self) { index in
                Text(verbatim: AppearanceRegistry.all[index].localizedName).tag(AppearanceRegistry.all[index].id)
            }
        }
        picker(.controlStyle, selection: controlStyleSelection, availability: availability(.controlStyle)) {
            ForEach(0..<ControlStyle.standardStyles.count, id: \.self) { index in
                Text(verbatim: ControlStyle.standardStyles[index].name).tag(ControlStyle.standardStyles[index])
            }
        }
    }
}

// MARK: - The Pickers

extension DisplayChoices {
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

    /// A `Picker` over `options`, titled `title`: in a menu, a submenu with
    /// the selected option checked. Where a choice would not show it is
    /// disabled — in a menu, a submenu of disabled items, which still opens,
    /// as macOS draws a disabled picker — with help saying so where the scene
    /// is why.
    @ViewBuilder
    private func picker<Selection: Hashable, Options: View>(
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
