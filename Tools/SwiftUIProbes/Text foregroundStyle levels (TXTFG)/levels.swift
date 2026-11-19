import AppKit
import SwiftUI

// What a `Text`'s own hierarchical style resolves against (lane TXTFG,
// 2026-11-19). The method is the 1119 probe's (`ink.swift` in "Disabled editor
// ink and toggle subtitles (1119)", on the review-fixes branch): each sample is
// drawn twice with the same layout, real and with every text at opacity 0, and
// per line of text the probe prints the CORE pixel, the one farthest from the
// blank render's pixel under it, as 8-bit sRGB, over that background pixel.
//
// The stack is seven lines, each a `Text` styled by `Text`'s own
// `foregroundStyle(_:) -> Text`: `.primary`, `.secondary`, `.tertiary`,
// `.quaternary`; a concatenation whose first run is `.clear` and whose second
// is `.secondary` (so the line's ink is the second run's alone); then `.tint`
// and `.foreground`, two styles that are neither a colour nor a level. It is
// drawn under no style, `.red`, `(.red, .blue)`, `(.red, .blue, .green)`, a
// view's `.foregroundStyle(.secondary)` and `(.red.secondary)`, and
// `.tint(.green)`. Calibration swatches give the sRGB of the colours and levels
// over white.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 levels.swift -o "$TMPDIR/levels"
//   "$TMPDIR/levels" | diff levels.out -

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let scale = 3

struct Pixels {
    let width: Int, height: Int
    var rgb: [(Int, Int, Int)]
    func at(_ x: Int, _ y: Int) -> (Int, Int, Int) { rgb[y * width + x] }
}

@MainActor func render<V: View>(_ view: V, size: CGSize) -> (Pixels, NSView) {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = hosting
    w.orderFrontRegardless()
    keep.append(w)
    spin()
    hosting.layoutSubtreeIfNeeded()
    let pw = Int(size.width) * scale, ph = Int(size.height) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)!
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    var px = Pixels(width: pw, height: ph, rgb: [])
    px.rgb.reserveCapacity(pw * ph)
    for y in 0..<ph {
        for x in 0..<pw {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            px.rgb.append((Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                Int((c.blueComponent * 255).rounded())))
        }
    }
    return (px, hosting)
}

func hex(_ c: (Int, Int, Int)) -> String { String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
func dist(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

/// The text's bands: rows where `real` differs from `blank`, grouped.
func bands(_ real: Pixels, _ blank: Pixels) -> [String] {
    var rowsWithInk: [Int: (count: Int, core: (Int, Int, Int), bg: (Int, Int, Int), d: Int)] = [:]
    for y in 0..<real.height {
        var count = 0, best = -1
        var core = (0, 0, 0), bg = (0, 0, 0)
        for x in 0..<real.width {
            let a = real.at(x, y), b = blank.at(x, y)
            let d = dist(a, b)
            guard d > 12 else { continue }
            count += 1
            if d > best { best = d; core = a; bg = b }
        }
        if count > 0 { rowsWithInk[y] = (count, core, bg, best) }
    }
    var out: [String] = []
    var y = 0
    while y < real.height {
        guard rowsWithInk[y] != nil else { y += 1; continue }
        let start = y
        var count = 0, best = -1
        var core = (0, 0, 0), bg = (0, 0, 0)
        while let row = rowsWithInk[y] {
            count += row.count
            if row.d > best { best = row.d; core = row.core; bg = row.bg }
            y += 1
        }
        // A band of a few pixel rows is antialiasing between two lines, not a line.
        guard y - start >= 2 * scale else { continue }
        out.append("y=\(start / scale)...\((y - 1) / scale) n=\(count) core=\(hex(core)) over \(hex(bg))")
    }
    return out
}

let rows = [
    "Text.foregroundStyle(.primary)", "Text.foregroundStyle(.secondary)", "Text.foregroundStyle(.tertiary)",
    "Text.foregroundStyle(.quaternary)", "Text(clear) + Text.foregroundStyle(.secondary)",
    "Text.foregroundStyle(.tint)", "Text.foregroundStyle(.foreground)",
]

@MainActor func sample<V: View, B: View>(
    _ name: String, height: CGFloat, labels: [String] = rows, _ real: V, blank: B
) {
    func framed<T: View>(_ v: T) -> some View {
        v.padding(8).frame(width: 320, height: height, alignment: .topLeading).background(Color.white)
    }
    let size = CGSize(width: 320, height: height)
    let (a, _) = render(framed(real), size: size)
    let (b, _) = render(framed(blank), size: size)
    print("\(name):")
    for (i, band) in bands(a, b).enumerated() {
        print("  \(i < labels.count ? labels[i] : "?"): \(band)")
    }
}

@MainActor func swatch(_ name: String, _ style: some ShapeStyle) {
    let (a, _) = render(Rectangle().fill(style).frame(width: 20, height: 20).padding(10).background(Color.white),
        size: CGSize(width: 40, height: 40))
    print("swatch \(name) over white: \(hex(a.at(20 * scale, 20 * scale)))")
}

struct Stack: View {
    let o: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Primary").foregroundStyle(.primary).opacity(o)
            Text("Secondary").foregroundStyle(.secondary).opacity(o)
            Text("Tertiary").foregroundStyle(.tertiary).opacity(o)
            Text("Quaternary").foregroundStyle(.quaternary).opacity(o)
            (Text("Plain ").foregroundStyle(.clear) + Text("secondary").foregroundStyle(.secondary)).opacity(o)
            Text("Tint").foregroundStyle(.tint).opacity(o)
            Text("Foreground").foregroundStyle(.foreground).opacity(o)
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            let os = ProcessInfo.processInfo.operatingSystemVersion
            print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), drawn at \(scale)x, Aqua")
            swatch(".red", Color.red)
            swatch(".blue", Color.blue)
            swatch(".green", Color.green)
            swatch(".accentColor", Color.accentColor)
            swatch(".primary", HierarchicalShapeStyle.primary)
            swatch(".secondary", HierarchicalShapeStyle.secondary)
            swatch(".tertiary", HierarchicalShapeStyle.tertiary)
            swatch(".quaternary", HierarchicalShapeStyle.quaternary)
            swatch(".red.secondary", Color.red.secondary)
            swatch(".red.tertiary", Color.red.tertiary)
            swatch(".red.quaternary", Color.red.quaternary)
            swatch(".blue.secondary", Color.blue.secondary)
            swatch(".green.secondary", Color.green.secondary)
            swatch(".secondary.secondary", HierarchicalShapeStyle.secondary.secondary)
            let h: CGFloat = 200
            print("")
            sample("no style", height: h, Stack(o: 1), blank: Stack(o: 0))
            sample(".foregroundStyle(.red)", height: h,
                Stack(o: 1).foregroundStyle(.red), blank: Stack(o: 0).foregroundStyle(.red))
            sample(".foregroundStyle(.red, .blue)", height: h,
                Stack(o: 1).foregroundStyle(.red, .blue), blank: Stack(o: 0).foregroundStyle(.red, .blue))
            sample(".foregroundStyle(.red, .blue, .green)", height: h,
                Stack(o: 1).foregroundStyle(.red, .blue, .green),
                blank: Stack(o: 0).foregroundStyle(.red, .blue, .green))
            sample("View.foregroundStyle(.secondary)", height: h,
                Stack(o: 1).foregroundStyle(.secondary), blank: Stack(o: 0).foregroundStyle(.secondary))
            sample("View.foregroundStyle(.red.secondary)", height: h,
                Stack(o: 1).foregroundStyle(.red.secondary), blank: Stack(o: 0).foregroundStyle(.red.secondary))
            sample(".tint(.green)", height: h, Stack(o: 1).tint(.green), blank: Stack(o: 0).tint(.green))

            // Which of two of `Text`'s own styles wins: the one written first
            // (nearer the text) or the one written last.
            print("")
            let twice = [
                "Text.foregroundStyle(.red).foregroundStyle(.blue)",
                "Text.foregroundStyle(.secondary).foregroundStyle(.blue)",
                "Text.foregroundStyle(.blue).foregroundStyle(.secondary)",
                "Text.foregroundStyle(.tint).foregroundStyle(.blue)",
                "Text.foregroundStyle(.blue).foregroundStyle(.tint)",
            ]
            func twiceStack(_ o: Double) -> some View {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Red, blue").foregroundStyle(.red).foregroundStyle(.blue).opacity(o)
                    Text("Secondary, blue").foregroundStyle(.secondary).foregroundStyle(.blue).opacity(o)
                    Text("Blue, secondary").foregroundStyle(.blue).foregroundStyle(.secondary).opacity(o)
                    Text("Tint, blue").foregroundStyle(.tint).foregroundStyle(.blue).opacity(o)
                    Text("Blue, tint").foregroundStyle(.blue).foregroundStyle(.tint).opacity(o)
                }
            }
            sample("Two of Text's own styles, under .foregroundStyle(.red) and .tint(.green)", height: 150,
                labels: twice, twiceStack(1).foregroundStyle(.red).tint(.green),
                blank: twiceStack(0).foregroundStyle(.red).tint(.green))
        }
    }
}
