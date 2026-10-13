//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutPriorityTests.swift
//
//  The built-in stacks give space by `layoutPriority(_:)`, as SwiftUI's do
//  (deviation L12, fixed by the owner's ruling of 2026-10-13: "we should
//  support layout priority properly"). Each case is one SwiftUI measured on
//  macOS 15.8 (`Tools/SwiftUIProbes/Layout priority/priority.out`), a
//  character of its monospaced font standing for a cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("Layout priority in the built-in stacks")
struct LayoutPriorityTests {
    private let tenA = "aaaaaaaaaa"
    private let tenB = "bbbbbbbbbb"

    private func lines<V: View>(_ view: V, width: Int, height: Int = 3) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
    }

    private func row<V: View>(width: Int, @ViewBuilder _ content: () -> V) -> String {
        lines(HStack(spacing: 0) { content() }, width: width).first ?? ""
    }

    @Test("A child with priority keeps its width and its sibling truncates (SwiftUI: b-priority, a-priority)")
    func priorityKeepsItsWidth() {
        let second = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1)
        }
        #expect(second.hasSuffix(tenB), "\(second)")
        #expect(!second.contains(tenA), "\(second)")
        let first = row(width: 12) {
            Text(tenA).lineLimit(1).layoutPriority(1)
            Text(tenB).lineLimit(1)
        }
        #expect(first.hasPrefix(tenA), "\(first)")
        #expect(!first.contains(tenB), "\(first)")
    }

    @Test("Higher priorities are offered space first, each leaving the lower their minimums (SwiftUI: three-levels)")
    func threeLevels() {
        let drawn = row(width: 15) {
            Text(tenA).lineLimit(1).layoutPriority(2)
            Text(tenB).lineLimit(1)
            Text("cccccccccc").lineLimit(1).layoutPriority(1)
        }
        // SwiftUI: a 10, b 1, c 4.
        #expect(drawn.hasPrefix(tenA), "\(drawn)")
        #expect(drawn.contains("ccc"), "\(drawn)")
        #expect(!drawn.contains("bb"), "\(drawn)")
    }

    @Test("A negative priority gives way to the default (SwiftUI: negative)")
    func negative() {
        let drawn = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(-1)
        }
        #expect(drawn.hasPrefix(tenA), "\(drawn)")
        // The mirror, which a row that ignored priorities would get wrong: it
        // keeps the leading child whole.
        let mirrored = row(width: 12) {
            Text(tenA).lineLimit(1).layoutPriority(-1)
            Text(tenB).lineLimit(1)
        }
        #expect(mirrored.hasSuffix(tenB), "\(mirrored)")
        #expect(!mirrored.contains(tenA), "\(mirrored)")
    }

    @Test("A priority survives a modifier that keeps the layout (SwiftUI: after-foreground … after-tag, in-group)")
    func throughModifiers() {
        let styled = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).foregroundStyle(.red)
        }
        #expect(styled.hasSuffix(tenB), "kept through foregroundStyle: \(styled)")
        let font = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).font(.headline)
        }
        #expect(font.hasSuffix(tenB), "kept through font: \(font)")
        let faded = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).opacity(0.9)
        }
        #expect(faded.hasSuffix(tenB), "kept through opacity: \(faded)")
        let filled = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).background(Color.yellow)
        }
        #expect(filled.hasSuffix(tenB), "kept through background: \(filled)")
        let identified = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).id(1)
        }
        #expect(identified.hasSuffix(tenB), "kept through id: \(identified)")
        let tagged = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).tag(1)
        }
        #expect(tagged.hasSuffix(tenB), "kept through tag: \(tagged)")
        let grouped = row(width: 12) {
            Text(tenA).lineLimit(1)
            Group { Text(tenB).lineLimit(1).layoutPriority(1) }
        }
        #expect(grouped.hasSuffix(tenB), "kept inside a Group: \(grouped)")
        let outside = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).padding(0).layoutPriority(1)
        }
        #expect(outside.hasSuffix(tenB), "written after padding: \(outside)")
    }

    @Test("A priority is lost under a modifier that lays the view out anew (SwiftUI: modifier-after, after-frame)")
    func lostUnderLayoutModifiers() {
        let padded = row(width: 12) {
            Text(tenA).lineLimit(1)
            Text(tenB).lineLimit(1).layoutPriority(1).padding(0)
        }
        #expect(padded.hasPrefix(tenA), "lost under padding: \(padded)")
        // A frame makes the child flexible, which a row draws the same with or
        // without the priority, so the read itself is what shows it lost.
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(1).frame(minWidth: 0))) == 0)
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(1).padding(0))) == 0)
    }

    @Test("A child's priority is read through the modifiers that keep it")
    func priorityRead() {
        #expect(layoutPriority(of: ChildView(Text(tenB))) == 0)
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(2))) == 2)
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(2).foregroundStyle(.red))) == 2)
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(2).background(Color.yellow))) == 2)
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(2).id(1))) == 2)
        #expect(layoutPriority(of: ChildView(Text(tenB).layoutPriority(2).opacity(0.9))) == 2)
    }

    @Test("A flexible child with priority leaves its sibling only its minimum (SwiftUI: flex-priority-vs-text)")
    func flexibleWithPriority() {
        let drawn = row(width: 40) {
            Text(tenA).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            Text(tenB).lineLimit(1)
        }
        #expect(!drawn.contains("bb"), "\(drawn)")
        let without = row(width: 40) {
            Text(tenA).frame(maxWidth: .infinity, alignment: .leading)
            Text(tenB).lineLimit(1)
        }
        #expect(without.hasSuffix(tenB), "without a priority the text keeps its width: \(without)")
    }

    /// The column's distribution is the row's, along the other axis. A column
    /// of multi-line `Text`s is no test of it: a `Text` measures at its full
    /// height when offered none, so it has nothing to give — and SwiftUI's
    /// column of two `Text`s came out the same with and without a priority
    /// too (v-priority, v-equal).
    @Test("The distribution offers the higher priority its length first, the lower keeping their minimums")
    func distributionByPriority() {
        // Two fixed children of 3 in 4: leading first without priorities…
        #expect(distributeLinearSpace(naturalSizes: [3, 3], isFlexible: [false, false], available: 4) == [3, 1])
        // …and the second first with one, the first keeping its minimum of 1.
        #expect(
            distributeLinearSpace(
                naturalSizes: [3, 3], isFlexible: [false, false], available: 4,
                priorities: [0, 1], minimumSizes: [1, 1]) == [1, 3])
        // Three levels, as SwiftUI's three-levels case: 10, 1, 4 in 15.
        #expect(
            distributeLinearSpace(
                naturalSizes: [10, 10, 10], isFlexible: [false, false, false], available: 15,
                priorities: [2, 0, 1], minimumSizes: [1, 1, 1]) == [10, 1, 4])
        // Gaps are charged between the children that occupy the axis.
        #expect(
            distributeLinearSpace(
                naturalSizes: [3, 3], isFlexible: [false, false], available: 5, spacing: 1,
                priorities: [0, 1], minimumSizes: [1, 1]) == [1, 3])
    }

    @Test("HStackLayout gives space by priority as HStack does")
    func stackLayout() {
        let drawn =
            lines(
                HStackLayout(spacing: 0) {
                    Text(tenA).lineLimit(1)
                    Text(tenB).lineLimit(1).layoutPriority(1)
                }, width: 12
            ).first ?? ""
        #expect(drawn.hasSuffix(tenB), "\(drawn)")
    }

    @Test("Without priorities nothing changes, and no minimum is measured")
    func noPrioritiesNoChange() {
        let children = [ChildView]()
        #expect(layoutPriorities(of: children) == nil)
        #expect(distributeLinearSpace(naturalSizes: [10, 10], isFlexible: [false, false], available: 12) == [10, 2])
    }
}
