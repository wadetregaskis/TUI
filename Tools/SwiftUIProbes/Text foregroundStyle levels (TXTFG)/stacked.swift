import AppKit
import SwiftUI

// Which of two of a `Text`'s own modifiers of one kind wins: the one written
// first (nearer the text) or the one written last (lane TXTFG-ORDER,
// 2026-11-19). `levels.swift` found the first `foregroundStyle` winning; this
// asks the same of every `Text`-returning modifier that states something a
// second one could contradict, and of the `View` modifiers TUI also declares on
// `Text` (`lineLimit`, `truncationMode`).
//
// Each case draws three texts, each alone, at 3x off-screen, with the same
// frame: `Text(s).a.b` (both), `Text(s).a` (first) and `Text(s).b` (last). The
// probe prints which of the two single ones the stacked one's pixels equal:
// "first", "last", "both" (the two draw alike, so the case says nothing) or
// "neither" (it composes them), with the share of pixels that differ.
//
// A custom attribute draws nothing, so its case reads the run's attribute back
// with a `TextRenderer` instead.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 stacked.swift -o "$TMPDIR/stacked"
//   "$TMPDIR/stacked" | diff stacked.out -

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let scale = 3

@MainActor func pixels<V: View>(_ view: V, size: CGSize) -> [UInt8] {
    let hosting = NSHostingView(rootView: view)
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
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
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

@MainActor func compare<A: View, B: View, C: View>(
    _ name: String, width: CGFloat = 260, height: CGFloat = 60, both: A, first: B, last: C
) {
    func framed<T: View>(_ v: T) -> some View {
        v.padding(8).frame(width: width, height: height, alignment: .topLeading).background(Color.white)
    }
    let size = CGSize(width: width, height: height)
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

/// Whether `sample` draws exactly as `reference`.
@MainActor func same<A: View, B: View>(_ name: String, _ sample: A, as reference: B, referenceName: String) {
    func framed<T: View>(_ v: T) -> some View {
        v.padding(8).frame(width: 260, height: 60, alignment: .topLeading).background(Color.white)
    }
    let size = CGSize(width: 260, height: 60)
    let n = differing(pixels(framed(sample), size: size), pixels(framed(reference), size: size))
    print("\(name) draws \(n == 0 ? "exactly as" : "unlike (\(n) px)") \(referenceName)")
}

struct Tag: TextAttribute { let value: String }

struct TagReader: TextRenderer {
    let report: (String) -> Void
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                report(run[Tag.self]?.value ?? "none")
                context.draw(run)
            }
        }
    }
}

let s = "Sample text"
let long = "One two three four five six seven eight nine ten eleven twelve thirteen fourteen"

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            let os = ProcessInfo.processInfo.operatingSystemVersion
            print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), drawn at \(scale)x, Aqua")
            print("")
            let t = Text(s)
            compare("foregroundColor(.red).foregroundColor(.blue)",
                both: t.foregroundColor(.red).foregroundColor(.blue), first: t.foregroundColor(.red),
                last: t.foregroundColor(.blue))
            compare("foregroundColor(nil).foregroundColor(.blue)",
                both: t.foregroundColor(nil).foregroundColor(.blue), first: t.foregroundColor(nil),
                last: t.foregroundColor(.blue))
            compare("foregroundColor(.red).foregroundStyle(.blue)",
                both: t.foregroundColor(.red).foregroundStyle(.blue), first: t.foregroundColor(.red),
                last: t.foregroundStyle(.blue))
            compare("foregroundStyle(.red).foregroundColor(.blue)",
                both: t.foregroundStyle(.red).foregroundColor(.blue), first: t.foregroundStyle(.red),
                last: t.foregroundColor(.blue))
            compare("foregroundStyle(.red).foregroundStyle(.blue)",
                both: t.foregroundStyle(.red).foregroundStyle(.blue), first: t.foregroundStyle(.red),
                last: t.foregroundStyle(.blue))
            compare("foregroundStyle(gradient).foregroundStyle(.blue)",
                both: t.foregroundStyle(LinearGradient(colors: [.red, .green], startPoint: .leading,
                    endPoint: .trailing)).foregroundStyle(.blue),
                first: t.foregroundStyle(LinearGradient(colors: [.red, .green], startPoint: .leading,
                    endPoint: .trailing)),
                last: t.foregroundStyle(.blue))
            compare("foregroundStyle(.blue).foregroundStyle(gradient)",
                both: t.foregroundStyle(.blue).foregroundStyle(LinearGradient(colors: [.red, .green],
                    startPoint: .leading, endPoint: .trailing)),
                first: t.foregroundStyle(.blue),
                last: t.foregroundStyle(LinearGradient(colors: [.red, .green], startPoint: .leading,
                    endPoint: .trailing)))
            compare("(Text + Text).foregroundStyle(.red).foregroundStyle(.blue)",
                both: (Text("Sample ") + Text("text")).foregroundStyle(.red).foregroundStyle(.blue),
                first: (Text("Sample ") + Text("text")).foregroundStyle(.red),
                last: (Text("Sample ") + Text("text")).foregroundStyle(.blue))
            compare("font(.title).font(.caption)",
                both: t.font(.title).font(.caption), first: t.font(.title), last: t.font(.caption))
            compare("font(nil).font(.title)",
                both: t.font(nil).font(.title), first: t.font(nil), last: t.font(.title))
            compare("font(.title).font(nil)",
                both: t.font(.title).font(nil), first: t.font(.title), last: t.font(nil))
            compare("fontWeight(.heavy).fontWeight(.ultraLight)",
                both: t.fontWeight(.heavy).fontWeight(.ultraLight), first: t.fontWeight(.heavy),
                last: t.fontWeight(.ultraLight))
            compare("fontWeight(nil).fontWeight(.heavy)",
                both: t.fontWeight(nil).fontWeight(.heavy), first: t.fontWeight(nil),
                last: t.fontWeight(.heavy))
            compare("fontWeight(.heavy).fontWeight(nil)",
                both: t.fontWeight(.heavy).fontWeight(nil), first: t.fontWeight(.heavy),
                last: t.fontWeight(nil))
            compare("bold(true).bold(false)", both: t.bold(true).bold(false), first: t.bold(true),
                last: t.bold(false))
            compare("bold(false).bold(true)", both: t.bold(false).bold(true), first: t.bold(false),
                last: t.bold(true))
            compare("bold().fontWeight(.ultraLight)", both: t.bold().fontWeight(.ultraLight), first: t.bold(),
                last: t.fontWeight(.ultraLight))
            compare("fontWeight(.ultraLight).bold()", both: t.fontWeight(.ultraLight).bold(),
                first: t.fontWeight(.ultraLight), last: t.bold())
            compare("bold(false).fontWeight(.heavy)", both: t.bold(false).fontWeight(.heavy), first: t.bold(false),
                last: t.fontWeight(.heavy))
            compare("fontWeight(.heavy).bold(false)", both: t.fontWeight(.heavy).bold(false),
                first: t.fontWeight(.heavy), last: t.bold(false))
            compare("bold(false).fontWeight(.ultraLight)", both: t.bold(false).fontWeight(.ultraLight),
                first: t.bold(false), last: t.fontWeight(.ultraLight))
            compare("fontWeight(.ultraLight).bold(false)", both: t.fontWeight(.ultraLight).bold(false),
                first: t.fontWeight(.ultraLight), last: t.bold(false))
            compare("bold(true).fontWeight(.regular)", both: t.bold(true).fontWeight(.regular),
                first: t.bold(true), last: t.fontWeight(.regular))
            compare("fontWeight(.regular).bold(true)", both: t.fontWeight(.regular).bold(true),
                first: t.fontWeight(.regular), last: t.bold(true))
            compare("bold(true).fontWeight(nil)", both: t.bold(true).fontWeight(nil),
                first: t.bold(true), last: t.fontWeight(nil))
            compare("fontWeight(nil).bold(true)", both: t.fontWeight(nil).bold(true),
                first: t.fontWeight(nil), last: t.bold(true))
            compare("font(.body.bold()).fontWeight(.regular)", both: t.font(.body.bold()).fontWeight(.regular),
                first: t.font(.body.bold()), last: t.font(.body).fontWeight(.regular))
            compare("font(.body.bold()).fontWeight(nil)", both: t.font(.body.bold()).fontWeight(nil),
                first: t.font(.body.bold()), last: t)
            compare("fontWeight(.heavy).font(.title)", both: t.fontWeight(.heavy).font(.title),
                first: t.fontWeight(.heavy), last: t.font(.title))
            compare("italic(true).italic(false)", both: t.italic(true).italic(false), first: t.italic(true),
                last: t.italic(false))
            compare("italic(false).italic(true)", both: t.italic(false).italic(true), first: t.italic(false),
                last: t.italic(true))
            compare("underline(true).underline(false)", both: t.underline(true).underline(false),
                first: t.underline(true), last: t.underline(false))
            compare("underline(false).underline(true)", both: t.underline(false).underline(true),
                first: t.underline(false), last: t.underline(true))
            compare("underline(color: .red).underline(color: .blue)",
                both: t.underline(color: .red).underline(color: .blue), first: t.underline(color: .red),
                last: t.underline(color: .blue))
            compare("underline(pattern: .dot).underline(pattern: .solid)",
                both: t.underline(pattern: .dot).underline(pattern: .solid), first: t.underline(pattern: .dot),
                last: t.underline(pattern: .solid))
            compare("strikethrough(true).strikethrough(false)", both: t.strikethrough(true).strikethrough(false),
                first: t.strikethrough(true), last: t.strikethrough(false))
            compare("strikethrough(false).strikethrough(true)", both: t.strikethrough(false).strikethrough(true),
                first: t.strikethrough(false), last: t.strikethrough(true))
            compare("strikethrough(color: .red).strikethrough(color: .blue)",
                both: t.strikethrough(color: .red).strikethrough(color: .blue),
                first: t.strikethrough(color: .red), last: t.strikethrough(color: .blue))
            compare("textScale(.secondary).textScale(.default)",
                both: t.textScale(.secondary).textScale(.default), first: t.textScale(.secondary),
                last: t.textScale(.default))
            compare("textScale(.default).textScale(.secondary)",
                both: t.textScale(.default).textScale(.secondary), first: t.textScale(.default),
                last: t.textScale(.secondary))
            compare("monospaced(true).monospaced(false)", both: t.monospaced(true).monospaced(false),
                first: t.monospaced(true), last: t.monospaced(false))
            compare("monospaced(false).monospaced(true)", both: t.monospaced(false).monospaced(true),
                first: t.monospaced(false), last: t.monospaced(true))
            compare("fontDesign(.serif).fontDesign(.monospaced)",
                both: t.fontDesign(.serif).fontDesign(.monospaced), first: t.fontDesign(.serif),
                last: t.fontDesign(.monospaced))
            compare("fontWidth(.compressed).fontWidth(.expanded)",
                both: t.fontWidth(.compressed).fontWidth(.expanded), first: t.fontWidth(.compressed),
                last: t.fontWidth(.expanded))
            compare("kerning(6).kerning(0)", both: t.kerning(6).kerning(0), first: t.kerning(6), last: t.kerning(0))
            compare("tracking(6).tracking(0)", both: t.tracking(6).tracking(0), first: t.tracking(6),
                last: t.tracking(0))
            compare("baselineOffset(8).baselineOffset(0)", both: t.baselineOffset(8).baselineOffset(0),
                first: t.baselineOffset(8), last: t.baselineOffset(0))
            // View modifiers, which TUI also declares on `Text`.
            compare("lineLimit(1).lineLimit(3)", width: 200, height: 120,
                both: Text(long).lineLimit(1).lineLimit(3), first: Text(long).lineLimit(1),
                last: Text(long).lineLimit(3))
            compare("truncationMode(.head).truncationMode(.tail)", width: 200, height: 40,
                both: Text(long).lineLimit(1).truncationMode(.head).truncationMode(.tail),
                first: Text(long).lineLimit(1).truncationMode(.head),
                last: Text(long).lineLimit(1).truncationMode(.tail))

            // A level written first is a level of the style written after it
            // (`levels.out` read #7FBBFF for blue): is it exactly that style's
            // own level, for a colour, the tint and a gradient?
            print("")
            let ramp = LinearGradient(colors: [.red, .green], startPoint: .leading, endPoint: .trailing)
            same("foregroundStyle(.secondary).foregroundStyle(.blue)",
                t.foregroundStyle(.secondary).foregroundStyle(.blue), as: t.foregroundStyle(Color.blue.secondary),
                referenceName: "foregroundStyle(Color.blue.secondary)")
            same("foregroundStyle(.tertiary).foregroundStyle(.blue)",
                t.foregroundStyle(.tertiary).foregroundStyle(.blue), as: t.foregroundStyle(Color.blue.tertiary),
                referenceName: "foregroundStyle(Color.blue.tertiary)")
            same("foregroundStyle(.secondary).foregroundStyle(.tint) under .tint(.green)",
                VStack { t.foregroundStyle(.secondary).foregroundStyle(.tint) }.tint(.green),
                as: t.foregroundStyle(Color.green.secondary), referenceName: "foregroundStyle(Color.green.secondary)")
            same("foregroundStyle(.secondary).foregroundStyle(gradient)",
                t.foregroundStyle(.secondary).foregroundStyle(ramp), as: t.foregroundStyle(ramp.secondary),
                referenceName: "foregroundStyle(gradient.secondary)")
            same("foregroundStyle(.secondary).foregroundStyle(gradient)",
                t.foregroundStyle(.secondary).foregroundStyle(ramp), as: t.foregroundStyle(ramp),
                referenceName: "foregroundStyle(gradient)")

            // A text's own statement against the same kind stated by a view
            // above it: "first" is the text's own, "last" the view's alone.
            print("")
            compare("{ fontWeight(nil) } under View.fontWeight(.heavy)",
                both: VStack { t.fontWeight(nil) }.fontWeight(.heavy), first: t,
                last: VStack { t }.fontWeight(.heavy))
            compare("{ fontWeight(nil) } under View.font(.body.bold())",
                both: VStack { t.fontWeight(nil) }.font(.body.bold()), first: t,
                last: VStack { t }.font(.body.bold()))
            compare("{ fontWeight(nil) } under View.bold()",
                both: VStack { t.fontWeight(nil) }.bold(), first: t, last: VStack { t }.bold())
            compare("{ fontWeight(.regular) } under View.font(.body.bold())",
                both: VStack { t.fontWeight(.regular) }.font(.body.bold()), first: t,
                last: VStack { t }.font(.body.bold()))
            compare("{ font(nil) } under View.font(.title)",
                both: VStack { t.font(nil) }.font(.title), first: t, last: VStack { t }.font(.title))
            compare("{ bold(false) } under View.bold()",
                both: VStack { t.bold(false) }.bold(), first: t, last: VStack { t }.bold())
            compare("{ bold(false) } under View.fontWeight(.heavy)",
                both: VStack { t.bold(false) }.fontWeight(.heavy), first: t, last: VStack { t }.fontWeight(.heavy))
            compare("{ bold() } under View.fontWeight(.ultraLight)",
                both: VStack { t.bold() }.fontWeight(.ultraLight), first: t.bold(),
                last: VStack { t }.fontWeight(.ultraLight))
            compare("{ fontWeight(.ultraLight) } under View.bold()",
                both: VStack { t.fontWeight(.ultraLight) }.bold(), first: t.fontWeight(.ultraLight),
                last: VStack { t }.bold())
            compare("{ foregroundColor(nil) } under View.foregroundStyle(.red)",
                both: VStack { t.foregroundColor(nil) }.foregroundStyle(.red), first: t,
                last: VStack { t }.foregroundStyle(.red))
            compare("{ italic(false) } under View.italic()",
                both: VStack { t.italic(false) }.italic(), first: t, last: VStack { t }.italic())
            compare("{ underline(false) } under View.underline()",
                both: VStack { t.underline(false) }.underline(), first: t, last: VStack { t }.underline())

            print("")
            var seen: [String] = []
            let reader = TagReader { seen.append($0) }
            _ = pixels(Text(s).customAttribute(Tag(value: "first")).customAttribute(Tag(value: "last"))
                .textRenderer(reader).padding(8).background(Color.white), size: CGSize(width: 200, height: 40))
            print("customAttribute(Tag(first)).customAttribute(Tag(last)): the runs' Tags read \(seen)")
            seen = []
            _ = pixels((Text("Sample ").customAttribute(Tag(value: "fragment")) + Text("text"))
                .customAttribute(Tag(value: "whole")).textRenderer(reader).padding(8).background(Color.white),
                size: CGSize(width: 200, height: 40))
            print("(Text(a).customAttribute(Tag(fragment)) + Text(b)).customAttribute(Tag(whole)): the runs' Tags read \(seen)")
        }
    }
}
