import AppKit
import SwiftUI

// The variants of `nested.swift`'s three unmatched answers (lane TXTFG-NEST2,
// 2026-11-20), measured before TUI took them on:
//
// 1. A text's own `bold()` under a view's `.medium`, `.semibold` and `.heavy`,
//    and the neighbours: a view's `bold()` on either side of the weight, a
//    Markdown `**`, bold fragments, a regular weight between, and a text's own
//    `bold()` before its own weight. `stacked.swift`'s method ("first" is the
//    first statement alone, "last" the second alone, compared pixel for pixel).
// 2. A view's level under a view's level: each outer level, of no style, of a
//    colour, of `foregroundStyle(_:_:)`'s named level, and a concrete
//    `.red.secondary`. `levels.swift`'s method (each sample drawn real and
//    blank, the core pixel of each line read back).
// 3. A view's `.foregroundStyle(.foreground)` under no style, `.red`, a level,
//    a level of a colour, a two-style `foregroundStyle`, `foregroundColor` and
//    a tint, with a text's own level and a view's level inside it.
//
// The drawing and comparing helpers are `nested.swift`'s.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 variants.swift -o "$TMPDIR/variants"
//   "$TMPDIR/variants" | diff variants.out -


@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let scale = 3

struct Pixels {
    let width: Int, height: Int
    var rgb: [(Int, Int, Int)]
    func at(_ x: Int, _ y: Int) -> (Int, Int, Int) { rgb[y * width + x] }
}

@MainActor func bitmap<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = hosting
    w.orderFrontRegardless()
    keep.append(w)
    spin()
    hosting.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
        pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    return rep
}

@MainActor func render<V: View>(_ view: V, size: CGSize) -> Pixels {
    let rep = bitmap(view, size: size)
    var px = Pixels(width: rep.pixelsWide, height: rep.pixelsHigh, rgb: [])
    px.rgb.reserveCapacity(rep.pixelsWide * rep.pixelsHigh)
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            px.rgb.append((Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                Int((c.blueComponent * 255).rounded())))
        }
    }
    return px
}

@MainActor func pixels<V: View>(_ view: V, size: CGSize) -> [UInt8] {
    let rep = bitmap(view, size: size)
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
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
    "Text.foregroundStyle(.foreground)",
]

@MainActor func sample<V: View, B: View>(
    _ name: String, height: CGFloat, labels: [String] = rows, _ real: V, blank: B
) {
    func framed<T: View>(_ v: T) -> some View {
        v.padding(8).frame(width: 320, height: height, alignment: .topLeading).background(Color.white)
    }
    let size = CGSize(width: 320, height: height)
    let a = render(framed(real), size: size)
    let b = render(framed(blank), size: size)
    print("\(name):")
    for (i, band) in bands(a, b).enumerated() {
        print("  \(i < labels.count ? labels[i] : "?"): \(band)")
    }
}

func differing(_ a: [UInt8], _ b: [UInt8]) -> Int {
    var n = 0
    var i = 0
    while i < a.count {
        if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] { n += 1 }
        i += 4
    }
    return n
}

@MainActor func compare<A: View, B: View, C: View>(_ name: String, both: A, first: B, last: C) {
    func framed<T: View>(_ v: T) -> some View {
        v.padding(8).frame(width: 260, height: 60, alignment: .topLeading).background(Color.white)
    }
    let size = CGSize(width: 260, height: 60)
    let ab = pixels(framed(both), size: size)
    let a = pixels(framed(first), size: size)
    let b = pixels(framed(last), size: size)
    let toFirst = differing(ab, a), toLast = differing(ab, b), apart = differing(a, b)
    let verdict: String
    switch (toFirst == 0, toLast == 0) {
    case (true, true): verdict = "both (first and last draw alike)"
    case (true, false): verdict = "first"
    case (false, true): verdict = "last"
    case (false, false): verdict = "neither (\(toFirst) px from first, \(toLast) from last)"
    }
    print("\(name): \(verdict); first and last differ in \(apart) px")
}

let viewRows = [
    "VStack { Text }.foregroundStyle(.primary)", "VStack { Text }.foregroundStyle(.secondary)",
    "VStack { Text }.foregroundStyle(.tertiary)", "VStack { Text }.foregroundStyle(.quaternary)",
    "VStack { Text }.foregroundStyle(.foreground)",
]

struct ViewStack: View {
    let o: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack { Text("Primary").opacity(o) }.foregroundStyle(.primary)
            VStack { Text("Secondary").opacity(o) }.foregroundStyle(.secondary)
            VStack { Text("Tertiary").opacity(o) }.foregroundStyle(.tertiary)
            VStack { Text("Quaternary").opacity(o) }.foregroundStyle(.quaternary)
            VStack { Text("Foreground").opacity(o) }.foregroundStyle(.foreground)
        }
    }
}

let foregroundRows = [
    "VStack { Text }.foregroundStyle(.foreground)",
    "VStack { Text.foregroundStyle(.secondary) }.foregroundStyle(.foreground)",
    "VStack { VStack { Text }.foregroundStyle(.secondary) }.foregroundStyle(.foreground)",
]

struct ForegroundStack: View {
    let o: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack { Text("Foreground").opacity(o) }.foregroundStyle(.foreground)
            VStack { Text("Secondary").foregroundStyle(.secondary).opacity(o) }.foregroundStyle(.foreground)
            VStack { VStack { Text("Secondary").opacity(o) }.foregroundStyle(.secondary) }
                .foregroundStyle(.foreground)
        }
    }
}

let shapeRows = ["Rectangle().fill(.primary)", "Rectangle().fill(.secondary)", "Rectangle().fill(.tertiary)"]

struct ShapeStack: View {
    let o: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(.primary).frame(width: 60, height: 12).opacity(o)
            Rectangle().fill(.secondary).frame(width: 60, height: 12).opacity(o)
            Rectangle().fill(.tertiary).frame(width: 60, height: 12).opacity(o)
        }
    }
}

let s = "Sample text"

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            let os = ProcessInfo.processInfo.operatingSystemVersion
            print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), drawn at \(scale)x, Aqua")

            // 1. A bold against a weight.
            print("")
            let t = Text(s)
            let weights: [(String, Font.Weight)] = [
                ("regular", .regular), ("medium", .medium), ("semibold", .semibold), ("heavy", .heavy),
            ]
            for (name, weight) in weights {
                compare("{ bold() } under View.fontWeight(.\(name))",
                    both: VStack { t.bold() }.fontWeight(weight), first: t.bold(),
                    last: VStack { t }.fontWeight(weight))
            }
            compare("View.fontWeight(.medium) alone, against regular and bold",
                both: VStack { t }.fontWeight(.medium), first: t, last: t.bold())
            compare("{ bold(false) } under View.fontWeight(.medium)",
                both: VStack { t.bold(false) }.fontWeight(.medium), first: t,
                last: VStack { t }.fontWeight(.medium))
            compare("{ Text(\"**Sample text**\") } under View.fontWeight(.medium)",
                both: VStack { Text("**Sample text**") }.fontWeight(.medium), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() + bold() } under View.fontWeight(.medium)",
                both: VStack { Text("Sample ").bold() + Text("text").bold() }.fontWeight(.medium),
                first: t.bold(), last: VStack { t }.fontWeight(.medium))
            compare("VStack { Text }.bold().fontWeight(.medium)",
                both: VStack { t }.bold().fontWeight(.medium), first: VStack { t }.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("VStack { Text }.fontWeight(.medium).bold()",
                both: VStack { t }.fontWeight(.medium).bold(), first: VStack { t }.fontWeight(.medium),
                last: VStack { t }.bold())
            compare("{ fontWeight(.regular).bold() } under View.fontWeight(.medium)",
                both: VStack { t.fontWeight(.regular).bold() }.fontWeight(.medium), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.fontWeight(.medium) under View.fontWeight(.regular)",
                both: VStack { VStack { t.bold() }.fontWeight(.medium) }.fontWeight(.regular), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.fontWeight(.regular) under View.fontWeight(.medium)",
                both: VStack { VStack { t.bold() }.fontWeight(.regular) }.fontWeight(.medium), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.fontWeight(.medium) under View.bold()",
                both: VStack { VStack { t.bold() }.fontWeight(.medium) }.bold(), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.bold() under View.fontWeight(.medium)",
                both: VStack { VStack { t.bold() }.bold() }.fontWeight(.medium), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.fontWeight(.medium) under View.bold(false)",
                both: VStack { VStack { t.bold() }.fontWeight(.medium) }.bold(false), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold(false) } under View.fontWeight(.medium) under View.bold()",
                both: VStack { VStack { t.bold(false) }.fontWeight(.medium) }.bold(), first: t,
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.fontWeight(.ultraLight) under View.bold()",
                both: VStack { VStack { t.bold() }.fontWeight(.ultraLight) }.bold(), first: t.bold(),
                last: VStack { t }.fontWeight(.ultraLight))
            compare("{ bold() } under View.bold() under View.fontWeight(.ultraLight)",
                both: VStack { VStack { t.bold() }.bold() }.fontWeight(.ultraLight), first: t.bold(),
                last: VStack { t }.fontWeight(.ultraLight))
            compare("{ bold() } under View.fontWeight(.heavy) under View.bold()",
                both: VStack { VStack { t.bold() }.fontWeight(.heavy) }.bold(), first: t.bold(),
                last: VStack { t }.fontWeight(.heavy))
            compare("{ bold() } under View.fontWeight(.medium) under View.fontWeight(.heavy)",
                both: VStack { VStack { t.bold() }.fontWeight(.medium) }.fontWeight(.heavy), first: t.bold(),
                last: VStack { t }.fontWeight(.medium))
            compare("{ bold() } under View.fontWeight(.medium) under View.bold() under View.fontWeight(.ultraLight)",
                both: VStack { VStack { VStack { t.bold() }.fontWeight(.medium) }.bold() }.fontWeight(.ultraLight),
                first: t.bold(), last: VStack { t }.fontWeight(.medium))
            compare("  the same, against ultralight and semibold",
                both: VStack { VStack { VStack { t.bold() }.fontWeight(.medium) }.bold() }.fontWeight(.ultraLight),
                first: t.fontWeight(.ultraLight), last: t.fontWeight(.semibold))
            compare("  the same, against light and regular",
                both: VStack { VStack { VStack { t.bold() }.fontWeight(.medium) }.bold() }.fontWeight(.ultraLight),
                first: t.fontWeight(.light), last: t)
            compare("  the same, against thin and ultralight bold()",
                both: VStack { VStack { VStack { t.bold() }.fontWeight(.medium) }.bold() }.fontWeight(.ultraLight),
                first: t.fontWeight(.thin), last: t.fontWeight(.ultraLight).bold())
            compare("bold().fontWeight(.medium)",
                both: t.bold().fontWeight(.medium), first: t.bold(), last: t.fontWeight(.medium))
            compare("bold().fontWeight(.semibold)",
                both: t.bold().fontWeight(.semibold), first: t.bold(), last: t.fontWeight(.semibold))
            compare("bold(false).fontWeight(.medium)",
                both: t.bold(false).fontWeight(.medium), first: t, last: t.fontWeight(.medium))

            // 2. A view's level under a view's level.
            let h: CGFloat = 145
            print("")
            sample("View.foregroundStyle(.secondary)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.secondary), blank: ViewStack(o: 0).foregroundStyle(.secondary))
            sample("View.foregroundStyle(.tertiary)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.tertiary), blank: ViewStack(o: 0).foregroundStyle(.tertiary))
            sample("View.foregroundStyle(.quaternary)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.quaternary), blank: ViewStack(o: 0).foregroundStyle(.quaternary))
            sample("View.foregroundStyle(.red)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.red), blank: ViewStack(o: 0).foregroundStyle(.red))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red),
                blank: ViewStack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red))
            sample("View.foregroundStyle(.tertiary) under .foregroundStyle(.red)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.tertiary).foregroundStyle(.red),
                blank: ViewStack(o: 0).foregroundStyle(.tertiary).foregroundStyle(.red))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red, .blue)", height: h,
                labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red, .blue),
                blank: ViewStack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red, .blue))
            sample("View.foregroundStyle(.red, .blue)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.red, .blue), blank: ViewStack(o: 0).foregroundStyle(.red, .blue))
            sample("View.foregroundStyle(.red, .blue, .green)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.red, .blue, .green),
                blank: ViewStack(o: 0).foregroundStyle(.red, .blue, .green))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red, .blue, .green)", height: h,
                labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red, .blue, .green),
                blank: ViewStack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red, .blue, .green))
            sample("View.foregroundStyle(.red.secondary)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.red.secondary),
                blank: ViewStack(o: 0).foregroundStyle(.red.secondary))

            // A shape's level beside a view's, under the same outer level.
            let r: CGFloat = 80
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red)", height: r, labels: shapeRows,
                ShapeStack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red),
                blank: ShapeStack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red))
            sample("View.foregroundStyle(.secondary)", height: r, labels: shapeRows,
                ShapeStack(o: 1).foregroundStyle(.secondary), blank: ShapeStack(o: 0).foregroundStyle(.secondary))
            sample("View.foregroundStyle(.foreground) under .foregroundStyle(.red)", height: r, labels: shapeRows,
                ShapeStack(o: 1).foregroundStyle(.foreground).foregroundStyle(.red),
                blank: ShapeStack(o: 0).foregroundStyle(.foreground).foregroundStyle(.red))

            // 3. A view's `.foreground`.
            let f: CGFloat = 95
            print("")
            sample("no style", height: f, labels: foregroundRows, ForegroundStack(o: 1), blank: ForegroundStack(o: 0))
            sample("View.foregroundStyle(.red)", height: f, labels: foregroundRows,
                ForegroundStack(o: 1).foregroundStyle(.red), blank: ForegroundStack(o: 0).foregroundStyle(.red))
            sample("View.foregroundStyle(.secondary)", height: f, labels: foregroundRows,
                ForegroundStack(o: 1).foregroundStyle(.secondary),
                blank: ForegroundStack(o: 0).foregroundStyle(.secondary))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red)", height: f,
                labels: foregroundRows,
                ForegroundStack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red),
                blank: ForegroundStack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red))
            sample("View.foregroundStyle(.red, .blue)", height: f, labels: foregroundRows,
                ForegroundStack(o: 1).foregroundStyle(.red, .blue),
                blank: ForegroundStack(o: 0).foregroundStyle(.red, .blue))
            sample("View.foregroundColor(.red)", height: f, labels: foregroundRows,
                ForegroundStack(o: 1).foregroundColor(.red), blank: ForegroundStack(o: 0).foregroundColor(.red))
            sample("View.tint(.green)", height: f, labels: foregroundRows,
                ForegroundStack(o: 1).tint(.green), blank: ForegroundStack(o: 0).tint(.green))
        }
    }
}
