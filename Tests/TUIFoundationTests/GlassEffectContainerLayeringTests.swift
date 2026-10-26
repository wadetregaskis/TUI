//  🖥️ TUI — A Terminal UI framework for Swift
//  GlassEffectContainerLayeringTests.swift
//
//  What lies between a glass and its `GlassEffectContainer` — a background,
//  `.hidden()`, `.opacity`, a clip — acts on the glass in a joined shape as it
//  acts on glass alone, on every pass; what lies between the glass it joins
//  is drawn over the background.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Glass in a container, under what lies between")
struct GlassEffectContainerLayeringTests {

    /// The screen after `passes` whole passes of `view` through one context —
    /// a container keeps who it joined between passes — in 24-bit colour.
    private func settled(_ view: some View, width: Int, height: Int = 1, passes: Int = 3) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = SystemPalette.green
        let tui = TUIContext()
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        var lines: [String] = []
        for _ in 0..<passes {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            lines = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines }
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
        }
        return lines
    }

    private func glass(_ label: String) -> some View {
        Text(label).padding(.horizontal).glassEffect()
    }

    @Test("An opaque background inside the container stays behind the joined glass")
    func backgroundInsideTheContainer() {
        let view = GlassEffectContainer {
            HStack(spacing: 0) { glass("A"); glass("B") }.background(Color.blue)
        }
        #expect(settled(view, width: 6).map(\.stripped) == ["(A  B)"])
    }

    @Test("A glass's own background stays behind its part of the joined glass")
    func backgroundOfAMember() {
        let view = GlassEffectContainer {
            HStack(spacing: 0) { glass("A").background(Color.red); glass("B") }
        }
        #expect(settled(view, width: 6).map(\.stripped) == ["(A  B)"])
    }

    @Test("What bridges a joined shape is drawn over a background inside the container")
    func bridgeOverABackground() {
        let view = GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) { glass("A"); glass("B") }.background(Color.blue)
        }
        let lines = settled(view, width: 7)
        #expect(lines.map(\.stripped) == ["(A   B)"])
        let cells = paintedCells(lines[0])
        #expect(cells[3].background == cells[1].background, "the gap is glass over the blue, as the padding is")
    }

    @Test("What bridges a joined shape stays under what is drawn between its members")
    func bridgeUnderAGlyph() {
        let namespace = Namespace().wrappedValue
        let view = GlassEffectContainer {
            HStack(spacing: 0) {
                glass("A").glassEffectUnion(id: 1, namespace: namespace)
                Text("x")
                glass("B").glassEffectUnion(id: 1, namespace: namespace)
            }
        }
        #expect(settled(view, width: 7).map(\.stripped) == ["(A x B)"])
    }

    @Test("Glass in a hidden view joins nothing")
    func hidden() {
        let pair = HStack(spacing: 0) { glass("A"); glass("B").hidden() }
        #expect(settled(GlassEffectContainer { pair }, width: 6) == settled(pair, width: 6))
    }

    @Test("Glass faded by an opacity is drawn by itself, as faded as outside a container")
    func faded() {
        let pair = HStack(spacing: 0) { glass("A"); glass("B").opacity(0.3) }
        #expect(settled(GlassEffectContainer { pair }, width: 6) == settled(pair, width: 6))
    }

    @Test("Glass inside a clip is drawn by itself, cut as outside a container")
    func clipped() {
        let pair = HStack(spacing: 0) {
            Text("AAAA").padding(.horizontal).glassEffect().frame(width: 4, alignment: .leading).clipped()
            glass("B")
        }
        #expect(settled(GlassEffectContainer { pair }, width: 7) == settled(pair, width: 7))
    }

    @Test("What bridges a joined shape is drawn in its members' environment, as their parts are")
    func bridgeInTheMembersEnvironment() {
        let view = GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) {
                Text("A").padding().glassEffect()
                Text("B").padding().glassEffect()
            }
            .environment(\.appearance, .heavy)
        }
        #expect(settled(view, width: 7, height: 3).map(\.stripped) == ["┏━━━━━┓", "┃A   B┃", "┗━━━━━┛"])
    }
}
