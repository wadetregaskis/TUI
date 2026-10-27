//  🖥️ TUI — A Terminal UI framework for Swift
//  _MenuBarCore.swift
//
//  The menu bar a scene's commands draw, on the window's top row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIApp
import TUIFoundation

/// The menu bar: one row of menu titles, from the commands the scene declares,
/// each of which opens its menu.
///
/// The window's chrome host draws it on the top row, after the page and the
/// toolbars (`WindowChromeState.menuBar`), so it walks the commands — evaluating
/// the bodies of commands of the app's own type, with their `@FocusedValue`s —
/// after the page has published this frame's focused values.
///
/// **Opening a menu.** A press on a title — dragged down the menu and let go
/// on an item, it runs the item, as a Mac's menu bar does — F10, which walks
/// the titles with every menu closed (the bar mode,
/// ``walkTitles(_:over:state:titleIDs:sectionID:context:)``: a title's letter,
/// Down or Return opens its menu), or Alt and a title's letter where the
/// terminal sends Option as Meta (``MenuBarMnemonics``: one per title, no two
/// the same, underlined in the bar mode and while Option is held where the
/// terminal reports it). With a menu open, Left and
/// Right step to the menu beside it, F10 and Escape close it, and Alt and a
/// letter open that menu instead; and the pointer moved or dragged onto
/// another title opens its menu, as on a Mac
/// (``titleTracking(_:state:context:)``). The open menu is a pop-up `Menu`'s:
/// the same rows, keys and highlight, hanging from its title over the whole
/// window. A keyboard-opened menu highlights its first item, a pointer-opened
/// one nothing. The titles are not in the Tab ring: the bar is reached by its
/// keys and the pointer.
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
        // Drawn as a backdrop — under a modal (`_WindowChromeHost.menuBarBuffer`)
        // — the bar is a picture of itself. Its keys and shortcuts go to the
        // backdrop's throwaway channels already; the mouse dispatcher is the
        // live one, so its open menu closes and its titles take no click, as
        // an inert toolbar item drops its regions (`_ToolbarEntryView`).
        let isInert = context.environment.drawsBackdrop
        if isInert { state.close() }
        let menus = resolvedMenus(context: context)
        if let open = state.openMenu ?? state.highlightedTitle, open >= menus.count { state.close() }
        registerShortcuts(of: menus, except: state.openMenu, context: context)

        let titles = titleRow(
            menus, open: state.openMenu ?? state.highlightedTitle, walking: state.highlightedTitle != nil,
            context: context)
        var buffer = FrameBuffer(lines: [titles.line])
        guard !isInert else { return buffer }
        let titleIDs = attachTitleRegions(to: &buffer, titles, state: state, context: context)
        let sectionID = "menubar-\(context.identity.path)"
        if let open = state.openMenu {
            present(
                menus[open], at: open, over: &buffer, state: state,
                titles: titles, tracking: titleTracking(titleIDs, state: state, context: context),
                sectionID: sectionID, context: context)
        } else if state.highlightedTitle != nil {
            walkTitles(titles, over: &buffer, state: state, titleIDs: titleIDs, sectionID: sectionID, context: context)
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
        _ menu: ResolvedCommandMenu, at index: Int, over buffer: inout FrameBuffer,
        state: MenuBarState, titles: TitleRow, tracking: MenuBackdropPassThrough?, sectionID: String,
        context: RenderContext
    ) {
        var presenter = context
        let count = titles.columns.count
        presenter.environment.menuBarStep = MenuBarStep { [weak state] offset in
            state?.step(offset, among: count)
        }
        presentMenuPopover(
            items: _CommandMenuItems(groups: menu.groups), over: &buffer, controller: state.controller,
            sectionID: sectionID, itemsIndex: index,
            anchor: MenuAnchor(x: max(0, titles.columns[index] - 1), y: 1, controlHeight: 1),
            dismiss: { [weak state] in state?.close() }, passThrough: tracking, context: presenter)
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
                    _ = TUIView.renderToBuffer(
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

        /// Each title's mnemonic, lowercased (``MenuBarMnemonics``); none for
        /// the app's menu.
        let mnemonics: [Character?]
    }

    /// The row of titles: each menu's with a cell on each side, one after
    /// another from the left edge, the app's menu in bold, as a menu bar's
    /// first title is, and the open menu's — or, `walking` the bar with every
    /// menu closed, the highlighted title's — in reverse. In the bar mode, and
    /// while Option is held where the terminal reports it
    /// (``showsMnemonics(_:)``), each title's letter is underlined.
    func titleRow(_ menus: [ResolvedCommandMenu], open: Int?, walking: Bool, context: RenderContext) -> TitleRow {
        let appName = context.environment.resolvedAboutPanel.name
        var drawn = menus.enumerated().map { index, menu in
            self.line(chunk(title(of: menu, appName: appName), open: index == open, context), context)
        }
        let plain: [String?] = zip(menus, drawn).map { menu, line in
            // The app's menu has no letter (``MenuBarMnemonics``).
            if case .standard(.app) = menu.title { return nil }
            return line.stripped.trimmingCharacters(in: .whitespaces)
        }
        let kept = MenuBarMnemonics.kept(by: context.environment.focusManager?.currentFocused)
        let mnemonics = MenuBarMnemonics.assign(plain, keeping: kept)
        if walking || showsMnemonics(context) {
            for (index, letter) in mnemonics.enumerated() {
                guard let letter, let title = plain[index], let parts = MenuBarMnemonics.split(title, at: letter)
                else { continue }
                let underlined = HStack(spacing: 0) {
                    Text(verbatim: parts.before)
                    Text(verbatim: parts.letter).underline()
                    Text(verbatim: parts.after)
                }
                drawn[index] = self.line(chunk(underlined, open: index == open, context), context)
            }
        }
        var line = ""
        var columns: [Int] = []
        var widths: [Int] = []
        for title in drawn {
            columns.append(line.strippedLength)
            widths.append(title.strippedLength)
            line += title
        }
        return TitleRow(line: line, columns: columns, widths: widths, mnemonics: mnemonics)
    }

    /// `name` with a cell on each side, in reverse if its menu is `open`.
    @ViewBuilder
    private func chunk(_ name: some View, open: Bool, _ context: RenderContext) -> some View {
        let chunk = HStack(spacing: 0) {
            Text(" ")
            name
            Text(" ")
        }
        let palette = context.environment.palette
        if open {
            chunk.foregroundStyle(palette.appHeaderBackground).background(palette.foreground)
        } else {
            chunk
        }
    }

    /// Whether the titles' letters are shown: while Option is held, where the
    /// terminal reports a modifier key held alone (the kitty keyboard
    /// protocol: `modifierKeyMonitor` is published only there). Elsewhere
    /// nothing says Option is down, and nothing is shown.
    ///
    /// Read each frame, so the bar asks for a frame when Option changes —
    /// and only Option: Shift, held for every capital typed, asks for none.
    private func showsMnemonics(_ context: RenderContext) -> Bool {
        guard let monitor = context.environment.modifierKeyMonitor else { return false }
        // Drawn from keys that change between frames with no state changing,
        // as a modifier key alternate is: no memo may keep it.
        context.environment.volatileReadTracker?.recordVolatileRead()
        if !context.isMeasuring { monitor.noteDrawnFrom(.option) }
        return monitor.current.contains(.option)
    }

    /// `view` drawn on one line at its natural width.
    private func line(_ view: some View, _ context: RenderContext) -> String {
        var lineContext = context.withChildIdentity(type: TitleRow.self, index: 0)
        lineContext.availableWidth = max(context.availableWidth, 1)
        lineContext.hasExplicitWidth = false
        return TUIView.renderToBuffer(view, context: lineContext).lines.first ?? ""
    }

    /// `menu`'s title, the app's menu titled `appName`.
    private func title(of menu: ResolvedCommandMenu, appName: String) -> Text {
        switch menu.title {
        case .standard(.app): Text(appName).bold()
        case .standard(let standard): Text(Self.name(of: standard, appName: appName))
        case .declared(let name): name
        }
    }

    /// A standard menu's name, in the app's language, the app's titled
    /// `appName` (``ResolvedAboutPanel/name``).
    static func name(of menu: StandardMenu, appName: String) -> String {
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
