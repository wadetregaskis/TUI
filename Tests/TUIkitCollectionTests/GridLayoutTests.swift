//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridLayoutTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

// MARK: - Fixtures

/// The identity each probe rendered at, by name.
@MainActor
private final class IdentityLog {
    var paths: [String: Set<String>] = [:]
}

/// Draws its name, and records the identity it drew at.
private struct Probe: View, Renderable {
    let name: String
    let log: IdentityLog

    var body: Never { fatalError("Probe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        log.paths[name, default: []].insert(context.identity.path)
        return FrameBuffer(text: name)
    }
}

// MARK: - Suite

/// `GridLayout`: a `Grid` that is a `Layout`, so it can be switched with another
/// through `AnyLayout` while its cells keep their identity.
@MainActor
@Suite("GridLayout")
struct GridLayoutTests {

    private func lines(_ view: some View, width: Int = 60, height: Int = 12) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    @Test("It draws what a Grid draws, spans and full-width children included")
    func drawsLikeAGrid() {
        let grid = lines(
            Grid(alignment: .leading) {
                GridRow { Text("a"); Text("bb"); Text("c") }
                Divider()
                GridRow { Text("aaaaaaa"); Text("b").gridCellColumns(2) }
                GridRow(alignment: .bottom) { Text("x"); Text("y").gridColumnAlignment(.trailing) }
            })
        let layout = lines(
            GridLayout(alignment: .leading) {
                GridRow { Text("a"); Text("bb"); Text("c") }
                Divider()
                GridRow { Text("aaaaaaa"); Text("b").gridCellColumns(2) }
                GridRow(alignment: .bottom) { Text("x"); Text("y").gridColumnAlignment(.trailing) }
            })
        #expect(layout == grid)
        #expect(layout[1].allSatisfy { $0 == "─" || $0 == " " } && layout[1].contains("─"))
    }

    @Test("Its spacings default to the grid's, and take what they are given")
    func spacings() {
        #expect(
            lines(GridLayout(alignment: .leading) { GridRow { Text("ab"); Text("cd") } })[0]
                .hasPrefix("ab cd"))
        #expect(
            lines(
                GridLayout(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 1) {
                    GridRow { Text("ab"); Text("cd") }
                    GridRow { Text("e"); Text("f") }
                }
            ).map { $0.trimmingCharacters(in: .whitespaces) } == ["ab   cd", "", "e    f"])
        #expect(GridLayout().horizontalSpacing == nil)
        #expect(
            lines(Grid(alignment: .leading, horizontalSpacing: nil) { GridRow { Text("ab"); Text("cd") } })[0]
                .hasPrefix("ab cd"))
    }

    @Test("Switched with a stack layout, a cell keeps its identity")
    func switchingKeepsCells() {
        // The reason `GridLayout` exists: the two branches of a switch keep one
        // identity, so the cells keep their `@State`. A looped row is cells
        // under both layouts, so every cell draws at the same identity either
        // way.
        let log = IdentityLog()
        for useGrid in [true, false] {
            let layout = useGrid ? AnyLayout(GridLayout()) : AnyLayout(VStackLayout())
            _ = lines(
                layout {
                    ForEach(0..<2) { row in
                        GridRow {
                            Probe(name: "\(row)a", log: log)
                            Probe(name: "\(row)b", log: log)
                        }
                    }
                })
        }
        for name in ["0a", "0b", "1a", "1b"] {
            #expect(log.paths[name]?.count == 1, "\(name) drew at \(log.paths[name] ?? [])")
        }
        let paths = Set(log.paths.values.flatMap { $0 })
        #expect(paths.count == 4)
    }

    @Test("Under the stack layout the same cells stack")
    func cellsStackUnderAStack() {
        let rendered = lines(
            AnyLayout(VStackLayout()) {
                GridRow { Text("a"); Text("b") }
                GridRow { Text("c"); Text("d") }
            })
        #expect(rendered.map { $0.trimmingCharacters(in: .whitespaces) } == ["a", "b", "c", "d"])
    }
}
