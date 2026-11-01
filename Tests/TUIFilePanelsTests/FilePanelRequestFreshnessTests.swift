//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelRequestFreshnessTests.swift
//
//  A panel is asked for what the app says as it opens: not what the frame
//  before said, however the app's change and the opening reach it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import Observation

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

private let markdown = UTType("net.daringfireball.markdown") ?? .plainText

/// When the page changes the panel's types, relative to opening it.
private enum Change {
    /// In the button's action, with the opening.
    case inTheAction
    /// In an `onChange` of the opening, which runs in the frame that opens it.
    case inAnEffect
    /// In the frame before, with the opening in the frame after.
    case aFrameBefore
}

private struct Page: View {
    let change: Change
    @State private var types: [UTType] = [.plainText, markdown]
    @State private var showing = false
    @State private var note = "a note"

    var body: some View {
        Button("Export") {
            switch change {
            case .inTheAction:
                types = [markdown, .plainText]
                showing = true
            case .inAnEffect:
                showing = true
            case .aFrameBefore:
                types = [markdown, .plainText]
            }
        }
        .fileExporter(isPresented: $showing, item: note, contentTypes: types, onCompletion: { _ in })
        .onChange(of: showing) { _, isShowing in
            if change == .inAnEffect, isShowing { types = [markdown, .plainText] }
        }
        .onChange(of: types) { _, _ in
            if change == .aFrameBefore { showing = true }
        }
    }
}

/// A page as an app, to be drawn through the run loop's own frames.
private struct PageApp<Page: View>: App {
    let page: @MainActor () -> Page
    /// `App`'s requirement; these apps are built with ``init(_:)``.
    init() { self.page = { fatalError("built with init(_:)") } }
    init(_ page: @escaping @MainActor () -> Page) { self.page = page }
    var body: some Scene { WindowGroup { page() } }
}

@Observable
@MainActor
private final class TypesModel {
    var types: [UTType] = [.plainText, markdown]
    var showing = false
}

private struct ModelPage: View {
    let model: TypesModel
    @State private var note = "a note"

    var body: some View {
        Text("page")
            .fileExporter(
                isPresented: Binding(get: { model.showing }, set: { model.showing = $0 }),
                item: note, contentTypes: model.types, onCompletion: { _ in })
    }
}

/// The everyday shape: an action says what to show, and shows it.
private struct PlainSheetPage: View {
    @State private var chosen = "old"
    @State private var showing = false

    var body: some View {
        // Copied, as an argument to a modifier is: nothing below reads the state.
        let said = chosen
        Button("Open") {
            chosen = "new"
            showing = true
        }
        .sheet(isPresented: $showing) { Text(verbatim: "sheet says \(said)") }
    }
}

/// The same shape as a wrapper of TUI's own, with the sheet's content built from a
/// closure held in a view with `@State` of its own, as the file panels' presenter is.
private struct HoldingSheet<Content: View>: View {
    let content: Content
    @Binding var isPresented: Bool
    let words: () -> String
    @State private var own = 0

    var body: some View {
        content.sheet(isPresented: $isPresented) { Text(verbatim: "sheet says \(words())") }
    }
}

private struct HoldingSheetPage: View {
    @State private var chosen = "old"
    @State private var showing = false

    var body: some View {
        let said = chosen
        HoldingSheet(
            content: Button("Open") {
                chosen = "new"
                showing = true
            },
            isPresented: $showing, words: { said })
    }
}

@MainActor
@Suite("A file panel opens with what the app says now")
struct FilePanelRequestFreshnessTests {
    @Test("Its content types are those of the frame that opens it",
          arguments: [Change.inTheAction, .inAnEffect, .aFrameBefore])
    fileprivate func contentTypes(change: Change) {
        // The run loop's own frames: an effect's write walks the frame again.
        let app = HeadlessApp(PageApp({ Page(change: change) }), width: 100, height: 30)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        let shown = app.screen.map(\.stripped).joined(separator: "\n")
        #expect(capless(shown).contains("Format: Markdown"), "\(change): \(shown)")
    }

    /// Nothing here is a file panel's: a sheet's content is built from this
    /// frame's values wherever the closure is held.
    @Test("A sheet shows what the action that opened it chose")
    func plainSheet() {
        let app = HeadlessApp(PageApp({ PlainSheetPage() }), width: 60, height: 20)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 16_666_667)
        let shown = app.screen.map(\.stripped).joined(separator: "\n")
        #expect(shown.contains("sheet says new"), "\(shown)")
    }

    @Test("A sheet whose content comes through a view holding state shows the same")
    func heldSheet() {
        let app = HeadlessApp(PageApp({ HoldingSheetPage() }), width: 60, height: 20)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 16_666_667)
        let shown = app.screen.map(\.stripped).joined(separator: "\n")
        #expect(shown.contains("sheet says new"), "\(shown)")
    }

    /// Once it's up, what the app changes applies the next time it opens.
    @Test("A change once the panel is up applies the next time it opens")
    func aChangeOnceOpenWaits() {
        let model = TypesModel()
        let app = HeadlessApp(PageApp({ ModelPage(model: model) }), width: 100, height: 30)
        app.frame(atNanos: 0)
        model.showing = true
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        model.types = [markdown, .plainText]
        app.frame(atNanos: 50_000_001)
        let shown = app.screen.map(\.stripped).joined(separator: "\n")
        #expect(capless(shown).contains("Format: Text"), "it changed while open: \(shown)")
    }
}
