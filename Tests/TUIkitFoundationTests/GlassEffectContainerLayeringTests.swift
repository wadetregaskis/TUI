//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassEffectContainerLayeringTests.swift
//
//  What lies between a glass and its `GlassEffectContainer` — a background —
//  acts on the glass in a joined shape as it acts on glass alone, on every
//  pass; what lies between the glass it joins is drawn over the background.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

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
}
