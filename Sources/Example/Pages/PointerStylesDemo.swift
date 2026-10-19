//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PointerStylesDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// A box per pointer style (`.pointerStyle(_:)`): the pointer takes each one's
/// shape while it is over it — on a terminal that takes shapes by name. On any
/// other the boxes change nothing, and the demo says so
/// (`\.terminalFeatures.pointerShapes`).
struct PointerStylesDemo: View {
    @Environment(\.terminalFeatures) private var terminal

    /// Each style, the name it is written with, and what it shows.
    private var styles: [(style: PointerStyle, name: String, shows: LocalizedStringKey)] {
        [
            (.default, ".default", "page.mouse.pointerArrow"),
            (.horizontalText, ".horizontalText", "page.mouse.pointerIBeam"),
            (.verticalText, ".verticalText", "page.mouse.pointerVerticalIBeam"),
            (.link, ".link", "page.mouse.pointerHand"),
            (.grabIdle, ".grabIdle", "page.mouse.pointerOpenHand"),
            (.grabActive, ".grabActive", "page.mouse.pointerClosedHand"),
            (.columnResize, ".columnResize", "page.mouse.pointerColumnResize"),
            (.rowResize, ".rowResize", "page.mouse.pointerRowResize"),
            (.frameResize(position: .bottomTrailing), ".frameResize", "page.mouse.pointerCornerResize"),
            (.rectSelection, ".rectSelection", "page.mouse.pointerCrosshair"),
            (.zoomIn, ".zoomIn", "page.mouse.pointerZoomIn"),
            (.zoomOut, ".zoomOut", "page.mouse.pointerZoomOut"),
        ]
    }

    var body: some View {
        DemoSection("page.mouse.pointerStyles") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.mouse.pointerStylesExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text(terminal.pointerShapes ? "page.mouse.pointerStylesShown" : "page.mouse.pointerStylesNotShown")
                    .foregroundStyle(.palette.foregroundTertiary)
                Flow(spacing: 1) {
                    ForEach(styles.indices, id: \.self) { index in
                        box(styles[index])
                    }
                }
            }
        }
    }

    /// One style's box: its name and what it shows, and the style over it.
    private func box(_ entry: (style: PointerStyle, name: String, shows: LocalizedStringKey)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: entry.name)
            Text(entry.shows).foregroundStyle(.palette.foregroundSecondary)
        }
        .frame(width: 22, alignment: .leading)
        .padding(.horizontal, 1)
        .border(.palette.border)
        .pointerStyle(entry.style)
    }
}
