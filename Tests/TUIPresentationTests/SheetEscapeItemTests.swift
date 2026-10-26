//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetEscapeItemTests.swift
//
//  A sheet's Escape is the sheet's, whatever status bar items its content
//  declares: they are added to the sheet's own Escape item, never put in its
//  place, so a page's "⎋ back" declared around the view presenting the sheet
//  does not answer Escape from behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("A sheet keeps its Escape item among its content's items", .rendersEnglishUI)
struct SheetEscapeItemTests {
    /// The page's state, by reference so the bindings a frame built reach it.
    private final class Model {
        var presented = true
        /// How many times the page's own "⎋ back" ran.
        var pageWentBack = 0
        /// How many times the content's own Escape item ran.
        var contentEscapes = 0
        var reloads = 0
        var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
    }

    /// A page carrying "⎋ back" outside everything it presents, as the
    /// Example's pages do, presenting a sheet whose content is `content`.
    private func page(_ model: Model, @ViewBuilder content: @escaping () -> some View) -> some View {
        Text("page")
            .sheet(isPresented: model.binding, content: content)
            .statusBarItems {
                StatusBarItem(shortcut: Shortcut.escape, label: "back") { model.pageWentBack += 1 }
            }
    }

    /// A sheet whose content declares an item of its own, in `composition`.
    private func sheetWithItems(_ model: Model, _ composition: StatusBarItemComposition = .merge) -> some View {
        page(model) {
            Text("draft")
                .statusBarItems(composition) {
                    StatusBarItem(shortcut: "r", label: "reload") { model.reloads += 1 }
                }
        }
    }

    /// The bar's items, as `shortcut label`, the system items left out.
    private func items(_ harness: InputChainHarness) -> [String] {
        harness.statusBar.currentUserItems.filter(\.displayInStatusBar).map { "\($0.shortcut) \($0.label)" }
    }

    @Test("Escape dismisses a sheet whose content declares items, not the page's Escape outside it")
    func escapeIsTheSheets() {
        let model = Model()
        let harness = InputChainHarness(width: 60, height: 20)
        let taken = harness.play([KeyEvent(key: .escape)]) { sheetWithItems(model) }
        #expect(taken == [true])
        #expect(!model.presented, "Escape did not dismiss the sheet")
        #expect(model.pageWentBack == 0, "the page's ⎋ back answered Escape from behind the sheet")
    }

    @Test("The bar shows the content's items beside the sheet's Escape, and not the page's")
    func barShowsBoth() {
        let model = Model()
        let harness = InputChainHarness(width: 60, height: 20)
        harness.frame(sheetWithItems(model))
        harness.frame(sheetWithItems(model))
        let shown = items(harness)
        #expect(shown.contains("r reload"), "\(shown)")
        #expect(shown.contains("⎋ dismiss"), "\(shown)")
        #expect(!shown.contains("⎋ back"), "\(shown)")
    }

    @Test("Content items that replace their parents' still leave the sheet its Escape")
    func replacingItemsKeepEscape() {
        let model = Model()
        let harness = InputChainHarness(width: 60, height: 20)
        harness.frame(sheetWithItems(model, .replace))
        harness.frame(sheetWithItems(model, .replace))
        #expect(Set(items(harness)) == ["r reload", "⎋ dismiss"], "\(items(harness))")
        harness.play([KeyEvent(key: .escape)]) { sheetWithItems(model, .replace) }
        #expect(!model.presented)
        #expect(model.pageWentBack == 0)
    }

    @Test("An Escape item the content declares stands, and the page's still does not answer")
    func contentEscapeStands() {
        let model = Model()
        let harness = InputChainHarness(width: 60, height: 20)
        let build = {
            page(model) {
                Text("draft")
                    .statusBarItems {
                        StatusBarItem(shortcut: Shortcut.escape, label: "revert") { model.contentEscapes += 1 }
                    }
            }
        }
        harness.play([KeyEvent(key: .escape)], build)
        #expect(model.contentEscapes == 1, "the content's own Escape item did not run")
        #expect(model.presented, "the content's Escape item is the content's to decide; it did not dismiss")
        #expect(model.pageWentBack == 0)
        #expect(items(harness).filter { $0.hasPrefix("⎋") } == ["⎋ revert"], "\(items(harness))")
    }

    @Test("Where the content forbids dismissal, Escape is held, and still not the page's")
    func heldEscapeIsKept() {
        let model = Model()
        let harness = InputChainHarness(width: 60, height: 20)
        let build = {
            page(model) {
                Text("draft")
                    .interactiveDismissDisabled()
                    .statusBarItems { StatusBarItem(shortcut: "r", label: "reload") { model.reloads += 1 } }
            }
        }
        let taken = harness.play([KeyEvent(key: .escape)], build)
        #expect(taken == [true])
        #expect(model.presented)
        #expect(model.pageWentBack == 0, "the page's ⎋ back answered Escape from behind the sheet")
        #expect(!items(harness).contains { $0.hasPrefix("⎋") }, "a held Escape shows nothing: \(items(harness))")
    }
}
