//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapesPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

// MARK: - Shapes Page

/// Shapes demo page: the rectangle family in the terminal's own lines and
/// cells, everything else rasterized at half-block resolution, a shape turned,
/// trimmed and dashed, and shapes behind, over and clipping views.
///
/// Every shape here is SwiftUI source: `Circle().fill(.green)`,
/// `RoundedRectangle(cornerRadius: 2).stroke(.cyan)`. What changes is the unit
/// — a column across and a row's height down, about two columns — so a frame
/// twice as wide as it is tall is square, and the circles are drawn in such
/// frames.
struct ShapesPage: View {
    /// The rotated rectangle's angle, in degrees.
    @State private var angle = 30.0

    /// How much of the trimmed circle is drawn.
    @State private var trim = 0.7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.shapes.units")
                    .foregroundStyle(.palette.foregroundSecondary)
                strokes
                fills
                rasterized
                transformed
                modifiers
            }
            .padding(.horizontal, 1)
        }
        .navigationTitle("menu.item.shapes")
        .navigationSubtitle("page.shapes.subtitle")
    }

    // MARK: - Lines

    /// The rectangle family stroked: a box of line glyphs, a corner per corner.
    private var strokes: some View {
        DemoSection("page.shapes.section.lines") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.shapes.lines.hint").foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    sample(".stroke()") { Rectangle().stroke(Color.palette.accent) }
                    sample("cornerRadius: 2") { RoundedRectangle(cornerRadius: 2).stroke(.cyan) }
                    sample("Uneven…") {
                        UnevenRoundedRectangle(topLeadingRadius: 2, bottomTrailingRadius: 2).stroke(.green)
                    }
                    sample("Capsule") { Capsule().stroke(.orange) }
                    sample("dash: [2, 1]") {
                        RoundedRectangle(cornerRadius: 2).stroke(.pink, style: StrokeStyle(lineWidth: 1, dash: [2, 1]))
                    }
                }
            }
        }
    }

    // MARK: - Fills

    /// The rectangle family filled: cells of the paint, rounded corners cut in
    /// quadrants, one row capped.
    private var fills: some View {
        DemoSection("page.shapes.section.fills") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.shapes.fills.hint").foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    sample("Rectangle") { Rectangle().fill(.blue) }
                    sample("cornerRadius: 1") { RoundedRectangle(cornerRadius: 1).fill(.purple) }
                    sample("cornerRadius: 4") { RoundedRectangle(cornerRadius: 4).fill(.purple) }
                    sample("Capsule") { Capsule().fill(.teal) }
                    sample("Capsule, 1 row", height: 1) { Capsule().fill(.mint) }
                }
            }
        }
    }

    // MARK: - Rasterized

    /// Circles, ellipses, gradients and a path of the app's own.
    private var rasterized: some View {
        DemoSection("page.shapes.section.raster") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.shapes.raster.hint").foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    sample("Circle", width: 12, height: 6) { Circle().fill(.green) }
                    sample("Ellipse", width: 18, height: 6) {
                        Ellipse().fill(LinearGradient(colors: [.orange, .purple], startPoint: .leading, endPoint: .trailing))
                    }
                    sample(".strokeBorder", width: 12, height: 6) { Circle().strokeBorder(.yellow, lineWidth: 1) }
                    sample("Star", width: 12, height: 6) { Star().fill(.yellow) }
                    sample(".fill.stroke", width: 12, height: 6) {
                        Circle().fill(.yellow).stroke(.red, lineWidth: 1)
                    }
                }
            }
        }
    }

    // MARK: - Turned, trimmed and dashed

    /// A path is coordinates: turning or trimming one is arithmetic before it
    /// is drawn.
    private var transformed: some View {
        DemoSection("page.shapes.section.transforms") {
            VStack(alignment: .leading, spacing: 1) {
                Slider(value: $angle, in: 0...360, step: 5) {
                    Text("\(L("page.shapes.transforms.angle")) \(Int(angle))°")
                }
                Slider(value: $trim, in: 0...1, step: 0.05) {
                    Text("\(L("page.shapes.transforms.trim")) \(Int((trim * 100).rounded()))%")
                }
                Button("page.shapes.transforms.animate") {
                    withAnimation(.easeInOut(duration: 1)) { trim = trim < 0.5 ? 1 : 0 }
                }
                HStack(alignment: .top, spacing: 2) {
                    sample(".rotation", width: 16, height: 8) {
                        Rectangle().inset(by: 3).rotation(.degrees(angle)).fill(.red)
                    }
                    sample(".trim", width: 16, height: 8) {
                        Circle().trim(from: 0, to: trim).stroke(.mint, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    }
                    sample("dash, phase", width: 16, height: 8) {
                        Circle().stroke(.cyan, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0, 3], dashPhase: angle / 30))
                    }
                }
            }
        }
    }

    // MARK: - Behind, over and clipping

    /// A shape behind a label, over a view and as its clip.
    private var modifiers: some View {
        DemoSection("page.shapes.section.modifiers") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.shapes.modifiersExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    caption(".background(_:in:)") {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("page.shapes.sample.tag")
                                .padding(.horizontal, 1)
                                .background(.purple, in: Capsule())
                            Text("page.shapes.sample.card")
                                .padding(1)
                                .background(.teal, in: RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    caption(".overlay(_:in:)") {
                        Text("page.shapes.sample.overlay")
                            .frame(width: 16, height: 6)
                            .background(Color.blue)
                            .overlay(.orange.opacity(0.6), in: Ellipse())
                    }
                    caption(".clipShape(Circle())") {
                        Text("page.shapes.sample.clipped")
                            .frame(width: 16, height: 8)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    /// `shape` in a `width` × `height` frame, with its spelling under it.
    private func sample(
        _ spelling: String, width: Int = 14, height: Int = 4, @ViewBuilder shape: () -> some View
    ) -> some View {
        caption(spelling) { shape().frame(width: width, height: height) }
    }

    /// `content` with `spelling` under it, as code: an API's name is the same in
    /// every language.
    private func caption(_ spelling: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Text(verbatim: spelling).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}

/// A five-pointed star — a shape of the app's own, written as a SwiftUI one is:
/// from its rectangle's middle and its shorter side, so it keeps its points
/// wherever it is drawn.
private struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : outer * 0.4
            let angle = Double(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
