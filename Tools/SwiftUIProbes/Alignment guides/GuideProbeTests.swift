//  GUIDE probe (scratch, not for landing): where TUI places a child whose
//  explicit guide lies outside its own extent, for comparison with SwiftUI.

import Foundation
import Testing

import TUI
@testable import TUIFoundation
@testable import TUITestSupport

private func run(_ char: Character, _ count: Int) -> String { String(repeating: char, count: count) }

/// A column of `height` one-cell rows of `char`.
private struct Column: View {
    let char: Character
    let height: Int
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<height, id: \.self) { _ in Text(String(char)) }
        }
    }
}

@MainActor
@Suite("GUIDE probe")
struct GuideProbeTests {
    static let guides: [Double] = [0, 1, 2, 5, 10, 15, 25, -1, -3, -10]
    /// Relative to the package root, where `swift test` runs; it overwrites the recorded output.
    static let out = "Tools/SwiftUIProbes/Alignment guides/tuikit.out"

    private func firstColumn(of char: Character, in buffer: FrameBuffer) -> Int {
        for line in buffer.lines {
            let s = Array(line.stripped)
            if let i = s.firstIndex(of: char) { return i }
        }
        return -99
    }

    private func firstRow(of char: Character, in buffer: FrameBuffer) -> Int {
        for (row, line) in buffer.lines.enumerated() where line.stripped.contains(char) { return row }
        return -99
    }

    private func name(_ v: Double) -> String { String(Int(v)) }

    private func vcase(_ alignment: HorizontalAlignment, _ aname: String, gw: Int, sw: Int, g: Double) -> String {
        let buffer = renderToBuffer(
            VStack(alignment: alignment, spacing: 0) {
                Text(run("g", gw)).alignmentGuide(alignment) { _ in g }
                Text(run("s", sw))
            },
            context: makeBareRenderContext(width: 80, height: 10))
        return "VStack(\(aname)) G w=\(gw) guide=\(name(g)) | S w=\(sw) || "
            + "G.x=\(firstColumn(of: "g", in: buffer)) S.x=\(firstColumn(of: "s", in: buffer)) stack.w=\(buffer.width)"
    }

    private func hcase(_ alignment: VerticalAlignment, _ aname: String, gh: Int, sh: Int, g: Double) -> String {
        let buffer = renderToBuffer(
            HStack(alignment: alignment, spacing: 0) {
                Column(char: "g", height: gh).alignmentGuide(alignment) { _ in g }
                Column(char: "s", height: sh)
            },
            context: makeBareRenderContext(width: 20, height: 60))
        return "HStack(\(aname)) G h=\(gh) guide=\(name(g)) | S h=\(sh) || "
            + "G.y=\(firstRow(of: "g", in: buffer)) S.y=\(firstRow(of: "s", in: buffer)) stack.h=\(buffer.height)"
    }

    @Test func record() throws {
        var lines: [String] = ["== leading"]
        for gw in [1, 6, 10] {
            for sw in [6, 10] {
                for g in Self.guides { lines.append(vcase(.leading, "leading", gw: gw, sw: sw, g: g)) }
            }
        }
        lines.append("== trailing (sibling's own trailing guide = its width)")
        for gw in [1, 6] {
            for g in Self.guides { lines.append(vcase(.trailing, "trailing", gw: gw, sw: 6, g: g)) }
        }
        lines.append("== center (sibling's own center guide = width/2)")
        for gw in [1, 6] {
            for g in Self.guides { lines.append(vcase(.center, "center", gw: gw, sw: 6, g: g)) }
        }
        lines.append("== HStack top")
        for gh in [1, 6] {
            for g in Self.guides { lines.append(hcase(.top, "top", gh: gh, sh: 6, g: g)) }
        }
        lines.append("== HStack bottom")
        for g in Self.guides { lines.append(hcase(.bottom, "bottom", gh: 1, sh: 6, g: g)) }
        // Control: the trailing anchor without any out-of-extent guide — G's
        // guide at its own leading edge (0, inside [0, 1]) pokes G out past S.
        lines.append("== control: in-extent guides only")
        lines.append(vcase(.trailing, "trailing", gw: 3, sw: 6, g: 0))
        lines.append(vcase(.trailing, "trailing", gw: 3, sw: 6, g: 1))
        lines.append(vcase(.center, "center", gw: 6, sw: 6, g: -6))
        lines.append(vcase(.center, "center", gw: 6, sw: 6, g: 0))
        lines.append(hcase(.bottom, "bottom", gh: 3, sh: 6, g: 0))
        try (lines.joined(separator: "\n") + "\n").write(toFile: Self.out, atomically: true, encoding: .utf8)
    }
}
