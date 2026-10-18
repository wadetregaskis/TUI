//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _MenuBarCore.swift
//
//  The menu bar a scene's commands draw, on the window's top row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitApp
import TUIkitFoundation

/// The menu bar: one row of menu titles, from the commands the scene declares.
///
/// The window's chrome host draws it on the top row, after the page and the
/// toolbars (`WindowChromeState.menuBar`), so it walks the commands — evaluating
/// the bodies of commands of the app's own type, with their `@FocusedValue`s —
/// after the page has published this frame's focused values.
///
/// **Shortcuts with every menu closed.** A command's keyboard shortcut works
/// whether its menu is open or not, as SwiftUI's do. A closed menu draws
/// nothing, so each frame the closed menus' items are rendered for their
/// registrations alone (`RenderContext.withRegistrationOnlyChannels()`): into
/// the live shortcut registry, below whatever the page registered on the same
/// key (`KeyboardShortcutRegistry.registeringCommands(_:)`), and into nothing
/// else — no focus, no click region, no status-bar item, no frame demand.
/// A `.disabled` command registers nothing, as a disabled button does not.
struct _MenuBarCore: View, Renderable {
    /// What the scene's commands modifiers gathered.
    let commands: SceneCommands

    var body: Never { fatalError("_MenuBarCore renders via Renderable") }

    /// The menu bar for `commands`, or `nil` where no modifier declared any:
    /// a scene that only takes commands away (`commandsRemoved()`) declares
    /// none, and has no menu bar.
    @MainActor
    static func menuBar(for commands: SceneCommands) -> AnyView? {
        let declares = commands.declarations.contains { ($0 as? CommandsDeclaration)?.commands != nil }
        return declares ? AnyView(Self(commands: commands)) : nil
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring else { return FrameBuffer(lines: [""]) }
        let menus = resolvedMenus(context: context)
        registerShortcuts(of: menus, context: context)
        return titleRow(menus, context: context)
    }

    // MARK: The menus

    /// The bar's menus this frame: every declaration's commands walked, in
    /// the order the modifiers stand from the inside out.
    private func resolvedMenus(context: RenderContext) -> [ResolvedCommandMenu] {
        var collector = CommandsCollector(
            environment: context.environment, storage: context.stateStorage,
            identity: context.identity.child(type: Self.self))
        for (index, declaration) in commands.declarations.enumerated() {
            guard let commands = (declaration as? CommandsDeclaration)?.commands else { continue }
            collector.step(index, commands)
        }
        return collector.resolvedMenus()
    }

    // MARK: The shortcuts

    /// Registers the key equivalents of `menus`' items, each menu rendered at
    /// an identity of its own for its registrations alone.
    private func registerShortcuts(of menus: [ResolvedCommandMenu], context: RenderContext) {
        guard let registry = context.environment.keyboardShortcutRegistry else { return }
        context.withThrowawayFrameDemand { quiet in
            var unseen = quiet.withRegistrationOnlyChannels()
            // Tall enough for every row: a row a column had no room for would
            // never render, and never register its key.
            unseen.availableHeight = Self.registrationCanvasHeight
            unseen.hasExplicitHeight = false
            registry.registeringCommands {
                for menu in menus {
                    _ = TUIkitView.renderToBuffer(
                        _CommandMenuItems(groups: menu.groups),
                        context: unseen.withChildIdentity(erasedType: _CommandMenuItems.self, key: menu.key))
                }
            }
        }
    }

    /// How tall a canvas the closed menus' items are rendered on.
    private static let registrationCanvasHeight = 4096

    // MARK: The titles

    /// The row of titles: each menu's, a cell in from the left and two apart,
    /// the app's menu in bold, as a menu bar's first title is.
    private func titleRow(_ menus: [ResolvedCommandMenu], context: RenderContext) -> FrameBuffer {
        var line = " "
        for (index, menu) in menus.enumerated() {
            if index > 0 { line += "  " }
            line += title(of: menu, context: context)
        }
        return FrameBuffer(lines: [line])
    }

    /// `menu`'s title, drawn.
    private func title(of menu: ResolvedCommandMenu, context: RenderContext) -> String {
        let text: Text =
            switch menu.title {
            case .standard(.app): Text(Self.appName).bold()
            case .standard(let standard): Text(Self.name(of: standard))
            case .declared(let name): name
            }
        var titleContext = context.withChildIdentity(type: Text.self, index: 0)
        titleContext.hasExplicitWidth = false
        return TUIkitView.renderToBuffer(text, context: titleContext).lines.first ?? ""
    }

    /// The app's name, as its menu is titled: the process's.
    static var appName: String { ProcessInfo.processInfo.processName }

    /// A standard menu's name, in the app's language.
    static func name(of menu: StandardMenu) -> String {
        let service = LocalizationService.shared
        switch menu {
        case .app: return appName
        case .file: return service.string(for: LocalizationKey.Menu.file)
        case .edit: return service.string(for: LocalizationKey.Menu.edit)
        case .format: return service.string(for: LocalizationKey.Menu.format)
        case .view: return service.string(for: LocalizationKey.Menu.view)
        case .window: return service.string(for: LocalizationKey.Menu.window)
        case .help: return service.string(for: LocalizationKey.Menu.help)
        }
    }
}
