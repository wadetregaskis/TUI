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

/// The menu bar: one row of menu titles, from the commands the scene declares,
/// each of which opens its menu.
///
/// The window's chrome host draws it on the top row, after the page and the
/// toolbars (`WindowChromeState.menuBar`), so it walks the commands — evaluating
/// the bodies of commands of the app's own type, with their `@FocusedValue`s —
/// after the page has published this frame's focused values.
///
/// **Opening a menu.** A click on a title, F10 (the first menu), or Alt and a
/// title's first letter where the terminal sends Option as Meta (the menu with
/// that letter; the first such menu). With a menu open, Left and Right step to
/// the menu beside it, F10 and Escape close it, and Alt and a letter open that
/// menu instead. The open menu is a pop-up `Menu`'s: the same rows, keys and
/// highlight, hanging from its title over the whole window. A keyboard-opened
/// menu highlights its first item, a pointer-opened one nothing. The titles are
/// not in the Tab ring: the bar is reached by its keys and the pointer.
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

    /// Shows the app menu's About alert (``_MenuBar``).
    let showAbout: () -> Void

    /// StateStorage property indices. The bar is drawn at an identity of the
    /// chrome host's, where no composite content renders.
    private enum StateIndex {
        static let state = 0
    }

    var body: Never { fatalError("_MenuBarCore renders via Renderable") }

    /// The menu bar for `commands`, or `nil` where no modifier declared any:
    /// a scene that only takes commands away (`commandsRemoved()`) declares
    /// none, and has no menu bar.
    @MainActor
    static func menuBar(for commands: SceneCommands) -> AnyView? {
        let declares = commands.declarations.contains { ($0 as? CommandsDeclaration)?.commands != nil }
        return declares ? AnyView(_MenuBar(commands: commands)) : nil
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring else { return FrameBuffer(lines: [""]) }
        let state = state(in: context)
        // Keep the box alive across the run loop's per-frame StateStorage GC.
        context.stateStorage?.markActive(context.identity)
        let menus = resolvedMenus(context: context)
        if let open = state.openMenu, open >= menus.count { state.close() }
        registerShortcuts(of: menus, except: state.openMenu, context: context)

        let titles = titleRow(menus, open: state.openMenu, context: context)
        var buffer = FrameBuffer(lines: [titles.line])
        attachTitleRegions(to: &buffer, titles, state: state, context: context)
        let sectionID = "menubar-\(context.identity.path)"
        if let open = state.openMenu {
            present(
                menus[open], at: open, column: titles.columns[open], over: &buffer, state: state,
                titles: titles, sectionID: sectionID, context: context)
        } else {
            // A menu just closed hands the focus back to the page.
            context.environment.focusManager?.deactivateSection(id: sectionID)
            attachOpeningKeys(titles, state: state, context: context)
        }
        return buffer
    }

    /// The persisted state, or a throwaway one outside a running app (no
    /// StateStorage: nothing then opens).
    private func state(in context: RenderContext) -> MenuBarState {
        guard let storage = context.stateStorage else { return MenuBarState() }
        let box: StateBox<MenuBarState> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.state),
            default: MenuBarState())
        return box.value
    }

    // MARK: The menus

    /// The bar's menus this frame: every declaration's commands walked, in
    /// the order the modifiers stand from the inside out, over the scene's own
    /// commands unless a modifier took them away.
    private func resolvedMenus(context: RenderContext) -> [ResolvedCommandMenu] {
        var collector = CommandsCollector(
            environment: context.environment, storage: context.stateStorage,
            identity: context.identity.child(type: Self.self))
        for (index, declaration) in commands.declarations.enumerated() {
            guard let commands = (declaration as? CommandsDeclaration)?.commands else { continue }
            collector.step(index, commands)
        }
        guard commands.includesSceneCommands else { return collector.resolvedMenus() }
        let own = SceneOwnCommands(showAbout: showAbout)
        return collector.resolvedMenus { own.items(for: $0, context: context) }
    }

    /// The open menu, presented as a pop-up `Menu`'s is, hanging from its
    /// title: its first row's text under the title's.
    private func present(
        _ menu: ResolvedCommandMenu, at index: Int, column: Int, over buffer: inout FrameBuffer,
        state: MenuBarState, titles: TitleRow, sectionID: String, context: RenderContext
    ) {
        var presenter = context
        let count = titles.columns.count
        presenter.environment.menuBarStep = MenuBarStep { [weak state] offset in
            state?.step(offset, among: count)
        }
        presentMenuPopover(
            items: _CommandMenuItems(groups: menu.groups), over: &buffer, controller: state.controller,
            sectionID: sectionID, itemsIndex: index,
            anchor: MenuAnchor(x: max(0, column - 1), y: 1, controlHeight: 1),
            dismiss: { [weak state] in state?.close() }, context: presenter)
        attachOpenMenuKeys(titles, state: state, sectionID: sectionID, context: context)
    }

    // MARK: The shortcuts

    /// Registers the key equivalents of `menus`' items but the open one's,
    /// which registers as it draws, each menu rendered at an identity of its
    /// own for its registrations alone.
    private func registerShortcuts(of menus: [ResolvedCommandMenu], except open: Int?, context: RenderContext) {
        guard let registry = context.environment.keyboardShortcutRegistry else { return }
        context.withThrowawayFrameDemand { quiet in
            var unseen = quiet.withRegistrationOnlyChannels()
            // Tall enough for every row: a row a column had no room for would
            // never render, and never register its key.
            unseen.availableHeight = Self.registrationCanvasHeight
            unseen.hasExplicitHeight = false
            registry.registeringCommands {
                for (index, menu) in menus.enumerated() where index != open {
                    _ = TUIkitView.renderToBuffer(
                        _CommandMenuItems(groups: menu.groups),
                        context: unseen.withChildIdentity(erasedType: _CommandMenuItems.self, key: menu.key))
                }
            }
        }
    }

    /// How tall a canvas the closed menus' items are rendered on.
    private static let registrationCanvasHeight = 4096
}

// MARK: - The Titles

extension _MenuBarCore {
    /// The bar's row of titles, and where each title is.
    struct TitleRow {
        /// The row, drawn.
        let line: String

        /// Each title's first column, the cell before its text.
        let columns: [Int]

        /// Each title's width, its cell on each side included.
        let widths: [Int]

        /// Each title's mnemonic: its first letter, if that is an ASCII
        /// letter, lowercased.
        let mnemonics: [Character?]
    }

    /// The row of titles: each menu's with a cell on each side, one after
    /// another from the left edge, the app's menu in bold, as a menu bar's
    /// first title is, and the open menu's in reverse.
    func titleRow(_ menus: [ResolvedCommandMenu], open: Int?, context: RenderContext) -> TitleRow {
        var line = ""
        var columns: [Int] = []
        var widths: [Int] = []
        var mnemonics: [Character?] = []
        var column = 0
        let palette = context.environment.palette
        for (index, menu) in menus.enumerated() {
            let name = title(of: menu)
            let chunk = HStack(spacing: 0) {
                Text(" ")
                name
                Text(" ")
            }
            let drawn =
                index == open
                ? self.line(chunk.foregroundStyle(palette.appHeaderBackground).background(palette.foreground), context)
                : self.line(chunk, context)
            let width = drawn.strippedLength
            columns.append(column)
            widths.append(width)
            mnemonics.append(drawn.stripped.trimmingCharacters(in: .whitespaces).first.flatMap(Self.mnemonic))
            line += drawn
            column += width
        }
        return TitleRow(line: line, columns: columns, widths: widths, mnemonics: mnemonics)
    }

    /// `view` drawn on one line at its natural width.
    private func line(_ view: some View, _ context: RenderContext) -> String {
        var lineContext = context.withChildIdentity(type: TitleRow.self, index: 0)
        lineContext.availableWidth = max(context.availableWidth, 1)
        lineContext.hasExplicitWidth = false
        return TUIkitView.renderToBuffer(view, context: lineContext).lines.first ?? ""
    }

    /// `menu`'s title.
    private func title(of menu: ResolvedCommandMenu) -> Text {
        switch menu.title {
        case .standard(.app): Text(Self.appName).bold()
        case .standard(let standard): Text(Self.name(of: standard))
        case .declared(let name): name
        }
    }

    /// `character`, lowercased, if it is an ASCII letter: what Alt and it
    /// opens.
    private static func mnemonic(_ character: Character) -> Character? {
        guard character.isASCII, character.isLetter else { return nil }
        return Character(character.lowercased())
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
