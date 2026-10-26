//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarTitleMenu.swift
//
//  The title menu of the window's top bar: the title made a pull-down whose
//  items act on the content the title names.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Toolbar Title Menu

/// The title menu of a toolbar — mirrors SwiftUI's `ToolbarTitleMenu`.
///
/// Placed in a `.toolbar`, it makes the window's title in the top bar a
/// pull-down: the title and a caret, which Return, Space or a click opens as a
/// menu of the items, hung beneath the title.
///
/// ```swift
/// ContentView()
///     .navigationTitle("Draft")
///     .toolbar {
///         ToolbarTitleMenu {
///             Button("Duplicate") { duplicate() }
///             Button("Print") { print() }
///         }
///     }
/// ```
///
/// The menu is the title's, so it is drawn where the title is: not while a
/// principal item takes the title's place, not with `.toolbar(removing:
/// .title)`, and not with no `.navigationTitle` to show. Its items are drawn
/// in the environment of the view that declared it, as any toolbar item is.
/// The first title menu the page declares is the one the title opens.
///
/// SwiftUI fills ``init()``'s menu from the app's commands (`saveItem`,
/// `printItem`, …); TUI's leaves the title as it is — the commands are in
/// the menu bar. Give the menu its items with ``init(content:)``.
public struct ToolbarTitleMenu<Content: View>: ToolbarContent {
    /// The menu's items.
    let content: Content

    /// Creates a toolbar title menu.
    ///
    /// - Parameter content: The content of the toolbar title menu.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Never called: a title menu hands itself to the bar.
    public var body: Never { fatalError("ToolbarTitleMenu hands itself to the bar") }
}

extension ToolbarTitleMenu where Content == EmptyView {
    /// Creates a toolbar title menu where actions are inferred from your app's
    /// commands.
    ///
    /// In a terminal the commands are the menu bar's, and the title is left
    /// as it is: a title menu with nothing in it opens nothing.
    public init() {
        self.content = EmptyView()
    }
}

extension ToolbarTitleMenu: _ToolbarContentPrimitive {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        // Nothing to open: the title stays a title.
        guard Content.self != EmptyView.self else { return }
        items.append(placement: .automatic, view: AnyView(_ToolbarTitleMenuView(items: content)), isTitleMenu: true)
    }
}

// MARK: - Public Modifier

extension View {
    /// Configure the title menu of a toolbar — mirrors SwiftUI's
    /// `toolbarTitleMenu(content:)`.
    ///
    /// The same as placing a ``ToolbarTitleMenu`` in a `.toolbar`: the window's
    /// title in the top bar becomes a pull-down of `content`.
    ///
    /// ```swift
    /// ContentView()
    ///     .navigationTitle("Draft")
    ///     .toolbarTitleMenu {
    ///         Button("Duplicate") { duplicate() }
    ///         Button("Print") { print() }
    ///     }
    /// ```
    ///
    /// - Parameter content: The content associated to the toolbar title menu.
    /// - Returns: A view whose toolbar's title opens `content`.
    public func toolbarTitleMenu<C: View>(@ViewBuilder content: () -> C) -> some View {
        _ToolbarModifier(content: self, items: ToolbarTitleMenu(content: content))
    }
}

// MARK: - The Title as a Pull-Down

/// The title the bar shows, as its title slot hands it to a title menu drawn
/// there.
struct _ToolbarTitleSlot: Equatable {
    let title: String
    let subtitle: String
}

/// Environment key for the title a title menu draws.
private struct ToolbarTitleSlotKey: EnvironmentKey {
    static let defaultValue = _ToolbarTitleSlot(title: "", subtitle: "")
}

extension EnvironmentValues {
    /// The window's title and subtitle, as the top bar's title slot hands
    /// them to the title menu it draws there.
    var toolbarTitleSlot: _ToolbarTitleSlot {
        get { self[ToolbarTitleSlotKey.self] }
        set { self[ToolbarTitleSlotKey.self] = newValue }
    }
}

/// The window's title as a pull-down of `items`.
struct _ToolbarTitleMenuView<Items: View>: View {
    let items: Items

    @Environment(\.toolbarTitleSlot) private var slot

    var body: some View {
        _ToolbarPullDown(label: _ToolbarTitle(title: slot.title, subtitle: slot.subtitle), items: items, isPlain: true)
    }
}
