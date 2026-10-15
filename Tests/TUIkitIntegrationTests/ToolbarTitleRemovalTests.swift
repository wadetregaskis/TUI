//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarTitleRemovalTests.swift
//
//  `.toolbar(removing: .title)` (refusal review O17): the top bar's title
//  slot is empty while the view is drawn — anywhere but in presented content —
//  and a navigation stack's bar over a pushed screen keeps its Back button
//  alone, without the screen's title, subtitle or trail.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A titled page with an item in its top bar, its title removed or not.
private struct TitledPage: View {
    let removes: Bool

    var body: some View {
        let page = Text("PAGE")
            .navigationTitle("PAGE-TITLE")
            .navigationSubtitle("PAGE-SUB")
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        if removes {
            page.toolbar(removing: .title)
        } else {
            page
        }
    }
}

private struct KeptTitleApp: App {
    init() {}
    var body: some Scene { WindowGroup { TitledPage(removes: false) } }
}

private struct RemovedTitleApp: App {
    init() {}
    var body: some Scene { WindowGroup { TitledPage(removes: true) } }
}

/// A titled page under a sheet whose content removes the title: the sheet's
/// removal is the sheet's.
private struct SheetRemovesTitleApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TitledPage(removes: false)
                .sheet(isPresented: .constant(true)) { Text("SHEET").toolbar(removing: .title) }
        }
    }
}

@MainActor
@Suite("Removing the title", .rendersEnglishUI)
struct ToolbarTitleRemovalTests {
    /// The rows inside the window's top bar.
    private func topBar(_ app: some App) -> [String] {
        let headless = HeadlessApp(app, width: 60, height: 16)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        let rows = headless.screen.map(\.stripped)
        guard rows.first?.hasPrefix("╭") == true,
            let bottom = rows.dropFirst().firstIndex(where: { $0.hasPrefix("╰") })
        else { return [] }
        return Array(rows[1..<bottom])
    }

    @Test("The top bar's title slot is empty, and its items stay")
    func windowTitleSlot() {
        let kept = topBar(KeptTitleApp()).joined(separator: "\n")
        #expect(kept.contains("PAGE-TITLE") && kept.contains("PAGE-SUB"), "\(kept)")
        let removed = topBar(RemovedTitleApp()).joined(separator: "\n")
        #expect(removed.contains("ITEM"), "\(removed)")
        #expect(!removed.contains("PAGE-TITLE") && !removed.contains("PAGE-SUB"), "\(removed)")
    }

    @Test("A sheet's removal is the sheet's: the window keeps its title")
    func sheetRemovalIsTheSheets() {
        let bar = topBar(SheetRemovesTitleApp()).joined(separator: "\n")
        #expect(bar.contains("PAGE-TITLE"), "\(bar)")
    }

    // MARK: - A navigation stack's bar

    private struct Planet: Hashable {
        let name: String
    }

    /// The stack's bar row, over Mars pushed on Planets.
    private func stackBar(removedInScreen: Bool = false, removedOnStack: Bool = false) -> String {
        var path = NavigationPath()
        path.append(Planet(name: "Mars"))
        let binding = Binding(get: { path }, set: { path = $0 })
        let stack = NavigationStack(path: binding) {
            Text("root")
                .navigationTitle("Planets")
                .navigationDestination(for: Planet.self) { planet in
                    let screen = Text("surface").navigationTitle(planet.name).navigationSubtitle("The red one")
                    if removedInScreen {
                        screen.toolbar(removing: .title)
                    } else {
                        screen
                    }
                }
        }
        let view = removedOnStack ? AnyView(stack.toolbar(removing: .title)) : AnyView(stack)
        let lines = renderToBuffer(view, context: makeRenderContext(width: 60, height: 8)).lines.map(\.stripped)
        return lines.first ?? ""
    }

    @Test("A pushed screen's bar keeps its Back button, without the title, subtitle or trail")
    func pushedScreen() {
        let kept = stackBar()
        #expect(kept.contains("Mars") && kept.contains("The red one"), "\(kept)")
        for (name, bar) in [("in the screen", stackBar(removedInScreen: true)), ("on the stack", stackBar(removedOnStack: true))] {
            #expect(bar.contains("Back"), "\(name): \(bar)")
            #expect(!bar.contains("Mars") && !bar.contains("The red one") && !bar.contains("Planets"), "\(name): \(bar)")
        }
    }
}
