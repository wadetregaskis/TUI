//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClippedAndCompositingTests.swift
//
//  `clipped(antialiased:)` cuts a view's displaced drawing at its frame, and
//  `compositingGroup()` names a guarantee the compositor already keeps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("Clipping and compositing groups")
struct ClippedAndCompositingTests {

    /// What `view` puts on screen, its floating layers composited, as text.
    private func screen(_ view: some View) -> [String] {
        let harness = InputChainHarness(width: 12, height: 2)
        let buffer = harness.frame(view)
        return buffer.compositingOverlays(
            maxWidth: 12, maxHeight: 2, palette: harness.context.environment.palette
        ).lines.map(\.stripped)
    }

    @Test("A clipped view's displaced drawing stops at its frame")
    func clipsDisplacedDrawing() {
        let loose = screen(HStack(spacing: 0) { Text("abcd").offset(x: 2); Text("WXYZ") })
        #expect(loose.first?.hasPrefix("  abcd") == true, "\(loose)")
        let clipped = screen(HStack(spacing: 0) { Text("abcd").offset(x: 2).clipped(); Text("WXYZ") })
        #expect(clipped.first?.hasPrefix("  abWXYZ") == true, "\(clipped)")
        #expect(screen(Text("abcd").offset(x: 2).clipped(antialiased: true)) == screen(Text("abcd").offset(x: 2).clipped()))
    }

    @Test("A clipped view measures as its content does")
    func clippingKeepsTheFrame() {
        let plain = screen(HStack(spacing: 0) { Text("abcd"); Text("|") })
        let clipped = screen(HStack(spacing: 0) { Text("abcd").clipped(); Text("|") })
        #expect(plain == clipped)
    }

    @Test("Overlapping children never show through one another under opacity")
    func childrenAreComposited() {
        let overlap = ZStack(alignment: .leading) { Text("AAAA"); Text("BB") }
        let grouped = renderToScreen(overlap.compositingGroup().opacity(0.5), context: InputChainHarness(width: 12, height: 1).context)
        let ungrouped = renderToScreen(overlap.opacity(0.5), context: InputChainHarness(width: 12, height: 1).context)
        #expect(grouped.lines.first?.stripped.hasPrefix("BBAA") == true, "\(grouped.lines.map(\.stripped))")
        #expect(grouped.lines == ungrouped.lines)
    }
}
