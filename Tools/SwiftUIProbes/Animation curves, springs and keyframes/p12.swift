import SwiftUI
import AppKit

// A PHASE ANIMATOR OVER CONTENT THAT DOES NOT ANIMATE (hunt H-66, STYLE-3):
// is a step paced by its animation when nothing in the content moves?
// p9.swift measured only `.opacity` content, which animates. Offscreen
// NSHostingView, as p9.swift.
//
// - `PhaseAnimator([0, 1, 2]) { Text("P\($0)") } animation: { _ in
//   .linear(duration: 0.5) }`: how often the phases advance.
// - The same over one phase, `[0]`: does it keep stepping or drawing after it
//   settles? (The animation closure called, the content closure called.)
// - Then a matrix of contents by animations, 3.5 s each: three phases, timed
//   by when the content closure is first handed each new phase.
//
// Each line prints the gap before each new phase, in seconds to one place
// (a frame's timing moves the second place from run to run), and how many
// times the content and animation closures were called.
//
// Found (macOS 15.8.3, Xcode's Swift 6.2.4, 2026-11-23; p12.out, runs alike
// in shape, an earlier draft's with the window on screen too): SwiftUI does NOT pace a
// step by its animation's duration whatever the content. The Text-only
// case at linear 0.5 s steps once, to P1, and then never again: no closure
// is called after it. The same Text with a spring (`.default`,
// `.spring(duration: 0.5)`) steps every 0.8 s; with `.monospacedDigit()` at
// linear 0.5 s, every 0.5 s; a fixed-size `Color` whose width changes with
// animations disabled stalls at linear and steps every 0.5 s with a spring;
// opacity on a `Color` steps every 0.5 s with any of them. A one-phase
// animator calls its content closure once and its animation closure never:
// it rests.
//
// c<phase>: content handed a phase.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) {
    let size = CGSize(width: 200, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// Every closure call, with its time: `c<phase>` for the content closure,
/// `a<phase>` for the animation closure.
enum Log {
    nonisolated(unsafe) static var entries: [(String, Date)] = []
    nonisolated(unsafe) static var start = Date()
    static func note(_ s: String) { entries.append((s, Date())) }
    static func flush(_ title: String) {
        var out: [String] = []
        var last = start, lastPhase = ""
        let contents = entries.filter { $0.0.hasPrefix("c") }
        for (entry, time) in contents where entry != lastPhase {
            out.append("+\(String(format: "%.1f", time.timeIntervalSince(last))) \(entry)")
            last = time
            lastPhase = entry
        }
        let animations = entries.count - contents.count
        print(title + ": " + out.joined(separator: " ") + "  [\(contents.count) content, \(animations) animation calls]")
        entries = []
        start = Date()
    }
}

@MainActor func closeAll() {
    for w in keep { w.contentView = nil; w.close() }
    keep = []
    spin(0.2)
    Log.entries = []
}

enum Kind: String, CaseIterable {
    /// `Text("P\(phase)")`.
    case text
    /// The same in a fixed frame.
    case textFramed
    /// The same with digits of one width.
    case textMono
    /// A `Color` whose width changes with animations disabled.
    case colorUnanimated
    /// A `Color` whose opacity changes (p9's content).
    case colorOpacity
}

struct Phases: View {
    let phases: [Int]
    let animation: Animation?
    let kind: Kind
    var body: some View {
        PhaseAnimator(phases) { phase in
            let _ = Log.note("c\(phase)")
            switch kind {
            case .text: Text("P\(phase)")
            case .textFramed: Text("P\(phase)").frame(width: 50, height: 20)
            case .textMono: Text("P\(phase)").monospacedDigit()
            case .colorUnanimated:
                Color.red.frame(width: 10 + CGFloat(phase), height: 10).transaction { $0.animation = nil }
            case .colorOpacity: Color.red.frame(width: 10, height: 10).opacity(Double(phase) / 2)
            }
        } animation: { phase in
            Log.note("a\(phase)")
            return animation
        }
    }
}

@main
struct Probe {
    @MainActor static func main() {
        let linear = Animation.linear(duration: 0.5)
        Log.start = Date()
        host(Phases(phases: [0, 1, 2], animation: linear, kind: .text)); spin(3.0)
        Log.flush("text [0,1,2] linear 0.5, first 3s")
        spin(1.5)
        Log.flush("text [0,1,2] linear 0.5, the next 1.5s")
        closeAll()

        Log.start = Date()
        host(Phases(phases: [0], animation: linear, kind: .text)); spin(3.0)
        Log.flush("text [0] linear 0.5, first 3s")
        spin(1.5)
        Log.flush("text [0] linear 0.5, the next 1.5s")
        closeAll()

        let animations: [(String, Animation)] = [
            ("linear 0.5", linear), ("easeInOut 0.5", .easeInOut(duration: 0.5)), ("default", .default),
            ("spring 0.5", .spring(duration: 0.5)),
        ]
        for kind in Kind.allCases {
            for (name, animation) in animations {
                Log.start = Date()
                host(Phases(phases: [0, 1, 2], animation: animation, kind: kind)); spin(3.5)
                Log.flush("\(kind) \(name), 3.5s")
                closeAll()
            }
        }
    }
}
