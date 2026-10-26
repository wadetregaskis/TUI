//  🖥️ TUI — A Terminal UI framework for Swift
//  GlassEffectContainerTests.swift
//
//  `GlassEffectContainer` and `glassEffectUnion(id:namespace:)`: glass that
//  touches, comes closer than the container's spacing, or shares a union is
//  drawn as one shape.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Glass effect containers")
struct GlassEffectContainerTests {

    /// `count` whole passes of `view`, each through `tui`'s own state and
    /// render cache — the container keeps who it joined between passes — as
    /// the screen shows them, styling stripped.
    private func frames(
        _ view: some View, count: Int = 2, width: Int, height: Int = 1, tui: TUIContext = TUIContext()
    ) -> [[String]] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = SystemPalette.green
        let context = RenderContext(availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        return (0..<count).map { _ in
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = renderToScreen(view, context: context)
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            return buffer.lines.map(\.stripped)
        }
    }

    private func pair(spacing: Int) -> some View {
        HStack(spacing: spacing) {
            Text("A").padding(.horizontal).glassEffect()
            Text("B").padding(.horizontal).glassEffect()
        }
    }

    @Test("Without a container, glass that touches is two shapes")
    func noContainer() {
        #expect(frames(pair(spacing: 0), width: 6).last == ["(A)(B)"])
    }

    @Test("In a container, glass that touches is drawn as one shape from the first pass")
    func touchingJoins() {
        let drawn = frames(GlassEffectContainer { pair(spacing: 0) }, width: 6)
        #expect(drawn[0] == ["(A  B)"])
        #expect(drawn[1] == ["(A  B)"])
    }

    @Test("Each member's part of a joined shape meets the next: one rim round both, rows and all")
    func partsMeet() {
        let view = GlassEffectContainer {
            HStack(spacing: 0) {
                Text("A").padding().glassEffect()
                Text("B").padding().glassEffect()
            }
        }
        #expect(frames(view, width: 6, height: 3).last == ["╭────╮", "│A  B│", "╰────╯"])
    }

    @Test("The pass a group forms is drawn as every pass after it: one glass, not the members' own under it")
    func formingPassIsTheGroup() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        let tui = TUIContext()
        let context = RenderContext(availableWidth: 6, availableHeight: 1, environment: environment, tuiContext: tui)
        let passes = (0..<2).map { _ in
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let lines = ColorDepth.withCurrent(.truecolor) {
                renderToScreen(GlassEffectContainer { pair(spacing: 0) }, context: context).lines
            }
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            return lines
        }
        #expect(passes[0] == passes[1])
    }

    @Test("Glass the container's spacing apart stays apart; closer, it joins")
    func spacing() {
        #expect(frames(GlassEffectContainer { pair(spacing: 1) }, width: 7).last == ["(A) (B)"])
        #expect(frames(GlassEffectContainer(spacing: 1) { pair(spacing: 1) }, width: 7).last == ["(A) (B)"])
        #expect(frames(GlassEffectContainer(spacing: 2) { pair(spacing: 1) }, width: 7).last == ["(A   B)"])
    }

    @Test("Glass of two kinds stays apart, touching or not")
    func kindsStayApart() {
        let view = GlassEffectContainer {
            HStack(spacing: 0) {
                Text("A").padding(.horizontal).glassEffect()
                Text("B").padding(.horizontal).glassEffect(.clear)
            }
        }
        #expect(frames(view, width: 6).last == ["(A)(B)"])
    }

    @Test("A union is drawn as one shape wherever its members are; another union is its own")
    func union() {
        let namespace = Namespace().wrappedValue
        let view = GlassEffectContainer {
            HStack(spacing: 3) {
                Text("A").padding(.horizontal).glassEffect().glassEffectUnion(id: "left", namespace: namespace)
                Text("B").padding(.horizontal).glassEffect().glassEffectUnion(id: "left", namespace: namespace)
                Text("C").padding(.horizontal).glassEffect().glassEffectUnion(id: "right", namespace: namespace)
            }
        }
        #expect(frames(view, width: 15).last == ["(A     B)   (C)"])
        let none = HStack(spacing: 3) {
            Text("A").padding(.horizontal).glassEffect().glassEffectUnion(id: "left", namespace: namespace)
            Text("B").padding(.horizontal).glassEffect().glassEffectUnion(id: "left", namespace: namespace)
        }
        #expect(frames(none, width: 9).last == ["(A)   (B)"], "outside a container a union is nothing")
    }

    @Test("Glass that leaves a group is drawn apart at once")
    func leaving() {
        let tui = TUIContext()
        let joined = frames(GlassEffectContainer { pair(spacing: 0) }, width: 8, tui: tui)
        #expect(joined.last == ["(A  B)"])
        let apart = frames(GlassEffectContainer { pair(spacing: 2) }, count: 2, width: 8, tui: tui)
        #expect(apart[0] == ["(A)  (B)"], "apart on the pass they part")
        #expect(apart[1] == ["(A)  (B)"])
    }

    @Test("Glass that comes to touch a group joins it on that pass; the group never comes apart")
    func joiningAGroup() {
        func row(gap: Int) -> some View {
            GlassEffectContainer {
                HStack(spacing: 0) {
                    Text("A").padding(.horizontal).glassEffect()
                    Text("B").padding(.horizontal).glassEffect()
                    Color.clear.frame(width: gap)
                    Text("C").padding(.horizontal).glassEffect()
                }
            }
        }
        let tui = TUIContext()
        #expect(frames(row(gap: 1), width: 10, tui: tui).last == ["(A  B) (C)"])
        let joining = frames(row(gap: 0), width: 10, tui: tui)
        #expect(joining[0] == joining[1], "joined on the pass it comes to touch")
        #expect(joining[1] == ["(A  B  C)"])
    }

    @Test("Glass in a scroll view in a container is drawn by itself")
    func scrollViewIsItsOwn() {
        let view = GlassEffectContainer {
            ScrollView(.horizontal) { pair(spacing: 0) }
        }
        #expect(frames(view, width: 6, height: 1).last?.first?.hasPrefix("(A)(B)") == true)
    }

    @Test("A container's markers stay its own")
    func markersDoNotLeak() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        let tui = TUIContext()
        let context = RenderContext(availableWidth: 6, availableHeight: 1, environment: environment, tuiContext: tui)
        let buffer = renderToBuffer(GlassEffectContainer { pair(spacing: 0) }, context: context)
        #expect(!buffer.carriesGeometryMarkers)
    }
}
