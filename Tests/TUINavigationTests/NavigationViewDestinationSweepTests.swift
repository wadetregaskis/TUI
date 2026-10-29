//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationViewDestinationSweepTests.swift
//
//  A `NavigationLink(destination:)` registers its view with the stack's
//  coordinator every pass it renders. Nothing ever took one out, so every link
//  that ever drew stayed registered for the stack's life, holding its
//  destination view: a list of links over changing data grew by a view per
//  row it ever showed. The coordinator now sweeps the ones a pass did not
//  register, keeping those on the path, which a buried screen's link cannot
//  register again while it is buried.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUINavigation
@testable import TUITestSupport

/// Where a probe in the stack's root leaves the stack's coordinator.
private final class CoordinatorBox {
    var coordinator: NavigationCoordinator?
}

/// Reads the coordinator the enclosing stack put in the environment.
private struct CoordinatorProbe: View {
    let box: CoordinatorBox
    @Environment(\.navigationCoordinator) private var coordinator

    var body: some View {
        let _ = box.coordinator = coordinator  // swiftlint:disable:this redundant_discardable_let
        EmptyView()
    }
}

/// An `.equatable()` boundary, equal by label alone, so the memo always wants
/// to serve what it holds.
private struct Memoized<Content: View>: View, @MainActor Equatable {
    let label: String
    let build: @MainActor () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.label == rhs.label }

    var body: some View {
        build()
    }
}

@MainActor
@Suite("Navigation view destinations are swept")
struct NavigationViewDestinationSweepTests {

    /// One pass of the run loop's bracketing, render cache included.
    private func frame(_ view: some View, tui: TUIContext, focusManager: FocusManager) -> [String] {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.focusManager = focusManager
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, identity: ViewIdentity(path: "Root"))
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return lines
    }

    @Test("Links over changing data leave no destinations behind")
    func churningLinksStayBounded() throws {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let box = CoordinatorBox()
        for round in 0..<200 {
            let ids = [round * 2, round * 2 + 1]
            _ = frame(
                NavigationStack {
                    VStack(spacing: 0) {
                        ForEach(ids, id: \.self) { id in
                            NavigationLink("row \(id)") { Text("detail \(id)") }
                        }
                        CoordinatorProbe(box: box)
                    }
                }, tui: tui, focusManager: focusManager)
        }
        let coordinator = try #require(box.coordinator)
        #expect(coordinator.viewDestinationCount == 2, "kept \(coordinator.viewDestinationCount) of 400 links")
    }

    @Test("A link a memo serves keeps its destination, and pushes it")
    func memoServedLinkStillPushes() throws {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let box = CoordinatorBox()
        let view = NavigationStack {
            VStack(spacing: 0) {
                Memoized(label: "links") {
                    NavigationLink("Go") { Text("the detail") }
                }.equatable()
                CoordinatorProbe(box: box)
            }
        }
        // Past a sweep interval, with the link served from the memo.
        for _ in 0..<(Int(NavigationCoordinator.sweepInterval) + 6) {
            _ = frame(view, tui: tui, focusManager: focusManager)
        }
        #expect(tui.renderCache.stats.hits > 0, "the memo never served, so this tests nothing")
        let coordinator = try #require(box.coordinator)
        #expect(coordinator.viewDestinationCount == 1, "the served link's destination was swept")

        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .enter)), "Return on the link")
        let pushed = frame(view, tui: tui, focusManager: focusManager)
        #expect(pushed.contains { $0.contains("the detail") }, "the push showed: \(pushed)")
    }

    @Test("A sweep keeps the destinations on the path")
    func pathKeepsItsDestinations() {
        let coordinator = NavigationCoordinator()
        let root = NavigationViewToken(id: "root-link")
        let buried = NavigationViewToken(id: "screen-a-link")
        let left = NavigationViewToken(id: "left-link")
        coordinator.read = { [AnyHashable(root), AnyHashable(buried)] }

        coordinator.beginRegistrationPass()
        for token in [root, buried, left] {
            coordinator.register(viewDestination: AnyView(Text(token.id)), forToken: token.id)
        }
        coordinator.endRegistrationPass()
        // Screen B is on top: the root renders and registers its link again;
        // screen A, under B, renders nothing, and the link that left is gone.
        for _ in 0..<(2 * Int(NavigationCoordinator.sweepInterval)) {
            coordinator.beginRegistrationPass()
            coordinator.register(viewDestination: AnyView(Text(root.id)), forToken: root.id)
            coordinator.endRegistrationPass()
        }

        #expect(coordinator.destination(for: AnyHashable(buried)) != nil, "popping back to B needs A's link")
        #expect(coordinator.destination(for: AnyHashable(left)) == nil, "the link that left kept its view")
        #expect(coordinator.viewDestinationCount == 2)
    }
}
