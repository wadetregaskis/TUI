import AppKit
import SwiftUI

// Whether a trait written on a view survives a wrapper written after it, for
// the wrappers bug hunt H-63 (FMOD-3) names: `.overlay { }`, `.background { }`,
// `.contextMenu { }`, `.clipped()`, `.clipShape(_:)` and `.mask { }`, with no
// wrapper and `.padding(0)` (already measured to keep a z-index) as controls.
//
//   z-index   `ZStack { Color.red.zIndex(1).<wrapper>; Color.green }`, 100 × 100:
//             the colour at a point the overlay's dot does not reach says which
//             layer is on top. Green without the z-index.
//   list tag  `List(selection:)` of `Text(…).tag(n).<wrapper>` rows, the
//             selection 2: the row the table shows selected, then the selection
//             after the table selects its first row. Untagged rows are the
//             control: no row shows the selection.
//   badge     `List { Text("Inbox").badge(7).<wrapper>; Text("Plain") }`: inked
//             pixels in each row's right 70 points (the badge's place); the
//             second row has no badge, so its count is the blank one.
//   spacing   `HStack { box; Spacer(minLength: 0).<wrapper>; box }.fixedSize()`:
//             its width says whether the spacer's preference of no spacing
//             reaches the row through the wrapper.
//   priority  `.layoutPriority(1).<wrapper>` on the first of two 20-character
//             texts in 30 characters: 20 and 10 where it counts, 15 and 15 not.
//   picker    a `.menu` `Picker` of `Text(…).tag(n).<wrapper>` options, the
//             selection 2: the pop-up's selected item, then the selection after
//             choosing the first item. Untagged options are the control.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 common.swift traits.swift -o "$TMPDIR/traits"
//   "$TMPDIR/traits"

@MainActor func colour(_ h: NSView, at p: CGPoint) -> String {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return "no rep" }
    h.cacheDisplay(in: h.bounds, to: rep)
    let sx = Double(rep.pixelsWide) / Double(h.bounds.width)
    let sy = Double(rep.pixelsHigh) / Double(h.bounds.height)
    guard let c = rep.colorAt(x: Int(p.x * sx), y: Int(p.y * sy))?.usingColorSpace(.sRGB) else { return "none" }
    let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
    if r > 0.8 && g < 0.4 && b < 0.4 { return "red" }
    if g > 0.6 && r < 0.4 && b < 0.5 { return "green" }
    return String(format: "rgb(%.2f, %.2f, %.2f)", r, g, b)
}

@MainActor func zIndexCase(_ w: Wrap, zIndex: Double = 1) {
    let h = host(
        ZStack {
            Color.red.zIndex(zIndex).wrapped(w)
            Color.green
        }.frame(width: 100, height: 100),
        size: CGSize(width: 100, height: 100))
    spin(0.3)
    let name = zIndex == 0 ? "no z-index" : ".zIndex(1)\(w == .none ? "" : "." + w.rawValue.dropFirst())"
    print("z-index  \(label(name)) on top: \(colour(h, at: CGPoint(x: 85, y: 85)))")
}

@MainActor var measuredWidths: [String: CGFloat] = [:]

extension View {
    /// Records the width this view was given, under `name`.
    func measured(_ name: String) -> some View {
        background(GeometryReader { p in
            let w = p.size.width
            let _ = MainActor.assumeIsolated { measuredWidths[name] = w }
            Color.clear
        })
    }
}

/// `HStack { box; Spacer(minLength: 0).<wrapper>; box }.fixedSize()`: how wide,
/// so the gaps the spacer's spacing preference leaves on each side (none, for a
/// bare spacer) against the default between two boxes.
@MainActor func spacingCase(_ w: Wrap) {
    measuredWidths = [:]
    let box = Color.gray.frame(width: 10, height: 10)
    _ = host(
        HStack { box; Spacer(minLength: 0).wrapped(w); box }.fixedSize().measured("row"),
        size: CGSize(width: 200, height: 40))
    spin(0.2)
    print("spacing  \(label("Spacer(minLength: 0)" + (w == .none ? "" : "." + w.rawValue.dropFirst()), 44)) row of two 10-pt boxes is \(measuredWidths["row"].map { "\($0)" } ?? "?") pt")
}

/// The control: a zero-wide view that states no spacing between the boxes, so
/// the row's width is the default gap twice over.
@MainActor func spacingControl() {
    measuredWidths = [:]
    let box = Color.gray.frame(width: 10, height: 10)
    _ = host(
        HStack { box; Color.clear.frame(width: 0); box }.fixedSize().measured("row"),
        size: CGSize(width: 200, height: 40))
    spin(0.2)
    print("spacing  \(label("Color.clear.frame(width: 0) (control)", 44)) row of two 10-pt boxes is \(measuredWidths["row"].map { "\($0)" } ?? "?") pt")
}

/// `HStack(spacing: 0) { Text(20 a).layoutPriority(1).<wrapper>; Text(20 b) }`
/// in 30 characters' width: the widths each text was given, in characters
/// (20 and 10 where the priority counts, 15 and 15 where it is lost).
@MainActor func priorityCase(_ w: Wrap) {
    measuredWidths = [:]
    let font = Font.system(size: 20, design: .monospaced)
    let advance = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular).maximumAdvancement.width
    _ = host(
        HStack(spacing: 0) {
            Text(String(repeating: "a", count: 20)).lineLimit(1).layoutPriority(1).wrapped(w).measured("a")
            Text(String(repeating: "b", count: 20)).lineLimit(1).measured("b")
        }.font(font).frame(width: 30 * advance),
        size: CGSize(width: 30 * advance + 40, height: 60))
    spin(0.2)
    let a = measuredWidths["a"].map { String(format: "%.1f", $0 / advance) } ?? "?"
    let b = measuredWidths["b"].map { String(format: "%.1f", $0 / advance) } ?? "?"
    print("priority \(label(w.rawValue)) a=\(a) b=\(b) characters")
}

@MainActor var listSelection: Int? = 2

struct ListCase: View {
    let wrap: Wrap
    var tagged = true
    var body: some View {
        List(selection: Binding(get: { listSelection }, set: { listSelection = $0 })) {
            if tagged {
                Text("One").tag(1).wrapped(wrap)
                Text("Two").tag(2).wrapped(wrap)
                Text("Three").tag(3).wrapped(wrap)
            } else {
                Text("One")
                Text("Two")
                Text("Three")
            }
        }
    }
}

@MainActor func listTagCase(_ w: Wrap, tagged: Bool = true) async {
    listSelection = 2
    let h = host(ListCase(wrap: w, tagged: tagged), size: CGSize(width: 300, height: 200))
    try? await Task.sleep(for: .milliseconds(400))
    guard let t = subviews(of: h, NSTableView.self).first, let window = h.window else {
        print("list tag \(label(w.rawValue)) no table"); return
    }
    let shown = t.selectedRowIndexes.map(String.init).joined(separator: ",")
    t.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try? await Task.sleep(for: .milliseconds(400))
    let after = listSelection.map(String.init) ?? "nil"
    let name = tagged ? w.rawValue : "untagged rows (control)"
    print("list tag \(label(name)) selection 2 shows row [\(shown)]; select row 0 -> selection \(after)")
    window.orderOut(nil)
}

@MainActor func badgeCase(_ w: Wrap) {
    let h = host(
        List {
            Text("Inbox").badge(7).wrapped(w)
            Text("Plain")
        }, size: CGSize(width: 300, height: 120))
    spin(0.5)
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return }
    h.cacheDisplay(in: h.bounds, to: rep)
    let sx = Double(rep.pixelsWide) / Double(h.bounds.width)
    let sy = Double(rep.pixelsHigh) / Double(h.bounds.height)
    var counts: [Int] = []
    for t in subviews(of: h, NSTableView.self) {
        for r in 0..<t.numberOfRows {
            let rect = t.convert(t.rect(ofRow: r), to: h)
            let yTop: Double = h.isFlipped ? rect.minY : h.bounds.height - rect.maxY
            let height: Double = rect.height, right: Double = rect.maxX
            var count = 0
            for y in Int((yTop + 1) * sy)..<Int((yTop + height - 1) * sy) {
                for x in Int((right - 70) * sx)..<Int((right - 2) * sx) {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let grey: Double = (c.redComponent + c.greenComponent + c.blueComponent) / 3
                    if grey < 0.985 { count += 1 }
                }
            }
            counts.append(count)
        }
    }
    let badged = counts.count == 2 && counts[0] > counts[1] + 50
    print("badge    \(label(w.rawValue)) inked badged row \(counts.first ?? -1), plain row \(counts.last ?? -1): \(badged ? "BADGE DRAWN" : "no badge")")
}

@MainActor var pickerSelection = 2

struct PickerCase: View {
    let wrap: Wrap
    var tagged = true
    var body: some View {
        Picker("P", selection: Binding(get: { pickerSelection }, set: { pickerSelection = $0 })) {
            if tagged {
                Text("One").tag(1).wrapped(wrap)
                Text("Two").tag(2).wrapped(wrap)
            } else {
                Text("One")
                Text("Two")
            }
        }
        .pickerStyle(.menu)
        .frame(width: 200)
    }
}

@MainActor func pickerCase(_ w: Wrap, tagged: Bool = true) async {
    pickerSelection = 2
    let h = host(PickerCase(wrap: w, tagged: tagged), size: CGSize(width: 300, height: 100))
    try? await Task.sleep(for: .milliseconds(400))
    guard let p = subviews(of: h, NSPopUpButton.self).first else {
        print("picker   \(label(w.rawValue)) no pop-up"); return
    }
    let shown = "\(p.indexOfSelectedItem) '\(p.titleOfSelectedItem ?? "")' of \(p.numberOfItems)"
    p.menu?.performActionForItem(at: 0)
    try? await Task.sleep(for: .milliseconds(300))
    let name = tagged ? w.rawValue : "untagged options (control)"
    print("picker   \(label(name)) selection 2 shows item \(shown); choose item 0 -> selection \(pickerSelection)")
    h.window?.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.appearance = NSAppearance(named: .aqua)
            NSApp.finishLaunching()
            print("macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
            Task { @MainActor in
                zIndexCase(.none, zIndex: 0)
                for w in Wrap.allCases { zIndexCase(w) }
                await listTagCase(.none, tagged: false)
                for w in Wrap.allCases { await listTagCase(w) }
                for w in Wrap.allCases { badgeCase(w) }
                await pickerCase(.none, tagged: false)
                for w in Wrap.allCases { await pickerCase(w) }
                spacingControl()
                for w in Wrap.allCases { spacingCase(w) }
                for w in Wrap.allCases { priorityCase(w) }
                exit(0)
            }
            NSApp.run()
        }
    }
}
