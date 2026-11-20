import AppKit
import SwiftUI

// Two follow-ups to `levels.swift` and `stacked.swift` (lane TXTFG-NEST,
// 2026-11-19), both a text's own statement against what a view states above it.
//
// 1. A content level under a view's content level. `levels.out` found a text's
//    own levels under a view's `.foregroundStyle(.secondary)` drawing as with no
//    style. This asks what they are levels of when that view's level is itself
//    under a colour or a two-style `foregroundStyle`, and what a view's level
//    under a view's level draws. The method is `levels.swift`'s: each sample
//    drawn real and blank, the core pixel of each line read back.
// 2. A text's own `bold()` under each view `fontWeight`, and the cases beside
//    it (a Markdown `**`, a caption, a view's `bold()`). The method is
//    `stacked.swift`'s: the sample compared pixel for pixel with the text's own
//    statement alone ("first") and the view's alone ("last").
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 nested.swift -o "$TMPDIR/nested"
//   "$TMPDIR/nested" | diff nested.out -

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

struct Stack: View {
    let o: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Primary").foregroundStyle(.primary).opacity(o)
            Text("Secondary").foregroundStyle(.secondary).opacity(o)
            Text("Tertiary").foregroundStyle(.tertiary).opacity(o)
            Text("Foreground").foregroundStyle(.foreground).opacity(o)
        }
    }
}

let viewRows = [
    "VStack { Text }.foregroundStyle(.primary)", "VStack { Text }.foregroundStyle(.secondary)",
    "VStack { Text }.foregroundStyle(.tertiary)", "VStack { Text }.foregroundStyle(.foreground)",
]

struct ViewStack: View {
    let o: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack { Text("Primary").opacity(o) }.foregroundStyle(.primary)
            VStack { Text("Secondary").opacity(o) }.foregroundStyle(.secondary)
            VStack { Text("Tertiary").opacity(o) }.foregroundStyle(.tertiary)
            VStack { Text("Foreground").opacity(o) }.foregroundStyle(.foreground)
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
            let h: CGFloat = 120
            print("")
            sample("View.foregroundStyle(.secondary)", height: h,
                Stack(o: 1).foregroundStyle(.secondary), blank: Stack(o: 0).foregroundStyle(.secondary))
            sample("View.foregroundStyle(.tertiary)", height: h,
                Stack(o: 1).foregroundStyle(.tertiary), blank: Stack(o: 0).foregroundStyle(.tertiary))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red)", height: h,
                Stack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red),
                blank: Stack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red, .blue)", height: h,
                Stack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red, .blue),
                blank: Stack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red, .blue))
            sample("View.foregroundStyle(.red) under View.foregroundStyle(.secondary)", height: h,
                Stack(o: 1).foregroundStyle(.red).foregroundStyle(.secondary),
                blank: Stack(o: 0).foregroundStyle(.red).foregroundStyle(.secondary))
            print("")
            sample("no style", height: h, labels: viewRows, ViewStack(o: 1), blank: ViewStack(o: 0))
            sample("View.foregroundStyle(.secondary)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.secondary), blank: ViewStack(o: 0).foregroundStyle(.secondary))
            sample("View.foregroundStyle(.secondary) under .foregroundStyle(.red)", height: h, labels: viewRows,
                ViewStack(o: 1).foregroundStyle(.secondary).foregroundStyle(.red),
                blank: ViewStack(o: 0).foregroundStyle(.secondary).foregroundStyle(.red))

            // A text's own bold against a view's weight above it: "first" is
            // the text's own alone, "last" the view's alone.
            print("")
            let t = Text(s)
            let weights: [(String, Font.Weight)] = [
                ("ultraLight", .ultraLight), ("thin", .thin), ("light", .light), ("regular", .regular),
                ("medium", .medium), ("semibold", .semibold), ("heavy", .heavy),
            ]
            for (name, weight) in weights {
                compare("{ bold() } under View.fontWeight(.\(name))",
                    both: VStack { t.bold() }.fontWeight(weight), first: t.bold(),
                    last: VStack { t }.fontWeight(weight))
            }
            compare("{ bold(false) } under View.fontWeight(.ultraLight)",
                both: VStack { t.bold(false) }.fontWeight(.ultraLight), first: t,
                last: VStack { t }.fontWeight(.ultraLight))
            compare("{ Text(\"**Sample text**\") } under View.fontWeight(.ultraLight)",
                both: VStack { Text("**Sample text**") }.fontWeight(.ultraLight), first: t.bold(),
                last: VStack { t }.fontWeight(.ultraLight))
            compare("{ bold() + bold() } under View.fontWeight(.ultraLight)",
                both: VStack { Text("Sample ").bold() + Text("text").bold() }.fontWeight(.ultraLight),
                first: t.bold(), last: VStack { t }.fontWeight(.ultraLight))
            compare("{ bold() } under View.font(.caption).fontWeight(.ultraLight)",
                both: VStack { t.bold() }.font(.caption).fontWeight(.ultraLight), first: t.bold().font(.caption),
                last: VStack { t }.font(.caption).fontWeight(.ultraLight))
            compare("{ bold() } under View.bold(false)",
                both: VStack { t.bold() }.bold(false), first: t.bold(), last: t)
            compare("VStack { Text }.bold().fontWeight(.ultraLight)",
                both: VStack { t }.bold().fontWeight(.ultraLight), first: VStack { t }.bold(),
                last: VStack { t }.fontWeight(.ultraLight))
            compare("VStack { Text }.fontWeight(.ultraLight).bold()",
                both: VStack { t }.fontWeight(.ultraLight).bold(), first: VStack { t }.fontWeight(.ultraLight),
                last: VStack { t }.bold())
        }
    }
}
