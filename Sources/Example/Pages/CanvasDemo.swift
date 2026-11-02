//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasDemo.swift
//
//  The Shapes page's `Canvas` section: SwiftUI source drawing paths, gradients,
//  text and symbols, and the grains and raw pixels only a terminal has.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// A `Canvas` drawing what a shape cannot: several things at once, clipped and
/// layered, in code run for the frame.
struct CanvasDemo: View {
    /// How far the clock has turned, driven by the slider, so every frame can be
    /// reached by the keyboard.
    @State private var turn = 0.2

    var body: some View {
        DemoSection("page.shapes.section.canvas") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.shapes.canvas.hint").foregroundStyle(.palette.foregroundSecondary)
                Slider(value: $turn, in: 0...1, step: 0.02) {
                    Text("page.shapes.canvas.turn")
                }
                HStack(alignment: .top, spacing: 2) {
                    caption("fill, stroke, draw") { clock.frame(width: 24, height: 12) }
                    caption("clip, drawLayer") { layered.frame(width: 24, height: 12) }
                    caption("resolveSymbol") { symbols.frame(width: 24, height: 12) }
                }
                Text("page.shapes.canvas.grainHint").foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    grain(".halfBlocks", .halfBlocks)
                    grain(".quadrants", .quadrants)
                    grain(".braille", .braille)
                    caption("setPixel") { pixels.canvasGrain(.quadrants).frame(width: 18, height: 8) }
                }
            }
        }
    }

    /// A clock's face: a gradient disc, a stroked ring, a turning hand and text.
    private var clock: some View {
        Canvas { [turn] context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let face = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(
                face,
                with: .radialGradient(
                    Gradient(colors: [.rgb(70, 110, 190), .rgb(20, 30, 80)]), center: centre, startRadius: 0, endRadius: radius))
            context.stroke(face, with: .color(.rgb(240, 240, 255)), lineWidth: 0.5)
            var hand = context
            hand.translateBy(x: centre.x, y: centre.y)
            hand.rotate(by: .degrees(turn * 360 - 90))
            hand.stroke(
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: radius * 0.8, y: 0))
                },
                with: .color(.rgb(255, 170, 60)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
            context.draw(Text(verbatim: "\(Int(turn * 60))s"), at: CGPoint(x: centre.x, y: centre.y + radius / 2))
        }
    }

    /// Stripes clipped to a disc, and two squares drawn as one translucent layer,
    /// so they do not darken where they overlap.
    private var layered: some View {
        Canvas { context, size in
            var clipped = context
            clipped.clip(to: Path(ellipseIn: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)))
            for stripe in 0..<12 {
                let rect = CGRect(x: 0, y: CGFloat(stripe) * size.height / 12, width: size.width, height: size.height / 24)
                clipped.fill(Path(rect), with: .color(.rgb(90, 200, 120)))
            }
            context.opacity = 0.7
            context.drawLayer { layer in
                let side = size.height / 2
                layer.fill(Path(CGRect(x: 2, y: 2, width: side, height: side)), with: .color(.rgb(230, 90, 90)))
                layer.fill(Path(CGRect(x: 6, y: 6, width: side, height: side)), with: .color(.rgb(230, 90, 90)))
            }
        }
    }

    /// A view drawn three times, wherever the renderer says.
    private var symbols: some View {
        Canvas { context, size in
            guard let badge = context.resolveSymbol(id: "badge") else { return }
            for index in 0..<3 {
                let place = CGPoint(x: size.width * (CGFloat(index) + 0.5) / 3, y: size.height * (CGFloat(index) + 0.5) / 3)
                context.opacity = 1 - Double(index) * 0.3
                context.draw(badge, at: place)
            }
        } symbols: {
            Text(verbatim: " ★ ").foregroundStyle(.black).background(.yellow).tag("badge")
        }
    }

    /// One curve at a grain: `grain` is a modifier, the drawing the same.
    private func grain(_ spelling: String, _ grain: CanvasGrain) -> some View {
        caption(spelling) {
            Canvas { context, size in
                let wave = Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    for x in stride(from: CGFloat(0), through: size.width, by: 0.25) {
                        let wave = sin(Double(x / size.width) * 4 * Double.pi)
                        path.addLine(to: CGPoint(x: x, y: size.height / 2 + CGFloat(wave) * size.height * 0.4))
                    }
                }
                context.stroke(wave, with: .color(.rgb(120, 220, 255)), lineWidth: 0.5)
            }
            .canvasGrain(grain)
            .frame(width: 18, height: 8)
        }
    }

    /// Raw pixels: a checker that fades to the right, one `setPixel` a pixel.
    private var pixels: some View {
        Canvas { context, _ in
            let grid = context.pixelGrid
            for y in 0..<grid.height {
                for x in 0..<grid.width where (x / 2 + y / 2).isMultiple(of: 2) {
                    let level = UInt8(60 + 195 * x / max(1, grid.width))
                    context.setPixel(x: x, y: y, to: .rgb(level, level / 2, 255 - level))
                }
            }
        }
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
