//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollAnchorAlignmentTests.swift
//
//  `ScrollAnchorRole.alignment`: where content SHORTER than a scroll view sits
//  in it — and the unlabelled `.defaultScrollAnchor(.bottom)`, which states it
//  too, as SwiftUI's does (measured on macOS 15: three rows sit at the bottom
//  of the view).
//
//  The two spellings the owner asked to have side by side are both here:
//  the chat (`.defaultScrollAnchor(.bottom)`: starts at the bottom, grows
//  upwards, follows the tail) and the log (`.bottom` for `.initialOffset` and
//  for `.sizeChanges`: starts at the top, grows downwards, follows the tail
//  once it fills the view).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("ScrollAnchorRole.alignment")
struct ScrollAnchorAlignmentTests {

    private static let viewport = 8

    @MainActor
    private final class Frames {
        let tui = TUIContext()
        let focusManager = FocusManager()

        func render<V: View>(_ view: V, width: Int = 30, height: Int = ScrollAnchorAlignmentTests.viewport)
            -> FrameBuffer
        {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer
        }

        /// The row number drawn on each line of the frame, `nil` for a line
        /// with none.
        func rows<V: View>(_ view: V) -> [Int?] {
            render(view).lines.map { line in
                let text = line.stripped
                guard let marker = text.range(of: "row ") else { return nil }
                return Int(text[marker.upperBound...].prefix { $0.isNumber })
            }
        }
    }

    private func log(_ count: Int, lazy: Bool = true) -> AnyView {
        let rows = ForEach(0..<count, id: \.self) { Text("row \($0)") }
        let content: AnyView =
            lazy
            ? AnyView(LazyVStack(alignment: .leading, spacing: 0) { rows })
            : AnyView(VStack(alignment: .leading, spacing: 0) { rows })
        return AnyView(ScrollView { content }.frame(height: Self.viewport))
    }

    // MARK: - Placement

    @Test("The unlabelled .bottom draws short content at the bottom", arguments: [true, false])
    func unlabelledBottomSitsAtTheBottom(lazy: Bool) {
        let frames = Frames()
        let drawn = frames.rows(log(3, lazy: lazy).defaultScrollAnchor(.bottom))
        #expect(drawn == [nil, nil, nil, nil, nil, 0, 1, 2], "\(drawn)")
    }

    @Test("No anchor, and .bottom for the other two roles, keep short content at the top")
    func otherRolesLeaveItAtTheTop() {
        let frames = Frames()
        #expect(frames.rows(log(3)) == [0, 1, 2, nil, nil, nil, nil, nil])
        let logLike = log(3)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
        #expect(Frames().rows(logLike) == [0, 1, 2, nil, nil, nil, nil, nil])
    }

    @Test("The alignment role alone places the content, and its y is not quantised")
    func alignmentRoleAlone() {
        // Five lines of room: .center is 2.5, rounded down; 0.6 is 3.
        #expect(
            Frames().rows(log(3).defaultScrollAnchor(.center, for: .alignment))
                == [nil, nil, 0, 1, 2, nil, nil, nil])
        #expect(
            Frames().rows(log(3).defaultScrollAnchor(UnitPoint(x: 0, y: 0.6), for: .alignment))
                == [nil, nil, nil, 0, 1, 2, nil, nil])
        #expect(
            Frames().rows(log(3).defaultScrollAnchor(.bottom, for: .alignment))
                == [nil, nil, nil, nil, nil, 0, 1, 2])
    }

    @Test("Content that fills the view is not moved")
    func fillingContentIsUnmoved() {
        let frames = Frames()
        let view = log(8).defaultScrollAnchor(.bottom)
        #expect(frames.rows(view) == Array(0..<8))
    }

    // MARK: - Precedence, as SwiftUI's

    /// SwiftUI's own example: the unlabelled anchor for everything, and the
    /// alignment role opted back out of it. Measured on macOS 15: the role wins
    /// whichever of the two is written nearer the view.
    @Test("A role's anchor wins over the unlabelled one in either order", arguments: [false, true])
    func roleWinsEitherOrder(roleOutside: Bool) {
        let view =
            roleOutside
            ? AnyView(log(3).defaultScrollAnchor(.bottom).defaultScrollAnchor(.top, for: .alignment))
            : AnyView(log(3).defaultScrollAnchor(.top, for: .alignment).defaultScrollAnchor(.bottom))
        #expect(Frames().rows(view) == [0, 1, 2, nil, nil, nil, nil, nil])
    }

    /// Measured: `nil` for a role states nothing, so the unlabelled anchor
    /// still applies to it.
    @Test("A nil role defers to the unlabelled anchor", arguments: [false, true])
    func nilRoleDefers(roleOutside: Bool) {
        let view =
            roleOutside
            ? AnyView(log(3).defaultScrollAnchor(.bottom).defaultScrollAnchor(nil, for: .alignment))
            : AnyView(log(3).defaultScrollAnchor(nil, for: .alignment).defaultScrollAnchor(.bottom))
        #expect(Frames().rows(view) == [nil, nil, nil, nil, nil, 0, 1, 2])
    }

    // MARK: - Growth: the chat and the log, side by side

    /// Renders `count` rows for a few frames each, growing from 3 to 12, and
    /// returns the last frame at each size.
    private func grow(_ configure: (AnyView) -> AnyView) -> [[Int?]] {
        let frames = Frames()
        var out: [[Int?]] = []
        for count in [3, 6, 9, 12] {
            var last: [Int?] = []
            for _ in 0..<2 { last = frames.rows(configure(log(count))) }
            out.append(last)
        }
        return out
    }

    @Test("The chat: starts at the bottom, grows upwards, then follows the tail")
    func chatGrowsUpwards() {
        let seen = grow { AnyView($0.defaultScrollAnchor(.bottom)) }
        #expect(seen[0] == [nil, nil, nil, nil, nil, 0, 1, 2], "3 rows: \(seen[0])")
        #expect(seen[1] == [nil, nil, 0, 1, 2, 3, 4, 5], "6 rows: \(seen[1])")
        #expect(seen[2].last == 8, "9 rows, the tail on the last line: \(seen[2])")
        #expect(seen[3].last == 11, "12 rows, still following: \(seen[3])")
    }

    @Test("The log: starts at the top, grows downwards, then follows the tail")
    func logGrowsDownwards() {
        let seen = grow {
            AnyView(
                $0.defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges))
        }
        #expect(seen[0] == [0, 1, 2, nil, nil, nil, nil, nil], "3 rows: \(seen[0])")
        #expect(seen[1] == [0, 1, 2, 3, 4, 5, nil, nil], "6 rows: \(seen[1])")
        #expect(seen[2].last == 8, "9 rows, the tail on the last line: \(seen[2])")
        #expect(seen[3].last == 11, "12 rows, still following: \(seen[3])")
    }

    // MARK: - What moves with the lines

    @Test("A control in aligned content is clickable where it is drawn")
    func hitRegionsMoveWithTheContent() {
        let frames = Frames()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("row 0")
                Button("press") {}
            }
        }
        .frame(height: Self.viewport)
        .defaultScrollAnchor(.bottom)
        let buffer = frames.render(view)
        let line = buffer.lines.firstIndex { $0.stripped.contains("press") }
        #expect(line == Self.viewport - 1, "drawn on the last line: \(buffer.lines.map(\.stripped))")
        // The button's own region, not the viewport's (which spans every line).
        let regions = buffer.hitTestRegions.filter { $0.height == 1 }
        #expect(regions.contains { $0.offsetY == Self.viewport - 1 }, "\(buffer.hitTestRegions)")
        #expect(!regions.contains { $0.offsetY == 1 }, "nothing left where it would be unaligned")
    }

    @Test("The geometry reports the room above as a top inset, as SwiftUI's does")
    func geometryReportsAnInset() {
        let frames = Frames()
        var reported: ScrollGeometry?
        let view = log(3)
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { reported = $1 })
        _ = frames.render(view)
        #expect(reported?.contentInsets.top == 5)
        #expect(reported?.contentOffset.y == -5)
        #expect(reported?.contentSize.height == 3)
        // The room is inset but does not come off the container, so the
        // visible rect is taller than the view by it: SwiftUI's numbers,
        // measured on macOS 15 (three 20-point rows at the bottom of a
        // 300-point view: container 300, visibleRect 540 from -240, bounds 300
        // from -240).
        #expect(reported?.containerSize.height == Self.viewport)
        #expect(reported?.visibleRect.y == -5 && reported?.visibleRect.height == Self.viewport + 5)
        #expect(reported?.bounds.y == -5 && reported?.bounds.height == Self.viewport)
    }

    // MARK: - List and Table ignore it, as macOS's do

    @Test("A List keeps short content at the top under the unlabelled .bottom")
    func listIgnoresTheRole() {
        let frames = Frames()
        let view = List(0..<3, id: \.self) { Text("row \($0)") }
            .frame(height: Self.viewport)
            .defaultScrollAnchor(.bottom)
        let drawn = frames.rows(view)
        #expect(drawn.compactMap { $0 } == [0, 1, 2])
        #expect(drawn.firstIndex(of: 0) ?? 99 <= 1, "the first row at the top: \(drawn)")
    }
}
