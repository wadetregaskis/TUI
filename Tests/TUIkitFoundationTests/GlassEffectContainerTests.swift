//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectContainerTests.swift
//
//  `GlassEffectContainer` and `glassEffectUnion(id:namespace:)`: glass that
//  touches, comes closer than the container's spacing, or shares a union is
//  drawn as one shape.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

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

    @Test("In a container, glass that touches is drawn as one shape from the next pass")
    func touchingJoins() {
        let drawn = frames(GlassEffectContainer { pair(spacing: 0) }, width: 6)
        // The first pass learns who touches; each glass has drawn itself by then.
        #expect(drawn[0] == ["(A)(B)"])
        #expect(drawn[1] == ["(A  B)"])
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

    @Test("Glass that leaves a group is drawn apart at once, and draws itself again after")
    func leaving() {
        let tui = TUIContext()
        let joined = frames(GlassEffectContainer { pair(spacing: 0) }, width: 8, tui: tui)
        #expect(joined.last == ["(A  B)"])
        let apart = frames(GlassEffectContainer { pair(spacing: 2) }, count: 2, width: 8, tui: tui)
        #expect(apart[0] == ["(A)  (B)"], "the container draws them apart while they still leave it their glass")
        #expect(apart[1] == ["(A)  (B)"])
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
