//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlinePassTests.swift
//
//  A table whose tree is row content (`DisclosureTableRow`, a `ForEach` of
//  rows) flattens it once a pass at its place, and the pass's measures and
//  its draw share that outline (`RenderCache.composedOncePerPass`): each used
//  to list every open row again, and a table in a stack is measured before it
//  is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITables
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A table's outline of row content, once a pass")
struct TableOutlinePassTests {
    private struct Item: Identifiable {
        let id: String
    }

    /// Whether the folder shows its rows: the app's, as tuitree's is.
    @MainActor
    private final class Open {
        var isOpen = true
        var binding: Binding<Bool> {
            Binding(get: { self.isOpen }, set: { self.isOpen = $0 })
        }
    }

    /// The render loop's shape: an isolated cache, state storage, and the
    /// volatile-read tracker whose presence turns the pass's memos on.
    private func memoisedContext() -> RenderContext {
        var context = makeRenderContext(width: 40, height: 12)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        return context
    }

    private func table(_ open: Open, folder: String = "Folder", files: [String] = ["a", "b", "c"]) -> some View {
        Table(of: Item.self) {
            TableColumn("Name", value: \Item.id)
        } rows: {
            DisclosureTableRow(Item(id: folder), isExpanded: open.binding) {
                ForEach(files.map(Item.init)) { TableRow($0) }
            }
        }
    }

    @Test("Measured and drawn in one pass, the outline is listed once")
    func measureAndDrawShareOneOutline() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let open = Open()
        let view = table(open)
        _ = measureChild(view, proposal: ProposedViewSize(width: 40, height: nil), context: context)
        _ = measureChild(view, proposal: ProposedViewSize(width: 30, height: 8), context: context)
        let drawn = renderToBuffer(view, context: context)

        #expect(cache.rowWork.listed == 4, "the folder and its three rows, once for the pass")
        #expect(drawn.lines.contains { $0.stripped.contains("c") })

        // The same picture as a table drawn with nothing kept.
        let fresh = renderToBuffer(table(Open()), context: makeRenderContext(width: 40, height: 12))
        #expect(drawn.lines.map(\.stripped) == fresh.lines.map(\.stripped))
    }

    /// A page of the app's own whose body makes the table, as a page's does.
    private struct Page: View {
        let open: Open
        var body: some View {
            Table(of: Item.self) {
                TableColumn("Name", value: \Item.id)
            } rows: {
                DisclosureTableRow(Item(id: "Folder"), isExpanded: open.binding) {
                    ForEach(["a", "b", "c"].map(Item.init)) { TableRow($0) }
                }
            }
        }
    }

    @Test("Under a title in a stack, which measures it before it draws it, the outline is listed once a pass")
    func inAStack() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let page = VStack(alignment: .leading, spacing: 0) {
            Text("title")
            Page(open: Open())
        }
        let drawn = renderToBuffer(page, context: context)
        #expect(drawn.lines.contains { $0.stripped.contains("c") })
        #expect(cache.rowWork.listed == 4, "the folder and its three rows, once for the pass")
        cache.beginRenderPass()
        _ = renderToBuffer(page, context: context)
        #expect(cache.rowWork.listed == 8, "and once for the next")
    }

    @Test("A branch closed between passes is flattened again, and shows closed")
    func aChangeBetweenPassesRebuilds() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let open = Open()
        let view = table(open)
        let before = renderToBuffer(view, context: context)
        #expect(before.lines.contains { $0.stripped.contains("b") })

        open.isOpen = false
        cache.beginRenderPass()
        _ = measureChild(view, proposal: ProposedViewSize(width: 40, height: nil), context: context)
        let after = renderToBuffer(view, context: context)
        #expect(!after.lines.contains { $0.stripped.contains(" b") }, "the folder's rows are gone")
        #expect(cache.rowWork.listed == 4 + 1, "four rows, then the folder alone")
    }

    /// Kept under the tree's first level (`_TableOutlineSource`): other rows
    /// there, in the same pass at the same place, are other rows beneath.
    @Test("Other rows at the same place in the same pass are flattened again")
    func anotherValueRebuilds() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let open = Open()
        _ = renderToBuffer(table(open), context: context)
        let other = renderToBuffer(table(open, folder: "Other", files: ["x", "y"]), context: context)

        #expect(other.lines.contains { $0.stripped.contains("y") })
        #expect(!other.lines.contains { $0.stripped.contains(" c") })
        #expect(cache.rowWork.listed == 4 + 3)
    }
}
