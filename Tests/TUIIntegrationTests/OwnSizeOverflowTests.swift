//  🖥️ TUI — A Terminal UI framework for Swift
//  OwnSizeOverflowTests.swift
//
//  Content drawn at its own size — `.fixedSize()` — larger than the frame,
//  overlay or background placing it, is drawn whole, placed by the region's
//  alignment, the part past the region drawn past it at the view's place in
//  the stacking order, as SwiftUI draws it (decisions B-GUIDE3-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Content drawn at its own size past its region")
struct OwnSizeOverflowTests {

    /// The screen `view` makes, its floating layers composited, each line's
    /// trailing blanks dropped.
    private func screen(_ view: some View, width: Int = 24, height: Int = 4) -> [String] {
        let context = makeRenderContext(width: width, height: height)
        let buffer = renderToBuffer(view, context: context)
        return buffer.compositingOverlays(maxWidth: width, maxHeight: height, palette: context.environment.palette)
            .lines.map { line in
                var text = line.stripped
                while text.last == " " { text.removeLast() }
                return text
            }
    }

    /// Ten digits fixed at their ideal width in a four-cell frame between two
    /// six-cell runs: the frame is columns 6 to 9.
    private func row(_ alignment: Alignment) -> some View {
        HStack(spacing: 0) {
            Text("......")
            Text("0123456789").fixedSize().frame(width: 4, alignment: alignment)
            Text(",,,,,,")
        }
    }

    @Test("Centred in a frame narrower than it, fixed-size content is drawn past both edges")
    func centredInAFrame() {
        // SwiftUI: a 40-wide view in a 20-wide centred frame draws 10 past
        // each side (GUIDE2 `g2c`). Here 3 past each side: over the dots
        // before the frame, under the commas after it. It was cut to "0123".
        #expect(screen(row(.center)).first == "...0123456,,,,,,")
    }

    @Test("Aligned trailing it is drawn past the frame's leading edge, aligned leading past its trailing one")
    func trailingAndLeadingInAFrame() {
        #expect(screen(row(.trailing)).first == "0123456789,,,,,,")
        #expect(screen(row(.leading)).first == "......0123,,,,,,", "past the trailing edge, under the commas")
    }

    @Test("A fixed-size overlay larger than its base is drawn past the base by its alignment")
    func overlayPastItsBase() {
        let view = HStack(spacing: 0) {
            Text("xxxxxx")
            Text("ab").overlay { Text("0123456789").fixedSize() }
            Text("yyyyyy")
        }
        #expect(screen(view).first == "xx012345yyyyyy")
    }

    @Test("Down the column too, and content that wraps to its offer is cut as before")
    func verticalAndWrapping() {
        let column = VStack(alignment: .leading, spacing: 0) {
            Text("-")
            Text("1\n2\n3").fixedSize().frame(width: 1, height: 1, alignment: .center)
            Text("+")
        }
        #expect(screen(column, height: 6).prefix(3) == ["1", "2", "+"])
        // Not drawn at its own size: truncated to the frame's four cells.
        #expect(screen(Text("0123456789").frame(width: 4, alignment: .center)).first == "012…")
    }
}
