//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineScrollViewTests.swift
//
//  A bare `OutlineGroup` as a scroll view's content — the shape its own doc
//  example uses — draws its rows, exactly as it does in a `VStack`; and, past
//  the lazy stack's threshold, builds only the rows on screen. Before, the
//  outline had no drawing of its own and the screen was blank.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITesting
@testable import TUITestSupport

/// Counts the rows whose labels were built.
@MainActor
private final class Builds {
    var count = 0
}

/// A node: a name, and its children stored in it.
private struct Node: Identifiable {
    let id: Int
    let name: String
    var children: [Self]?
}

/// Three roots, the first and last of them branches.
private let smallTree: [Node] = [
    Node(id: 1, name: "Sources", children: [
        Node(id: 11, name: "TUI"),
        Node(id: 12, name: "TUICore", children: [Node(id: 121, name: "Rendering")]),
    ]),
    Node(id: 2, name: "README.md"),
    Node(id: 3, name: "Tests", children: [Node(id: 31, name: "Unit")]),
]

/// `count` roots, every tenth a branch of three leaves: closed, `count` rows,
/// past the lazy stack's threshold of 256 from 257.
private func wideTree(count: Int) -> [Node] {
    (0..<count).map { index in
        guard index.isMultiple(of: 10) else { return Node(id: index, name: "r\(index)") }
        let leaves = (1...3).map { Node(id: count + index * 3 + $0, name: "r\(index).\($0)") }
        return Node(id: index, name: "r\(index)", children: leaves)
    }
}

/// Where the twins put the outline.
private enum Shape: CaseIterable {
    /// `ScrollView { OutlineGroup }`: the outline drawn on its own.
    case bare
    /// `ScrollView { VStack { OutlineGroup } }`: a stack lays the rows out.
    case stacked
    /// `ScrollView { LazyVStack { OutlineGroup } }`: a lazy stack does.
    case lazy
}

@MainActor
@Suite("An OutlineGroup in a ScrollView draws its rows")
struct OutlineScrollViewTests {
    /// The outline in `shape`, in a terminal of 30 × 10; drawn `whole`, every
    /// row built, as before it windowed (`drawsContainerRowsWhole`).
    private func app(_ tree: [Node], _ shape: Shape, builds: Builds = Builds(), whole: Bool = false) -> TestApp {
        TestApp(width: 30, height: 10) {
            let outline = OutlineGroup(tree, children: \.children) { node in
                // swiftlint:disable:next redundant_discardable_let
                let _ = MainActor.assumeIsolated { builds.count += 1 }
                Text(verbatim: node.name)
            }
            Group {
                switch shape {
                case .bare: AnyView(ScrollView { outline })
                case .stacked: AnyView(ScrollView { VStack(alignment: .leading, spacing: 0) { outline } })
                case .lazy: AnyView(ScrollView { LazyVStack(alignment: .leading, spacing: 0) { outline } })
                }
            }
            .environment(\.drawsContainerRowsWhole, whole)
        }
    }

    /// Seen failing before the outline drew itself: a blank screen.
    @Test("ScrollView { OutlineGroup } shows the outline's roots")
    func scrollViewShowsTheRoots() {
        let screen = app(smallTree, .bare).screen
        #expect(screen.contains("Sources"), "\(screen)")
        #expect(screen.contains("README.md"), "\(screen)")
        #expect(screen.contains("Tests"), "\(screen)")
    }

    /// Plays the same steps on the bare outline and on `twin`, comparing
    /// the screens after each.
    private func expectTwins(
        _ tree: [Node], _ twin: Shape, steps: [(String, (TestApp) -> Void)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let apps = [app(tree, .bare), app(tree, twin)]
        #expect(apps[0].screen == apps[1].screen, "opened", sourceLocation: sourceLocation)
        for (name, step) in steps {
            let before = apps[0].screen
            apps.forEach(step)
            #expect(
                apps[0].screen == apps[1].screen, "after \(name):\n\(apps[0].screen)\n\(apps[1].screen)",
                sourceLocation: sourceLocation)
            // So the twins cannot agree by both ignoring the keys.
            if Self.disclosingSteps.contains(name) {
                #expect(apps[0].screen != before, "\(name) moved nothing", sourceLocation: sourceLocation)
            }
        }
    }

    /// Tab from the first triangle, which holds the focus at launch, to the
    /// next, open it, scroll, close it, Tab on and open that one.
    private static let disclosingSteps: Set = ["open it", "close it", "open that"]

    private var steps: [(String, (TestApp) -> Void)] {
        [
            ("Tab to the next triangle", { _ = $0.press(.tab) }),
            ("open it", { _ = $0.press(.right) }),
            ("wheel down 3", { $0.scroll(.down, by: 3) }),
            ("wheel down 3 more", { $0.scroll(.down, by: 3) }),
            ("wheel up 6", { $0.scroll(.up, by: 6) }),
            ("close it", { _ = $0.press(.left) }),
            ("focus the next triangle", { _ = $0.press(.tab) }),
            ("open that", { _ = $0.press(.right) }),
            ("page down", { _ = $0.press(.pageDown) }),
        ]
    }

    @Test(
        "the bare outline draws as a stack of it does, drawn whole and windowed",
        arguments: [smallTree, wideTree(count: 40), wideTree(count: 600)])
    fileprivate func bareMatchesStacked(_ tree: [Node]) {
        expectTwins(tree, .stacked, steps: steps)
    }

    @Test("a lazy stack of an outline draws as an eager one does", arguments: [smallTree, wideTree(count: 600)])
    fileprivate func lazyMatchesStacked(_ tree: [Node]) {
        let apps = [app(tree, .lazy), app(tree, .stacked)]
        #expect(apps[0].screen == apps[1].screen, "opened")
        for (name, step) in steps {
            apps.forEach(step)
            #expect(apps[0].screen == apps[1].screen, "after \(name):\n\(apps[0].screen)\n\(apps[1].screen)")
        }
    }

    /// The labels built on the first frame and by each step after it: Tab to
    /// the second triangle, Right to open it, two wheels of five and two page
    /// downs.
    private func builtPerStep(_ shape: Shape, roots: Int, whole: Bool = false) -> [Int] {
        let builds = Builds()
        let app = app(wideTree(count: roots), shape, builds: builds, whole: whole)
        _ = app.screen
        var counts = [builds.count]
        let steps: [(TestApp) -> Void] = [
            { _ = $0.press(.tab) }, { _ = $0.press(.right) },
            { $0.scroll(.down, by: 5) }, { $0.scroll(.down, by: 5) },
            { _ = $0.press(.pageDown) }, { _ = $0.press(.pageDown) },
        ]
        for step in steps {
            builds.count = 0
            step(app)
            counts.append(builds.count)
        }
        #expect(!app.screen.contains("r0 "), "scrolled off the top: \(app.screen)")
        return counts
    }

    /// Drawn whole, a step builds every root (``drawnWholeBuildsEveryRow()``).
    /// Windowed, a step builds the rows it draws, the same however many roots;
    /// a first frame a screenful and the measure ladder's samples, 135 and 183
    /// labels here: past 4,096 lines the ladder likely takes another rung, whose
    /// sample an outline's rows, not memoised, build again (PERFCASE-F14).
    @Test("a large outline in a ScrollView builds only the rows it shows", arguments: [Shape.bare, Shape.lazy])
    fileprivate func buildsOnlyWhatShows(_ shape: Shape) {
        let thousand = builtPerStep(shape, roots: 1_000)
        let tenThousand = builtPerStep(shape, roots: 10_000)
        #expect(thousand.dropFirst() == tenThousand.dropFirst(), "\(shape): \(thousand) \(tenThousand)")
        #expect(tenThousand.dropFirst().allSatisfy { $0 < 150 }, "\(shape): \(tenThousand)")
        #expect(tenThousand[0] < 250, "\(shape): \(tenThousand)")
    }

    /// What the windowing saves, and what makes the test above able to fail:
    /// the same outline drawn whole builds every root's label each step.
    @Test("drawn whole, the same outline builds every row each step")
    func drawnWholeBuildsEveryRow() {
        let counts = builtPerStep(.bare, roots: 1_000, whole: true)
        #expect(counts.allSatisfy { $0 >= 1_000 }, "\(counts)")
    }

    // MARK: - Modifiers and the environment reach the rows (CLAUDE.md)

    /// One frame of `view`, its lines with their SGR, as
    /// `ListAttributeCascadeTests` draws one.
    private func drawn(_ view: some View) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let context = RenderContext(availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines
    }

    @Test(".foregroundStyle() on a bare outline reaches its rows' text")
    func foregroundStyleReachesTheRows() {
        let outline = OutlineGroup(smallTree, children: \.children) { Text(verbatim: $0.name) }
        let red = drawn(ScrollView { outline.foregroundStyle(.red) })
        let plain = drawn(ScrollView { outline })
        let wanted = sgrState(of: "x", in: drawn(Text(verbatim: "x").foregroundStyle(.red)))?.foregroundColour
        #expect(wanted != nil)
        for word in ["Sources", "README.md", "Tests"] {
            #expect(sgrState(of: word, in: red)?.foregroundColour == wanted, "\(word): \(red)")
            #expect(sgrState(of: word, in: plain)?.foregroundColour != wanted, "\(word): \(plain)")
        }
    }

    @Test(".disabled() on a bare outline disables its rows, from the keyboard and the mouse")
    func disabledReachesTheRows() throws {
        for disabled in [false, true] {
            let app = TestApp(width: 30, height: 8) {
                ScrollView {
                    OutlineGroup(smallTree, children: \.children) { Text(verbatim: $0.name) }
                        .disabled(disabled)
                }
            }
            // Enabled, the first triangle holds the focus at launch.
            #expect((app.focusedID != nil) == !disabled, "disabled \(disabled): \(app.focusedID ?? "no focus")")
            _ = app.press(.right)
            #expect(app.screen.contains("TUICore") == !disabled, "disabled \(disabled), Right:\n\(app.screen)")
            try app.click("Tests")
            #expect(app.screen.contains("Unit") == !disabled, "disabled \(disabled), a click:\n\(app.screen)")
        }
    }

    @Test("an outline in a List still makes each node a row")
    func listIsUnaffected() {
        let app = TestApp(width: 30, height: 10) {
            List { OutlineGroup(smallTree, children: \.children) { Text(verbatim: $0.name) } }
        }
        #expect(app.screen.contains("Sources"), "\(app.screen)")
        #expect(app.screen.contains("README.md"), "\(app.screen)")
        _ = app.press(.tab)
        _ = app.press(.right)
        #expect(app.screen.contains("TUICore"), "\(app.screen)")
    }
}
