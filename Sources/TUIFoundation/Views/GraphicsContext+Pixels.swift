//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Pixels.swift
//
//  TUI additions to `GraphicsContext`, named apart from SwiftUI's: addressing
//  the grid a canvas draws on, a pixel or a cell at a time.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling

extension GraphicsContext {
    /// The size of the grid this context draws on, in pixels — a TUI addition.
    /// What ``setPixel(x:y:to:)`` addresses: it changes with the terminal and
    /// ``View/canvasGrain(_:)``, so read it rather than assuming one.
    public var pixelGrid: (width: Int, height: Int) {
        (surface.frame.columns * surface.grid.across, surface.frame.rows * surface.grid.down)
    }

    /// Sets one pixel of the grid — a TUI addition, for a plot or a cellular
    /// automaton, where a path would be a square per point. In the grid's
    /// coordinates (``pixelGrid``), past the transform; under the opacity, blend
    /// mode, colour filters and clip.
    ///
    /// - Parameters:
    ///   - x: The pixel's column, from the left.
    ///   - y: The pixel's row, from the top.
    ///   - color: Its colour.
    public func setPixel(x: Int, y: Int, to color: Color) {
        paint(.flat(surface.pixel(of: color))) { raster, source, opacity, mode, clip in
            raster.paintPixel(x: x, y: y, source: source, opacity: opacity, mode: mode, clip: clip)
        } covering: { [surface] column, row in
            let (across, down) = (surface.grid.across, surface.grid.down)
            return x / across == column && y / down == row ? 1 / Double(across * down) : 0
        }
    }

    /// Draws a line one pixel wide with no antialiasing between two points — a
    /// TUI addition. ``stroke(_:with:lineWidth:)`` blends a thin line's edge, so
    /// at a grain of a few pixels a cell it thickens and fades; this keeps it
    /// sharp, one pixel a step, as a plot wants.
    ///
    /// - Parameters:
    ///   - start: Where it starts, in the context's coordinates.
    ///   - end: Where it ends, the last pixel included.
    ///   - shading: What to paint it with.
    public func drawLine(from start: CGPoint, to end: CGPoint, with shading: Shading) {
        let device = transform.concatenating(surface.deviceMatrix)
        let (from, to) = (start.applying(device), end.applying(device))
        let grid = pixelGrid
        // Non-finite, or too far off to walk: no line reaches the grid from
        // there in a number of steps worth taking.
        let limit = CGFloat(1 << 16)
        guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite,
            abs(from.x) < limit, abs(from.y) < limit, abs(to.x) < limit, abs(to.y) < limit
        else { return }
        let pixelBounds = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let source = source(of: shading, bounds: pixelBounds)
        var points: [(x: Int, y: Int)] = []
        var (x, y) = (Int(from.x.rounded(.down)), Int(from.y.rounded(.down)))
        let (lastX, lastY) = (Int(to.x.rounded(.down)), Int(to.y.rounded(.down)))
        let (deltaX, deltaY) = (abs(lastX - x), -abs(lastY - y))
        let (stepX, stepY) = (x < lastX ? 1 : -1, y < lastY ? 1 : -1)
        var error = deltaX + deltaY
        while true {
            if x >= 0, y >= 0, x < grid.width, y < grid.height { points.append((x, y)) }
            if x == lastX, y == lastY { break }
            let doubled = 2 * error
            if doubled >= deltaY {
                error += deltaY
                x += stepX
            }
            if doubled <= deltaX {
                error += deltaX
                y += stepY
            }
        }
        paint(source) { raster, source, opacity, mode, clip in
            for point in points {
                raster.paintPixel(x: point.x, y: point.y, source: source, opacity: opacity, mode: mode, clip: clip)
            }
        } covering: { _, _ in 0 }
    }

    /// Draws a bitmap to fill `rect` — a TUI addition, for a dense picture your
    /// program computes, without making an ``Image`` of it each frame.
    ///
    /// - Parameters:
    ///   - pixels: The colours, row by row from the top: `width` × `height` of
    ///     them, or nothing is drawn.
    ///   - width: How many pixels a row has.
    ///   - height: How many rows.
    ///   - rect: Where to draw it, in the context's coordinates. Each pixel is a
    ///     sharp block of it.
    public func drawPixels(_ pixels: [Color], width: Int, height: Int, in rect: CGRect) {
        guard width > 0, height > 0, pixels.count == width * height, rect.width > 0, rect.height > 0 else { return }
        let device = transform.concatenating(surface.deviceMatrix)
        let inverse = device.inverted()
        let colours = pixels.map { surface.pixel(of: $0) }
        let polygons = Path(rect).applying(device).contours(tolerance: Self.flattening).map(\.points)
        let source = CanvasSource.sampled { x, y in
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(inverse)
            let column: Double = Double((point.x - rect.minX) / rect.width) * Double(width)
            let row: Double = Double((point.y - rect.minY) / rect.height) * Double(height)
            let across = Int(max(0, min(Double(width - 1), column.rounded(.down))))
            let down = Int(max(0, min(Double(height - 1), row.rounded(.down))))
            return colours[down * width + across]
        }
        let across = CGFloat(surface.grid.across)
        let down = CGFloat(surface.grid.down)
        paint(source) { raster, source, opacity, mode, clip in
            raster.paint(polygons: polygons, evenOdd: false, antialiased: false, source: source, opacity: opacity, mode: mode, clip: clip)
        } covering: { column, row in
            let centre = CGPoint(x: (CGFloat(column) + 0.5) * across, y: (CGFloat(row) + 0.5) * down)
            return rect.contains(centre.applying(inverse)) ? 1.0 : 0.0
        }
    }

    /// Writes a character into a whole cell — a TUI addition, for what only a
    /// terminal has: a line-drawing corner, a glyph at an exact cell. In cells,
    /// past the transform; under the opacity, colour filters, clip and
    /// ``textAttributes``. A character wider than a cell takes the next too.
    ///
    /// - Parameters:
    ///   - column: The cell's column.
    ///   - row: The cell's row.
    ///   - character: What to write.
    ///   - foreground: The character's colour; the terminal's own if `nil`.
    ///   - background: The colour behind it; what is drawn beneath it if `nil`.
    public func setCell(column: Int, row: Int, to character: Character, foreground: Color? = nil, background: Color? = nil) {
        guard surface.reaches(CGPoint(x: CGFloat(column), y: CGFloat(row))) else { return }
        var style = SGRState()
        let palette = environment.palette
        if let foreground { style.apply("\u{1B}[" + foreground.resolve(with: palette).opaqueSpelling.foregroundCodes().joined(separator: ";") + "m") }
        if let background { style.apply(background.resolve(with: palette).opaqueSpelling.backgroundEscape()) }
        writeGlyph(String(character), width: max(1, character.terminalWidth), style: style, column: column, row: row)
    }
}
