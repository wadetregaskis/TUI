// O-26 probe: how SwiftUI decides that a view's plain-data field changed.
//
// (1) A `Double` field stepped 0.0 -> -0.0 -> -0.0 -> .nan -> .nan: a bitwise compare and `==`
//     disagree on both (-0.0 == 0.0 but the bits differ; nan != nan but the bits match).
// (2) An `Equatable` struct field whose custom `==` ignores a member: change only that member.
//
// Part A writes the value straight into a parent's @State<T> and counts the parent's bodies:
// that is @State's own compare. Part B isolates the CHILD's compare: the parent keeps the value
// in a reference box and bumps an Int @State tick, so its body re-runs on every step and hands
// the child a new view value whose field may or may not "differ".
// Each case is hosted in its own offscreen NSWindow; the run loop spins after each write; the
// body counts are read back, and what is drawn is found by comparing a bitmap of the hosting
// view (cacheDisplay) against bitmaps of reference `Text(verbatim:)` views of each candidate.
//
// Build: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 6 \
//          -parse-as-library probe.swift -o probe && ./probe
import AppKit
import SwiftUI

// MARK: - Counting

@MainActor enum Counter {
    static var bodies: [String: Int] = [:]
    static var saw: [String: String] = [:]
    static func bump(_ name: String, _ shown: String? = nil) {
        bodies[name, default: 0] += 1
        if let shown { saw[name] = shown }
    }
}

@MainActor enum Drivers {
    static var set: [String: (Any) -> Void] = [:]
}

// MARK: - Hosting (as Documentation/Working notes/plan/probe-printchanges/pc.swift)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 120)
    let h = NSHostingView(rootView: v)
    h.wantsLayer = true
    h.sizingOptions = []                    // keep 300 x 120: otherwise the view shrinks to its text
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.25) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// The hosting view's layer tree rendered into a bitmap. (`cacheDisplay(in:to:)` returned the
/// FIRST frame forever here: SwiftUI's later frames live in sublayers it does not redraw.)
@MainActor func snapshot(_ v: NSView) -> Data {
    v.layoutSubtreeIfNeeded()
    guard let layer = v.layer else { return Data() }
    let w = Int(v.bounds.width) * 2, ht = Int(v.bounds.height) * 2
    guard let ctx = CGContext(data: nil, width: w, height: ht, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return Data() }
    ctx.scaleBy(x: 2, y: 2)
    layer.render(in: ctx)
    guard let data = ctx.data else { return Data() }
    return Data(bytes: data, count: ctx.bytesPerRow * ht)
}
@MainActor var references: [String: Data] = [:]
/// A bitmap of `Text(verbatim: s)` hosted the same way: what drawing `s` looks like.
@MainActor func reference(_ s: String) -> Data {
    if let d = references[s] { return d }
    let h = host(Text(verbatim: s))
    spin(0.3); h.layoutSubtreeIfNeeded(); spin(0.1)
    let d = snapshot(h)
    references[s] = d
    return d
}
@MainActor func drawn(_ h: NSView, candidates: [String]) -> String {
    let now = snapshot(h)
    let hits = candidates.filter { reference($0) == now }
    if hits.isEmpty {
        func diff(_ a: Data, _ b: Data) -> Int { a.count != b.count ? -1 : zip(a, b).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) } }
        let d = candidates.map { "\($0):\(diff(reference($0), now))" }.joined(separator: ",")
        let nz = now.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        return "? (no candidate matches; diffs \(d); nonzero \(nz))"
    }
    return hits.joined(separator: " or ")
}

// MARK: - The harness: a parent whose @State feeds one child

/// Part A: the value lives in the parent's @State; a write is judged by @State's compare.
struct StateHarness<T>: View {
    let name: String
    @State var value: T
    var body: some View {
        let _ = Counter.bump(name + ".parent", "\(value)")
        let _ = { Drivers.set[name] = { value = $0 as! T } }()
        Text(verbatim: "\(value)")
    }
}

@MainActor final class Box<T> { var value: T; init(_ v: T) { value = v } }

/// Part B: the parent re-runs on every step (an Int tick always changes), so only the child's
/// compare decides whether the child's body runs.
struct TickHarness<T, V: View>: View {
    let name: String
    let box: Box<T>
    @State var tick = 0
    let make: (T) -> V
    init(name: String, value: T, make: @escaping (T) -> V) { self.name = name; box = Box(value); self.make = make }
    var body: some View {
        let _ = Counter.bump(name + ".parent")
        let _ = { Drivers.set[name] = { box.value = $0 as! T; tick += 1 } }()
        let _ = tick
        make(box.value)
    }
}

// MARK: - (1) Double fields

struct Readout: View {                      // POD view, not Equatable
    let value: Double
    var body: some View { let _ = Counter.bump("D1", "\(value)"); Text(verbatim: "\(value)") }
}
struct ReadoutTagged: View {                // non-POD view (a String field), not Equatable
    let value: Double
    let tag: String
    var body: some View { let _ = Counter.bump("D2", "\(value)"); Text(verbatim: "\(value)") }
}
struct ReadoutEq: View, Equatable {         // POD view (Int key picks the counter), == is Double's ==
    let key: Int
    let value: Double
    nonisolated static func == (a: Self, b: Self) -> Bool { a.value == b.value }
    var body: some View { let _ = Counter.bump(["D3", "D4"][key], "\(value)"); Text(verbatim: "\(value)") }
}
struct ReadoutTaggedEq: View, Equatable {   // non-POD view, == is Double's ==
    let key: String
    let value: Double
    nonisolated static func == (a: Self, b: Self) -> Bool { a.value == b.value }
    var body: some View { let _ = Counter.bump(key, "\(value)"); Text(verbatim: "\(value)") }
}

// MARK: - (2) An Equatable field whose == ignores `name`

struct Item: Equatable {
    var id: Int
    var name: Int
    static func == (a: Item, b: Item) -> Bool { a.id == b.id }
}
struct ItemS: Equatable {                   // the same, but non-POD (a String member)
    var id: Int
    var name: Int
    var note: String
    static func == (a: ItemS, b: ItemS) -> Bool { a.id == b.id }
}

struct ItemView: View {                     // POD view, not Equatable
    let item: Item
    var body: some View { let _ = Counter.bump("I1", "name=\(item.name)"); Text(verbatim: "name=\(item.name)") }
}
struct ItemViewEq: View, Equatable {        // POD view, synthesized == (uses Item's ==)
    let item: Item
    let key: Int                            // 0..3, picks the counter name; Int keeps the view POD
    var body: some View {
        let n = ["I2", "I3", "I4", "I9"][key]
        let _ = Counter.bump(n, "name=\(item.name)"); Text(verbatim: "name=\(item.name)")
    }
}
struct ItemViewTagged: View {               // non-POD view, not Equatable
    let key: String
    let item: Item
    var body: some View { let _ = Counter.bump(key, "name=\(item.name)"); Text(verbatim: "name=\(item.name)") }
}
struct ItemViewTaggedEq: View, Equatable {  // non-POD view, synthesized == (String's and Item's ==)
    let key: String
    let item: Item
    var body: some View { let _ = Counter.bump(key, "name=\(item.name)"); Text(verbatim: "name=\(item.name)") }
}
struct ItemSView: View {                    // view of a non-POD Equatable field, not Equatable
    let key: String
    let item: ItemS
    var body: some View { let _ = Counter.bump(key, "name=\(item.name)"); Text(verbatim: "name=\(item.name)") }
}

// MARK: - Running

@MainActor func run<T>(_ name: String, _ what: String, _ view: some View, steps: [(String, T)],
                       initial: T, shown: (T) -> String, child: Bool = true) {
    let initialShown = shown(initial)
    print("### \(name): \(what)")
    let h = host(view)
    spin(); h.layoutSubtreeIfNeeded(); spin(0.1)
    let candidates = Array(Set(steps.map { shown($0.1) } + [initialShown])).sorted()
    print(child ? "| step | parent bodies | child bodies | child saw | drawn |" : "| step | parent bodies | body saw | drawn |")
    print(child ? "|---|---|---|---|---|" : "|---|---|---|---|")
    let who = child ? name : name + ".parent"
    func row(_ label: String, _ p0: Int, _ c0: Int) {
        let p = Counter.bodies[name + ".parent", default: 0] - p0
        let c = Counter.bodies[name, default: 0] - c0
        let d = drawn(h, candidates: candidates)
        if child { print("| \(label) | \(p) | \(c) | \(Counter.saw[who] ?? "-") | \(d) |") }
        else { print("| \(label) | \(p) | \(Counter.saw[who] ?? "-") | \(d) |") }
    }
    row("first appearance", 0, 0)
    for (label, v) in steps {
        let p0 = Counter.bodies[name + ".parent", default: 0], c0 = Counter.bodies[name, default: 0]
        Drivers.set[name]?(v)
        spin(); h.layoutSubtreeIfNeeded(); spin(0.15)
        row(label, p0, c0)
    }
    print()
    fflush(stdout)
}

@main struct Probe {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            let dsteps: [(String, Double)] = [("-> -0.0", -0.0), ("-> -0.0 again", -0.0), ("-> .nan", .nan),
                                              ("-> .nan again", .nan), ("-> 0.0", 0.0), ("-> -0.0 (late)", -0.0)]
            let fsteps: [(String, Float)] = [("-> 0.0 (identical, first write)", 0.0), ("-> -0.0", -0.0), ("-> .nan", .nan), ("-> .nan again", .nan)]
            let start = Item(id: 1, name: 1)
            let isteps: [(String, Item)] = [("name 1 -> 2", Item(id: 1, name: 2)), ("name 2 -> 3", Item(id: 1, name: 3)),
                                            ("same value again", Item(id: 1, name: 3)), ("id 1 -> 2", Item(id: 2, name: 3))]
            let sstart = ItemS(id: 1, name: 1, note: "n")
            let ssteps: [(String, ItemS)] = [("name 1 -> 2", ItemS(id: 1, name: 2, note: "n")), ("name 2 -> 3", ItemS(id: 1, name: 3, note: "n")),
                                             ("same value again", ItemS(id: 1, name: 3, note: "n")), ("id 1 -> 2", ItemS(id: 2, name: 3, note: "n"))]
            let dshow: (Double) -> String = { "\($0)" }
            let ishow: (Item) -> String = { "name=\($0.name)" }
            let sshow: (ItemS) -> String = { "name=\($0.name)" }

            print("## Part A: a write to the parent's own @State<T>\n")
            run("A1", "@State<Double>, first State<Double> in the process", StateHarness(name: "A1", value: 0.0), steps: dsteps, initial: 0.0, shown: dshow, child: false)
            run("A2", "@State<Double>, second", StateHarness(name: "A2", value: 0.0), steps: dsteps, initial: 0.0, shown: dshow, child: false)
            run("A3", "@State<Float>, first write is the identical 0.0", StateHarness(name: "A3", value: Float(0)), steps: fsteps, initial: Float(0), shown: { "\($0)" }, child: false)
            run("A4", "@State<Item> (== ignores name), first State<Item>", StateHarness(name: "A4", value: start), steps: isteps, initial: start, shown: { "\($0)" }, child: false)
            run("A5", "@State<Item>, second", StateHarness(name: "A5", value: start), steps: isteps, initial: start, shown: { "\($0)" }, child: false)
            run("A6", "@State<ItemS> (non-POD, == ignores name)", StateHarness(name: "A6", value: sstart), steps: ssteps, initial: sstart, shown: { "\($0)" }, child: false)

            print("## Part B: the child's compare (parent re-runs every step)\n")
            run("D1", "POD view `let value: Double`", TickHarness(name: "D1", value: 0.0) { Readout(value: $0) }, steps: dsteps, initial: 0.0, shown: dshow)
            run("D2", "non-POD view (`value: Double`, `tag: String`)", TickHarness(name: "D2", value: 0.0) { ReadoutTagged(value: $0, tag: "t") }, steps: dsteps, initial: 0.0, shown: dshow)
            run("D3", "POD view, Equatable (Double ==), no .equatable()", TickHarness(name: "D3", value: 0.0) { ReadoutEq(key: 0, value: $0) }, steps: dsteps, initial: 0.0, shown: dshow)
            run("D4", "same POD Equatable view + .equatable()", TickHarness(name: "D4", value: 0.0) { ReadoutEq(key: 1, value: $0).equatable() }, steps: dsteps, initial: 0.0, shown: dshow)
            run("D5", "non-POD Equatable view (Double ==), no .equatable()", TickHarness(name: "D5", value: 0.0) { ReadoutTaggedEq(key: "D5", value: $0) }, steps: dsteps, initial: 0.0, shown: dshow)
            run("D6", "non-POD Equatable view (Double ==) + .equatable()", TickHarness(name: "D6", value: 0.0) { ReadoutTaggedEq(key: "D6", value: $0).equatable() }, steps: dsteps, initial: 0.0, shown: dshow)

            run("I1", "POD view `let item: Item`, not Equatable", TickHarness(name: "I1", value: start) { ItemView(item: $0) }, steps: isteps, initial: start, shown: ishow)
            run("I2", "POD view, Equatable (synthesized, Item's ==), no .equatable()", TickHarness(name: "I2", value: start) { ItemViewEq(item: $0, key: 0) }, steps: isteps, initial: start, shown: ishow)
            run("I3", "same view + .equatable()", TickHarness(name: "I3", value: start) { ItemViewEq(item: $0, key: 1).equatable() }, steps: isteps, initial: start, shown: ishow)
            run("I4", "same view in EquatableView(content:)", TickHarness(name: "I4", value: start) { EquatableView(content: ItemViewEq(item: $0, key: 2)) }, steps: isteps, initial: start, shown: ishow)
            run("I5", "non-POD view (`key: String`), not Equatable", TickHarness(name: "I5", value: start) { ItemViewTagged(key: "I5", item: $0) }, steps: isteps, initial: start, shown: ishow)
            run("I6", "non-POD view, Equatable (synthesized), no .equatable()", TickHarness(name: "I6", value: start) { ItemViewTaggedEq(key: "I6", item: $0) }, steps: isteps, initial: start, shown: ishow)
            run("I6e", "non-POD view, Equatable (synthesized) + .equatable()", TickHarness(name: "I6e", value: start) { ItemViewTaggedEq(key: "I6e", item: $0).equatable() }, steps: isteps, initial: start, shown: ishow)
            run("I7", "view of a NON-POD Equatable field `ItemS` (== ignores name), not Equatable", TickHarness(name: "I7", value: sstart) { ItemSView(key: "I7", item: $0) }, steps: ssteps, initial: sstart, shown: sshow)

            print("## Part C: the same types again, in fresh harnesses (is the first-compare effect per type?)\n")
            run("D7", "ReadoutTaggedEq again (as D5)", TickHarness(name: "D7", value: 0.0) { ReadoutTaggedEq(key: "D7", value: $0) }, steps: dsteps, initial: 0.0, shown: dshow)
            run("I8", "ItemViewTaggedEq again (as I6)", TickHarness(name: "I8", value: start) { ItemViewTaggedEq(key: "I8", item: $0) }, steps: isteps, initial: start, shown: ishow)
            run("I9", "ItemViewEq.equatable() again (as I3)", TickHarness(name: "I9", value: start) { ItemViewEq(item: $0, key: 3).equatable() }, steps: isteps, initial: start, shown: ishow)
            print("== end")
        }
    }
}
