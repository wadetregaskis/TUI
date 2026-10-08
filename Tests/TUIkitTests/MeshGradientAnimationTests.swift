//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshGradientAnimationTests.swift
//
//  A mesh gradient moves inside `withAnimation` — its vertices, its colours
//  and its background — as SwiftUI's does, measured on macOS 15.8.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Animating a mesh gradient")
struct MeshGradientAnimationTests {

    /// One place in the tree, drawn again as the frame clock advances.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 20, height: 1)

        init(_ animation: Animation?) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        func draw<V: View>(_ view: V, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context).lines }
        }
    }

    /// Each cell's truecolor background, in order.
    private func fills(_ line: String) -> [String] {
        var out: [String] = []
        var current = "—"
        var rest = Substring(line)
        while let escape = rest.firstIndex(of: "\u{1B}") {
            for character in rest[rest.startIndex..<escape] {
                out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
            }
            rest = rest[escape...]
            guard let end = rest.firstIndex(of: "m") else { break }
            let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<end]
            if let range = body.range(of: "48;2;") {
                current = body[range.upperBound...].split(separator: ";").prefix(3).joined(separator: ";")
            } else if body == "0" {
                current = "—"
            }
            rest = rest[rest.index(after: end)...]
        }
        for character in rest {
            out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
        }
        return out
    }

    /// Black, white, black across, the white column at `x`: the brightest cell
    /// is where the column is.
    private func ridge(at x: Float) -> some View {
        MeshGradient(
            width: 3, height: 2, points: [[0, 0], [x, 0], [1, 0], [0, 1], [x, 1], [1, 1]],
            colors: [.rgb(0, 0, 0), .rgb(255, 255, 255), .rgb(0, 0, 0), .rgb(0, 0, 0), .rgb(255, 255, 255), .rgb(0, 0, 0)],
            smoothsColors: false
        )
        .frame(width: 20, height: 1)
    }

    private func brightest(_ line: String) -> Int? {
        let cells = fills(line).map { $0.split(separator: ";").compactMap { Int($0) }.reduce(0, +) }
        guard let peak = cells.max() else { return nil }
        return cells.firstIndex(of: peak)
    }

    @Test("A vertex that moves inside withAnimation slides there")
    func vertexSlides() throws {
        let screen = Screen(.linear(duration: 1))
        let before = screen.draw(ridge(at: 0.1), atMillis: 0)
        #expect(brightest(before[0]) == 2, "\(fills(before[0]))")
        // The frame the change lands on still shows the old mesh.
        #expect(screen.draw(ridge(at: 0.9), atMillis: 0) == before)
        let half = screen.draw(ridge(at: 0.9), atMillis: 500)
        let middle = try #require(brightest(half[0]))
        #expect((9...10).contains(middle), "the column did not move half way: \(middle)")
        let end = screen.draw(ridge(at: 0.9), atMillis: 1000)
        #expect(brightest(end[0]) == 17, "\(fills(end[0]))")
    }

    @Test("Without an animation a mesh changes at once")
    func noAnimationIsImmediate() {
        let screen = Screen(nil)
        _ = screen.draw(ridge(at: 0.1), atMillis: 0)
        let changed = screen.draw(ridge(at: 0.9), atMillis: 0)
        #expect(brightest(changed[0]) == 17, "\(fills(changed[0]))")
    }

    @Test("A vertex's colour fades as a gradient stop does")
    func colourFades() {
        func flat(_ colour: Color) -> some View {
            MeshGradient(
                width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                colors: [colour, colour, colour, colour], smoothsColors: false
            )
            .frame(width: 20, height: 1)
        }
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(flat(.rgb(0, 0, 0)), atMillis: 0)
        _ = screen.draw(flat(.rgb(200, 0, 0)), atMillis: 0)
        let half = screen.draw(flat(.rgb(200, 0, 0)), atMillis: 500)
        #expect(Set(fills(half[0])) == ["100;0;0"], "\(Set(fills(half[0])))")
    }

    @Test("A mesh that changes shape snaps rather than moving one vertex toward another's place")
    func reshapingSnaps() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(ridge(at: 0.1), atMillis: 0)
        // Two columns of vertices instead of three: a different mesh.
        let wide = MeshGradient(
            width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
            colors: [.rgb(255, 255, 255), .rgb(0, 0, 0), .rgb(255, 255, 255), .rgb(0, 0, 0)], smoothsColors: false
        )
        .frame(width: 20, height: 1)
        _ = screen.draw(wide, atMillis: 0)
        let half = screen.draw(wide, atMillis: 500)
        #expect(brightest(half[0]) == 0, "\(fills(half[0]))")
    }
}
