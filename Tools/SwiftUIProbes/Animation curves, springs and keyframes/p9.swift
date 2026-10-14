import SwiftUI
import AppKit

// PHASE AND KEYFRAME ANIMATORS (refusal review O2, decisions A37): what the
// content closure and the animation / keyframes closures are handed, and when.
// Offscreen NSHostingView, as ../Alignment guides/guide.swift.
//
// - PhaseAnimator with a trigger: does one trigger change step one phase or
//   run through them all? Where does it rest? Is the animation closure handed
//   the phase it leaves or the one it enters?
// - PhaseAnimator with no trigger: where it starts, how it cycles.
// - KeyframeAnimator: the value before a trigger, after the keyframes end, the
//   keyframes closure's argument; repeating: false.
//
// Found (p9.out; macOS 15.8, 2026-10-14): a trigger change runs through EVERY
// phase and back to the first — SwiftUI's documentation says one step per
// change — and a change mid-run starts the run again after the step under
// way; the animation closure is handed the phase being entered; with no
// trigger it cycles, and a cycle with nothing animated stops at the first
// phase. Keyframes rest at the initial value, play to the end and rest there,
// and REPLAY FROM THE INITIAL VALUE on the next trigger — the documentation
// says from the end value — except a trigger during play, which starts from
// the value reached; repeating: false draws the timeline's start and plays
// nothing.
//
// c<phase>: content handed a phase; a<phase>: animation handed one;
// v<value>: content handed a value; k<value>: keyframes handed a start.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 200, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// What the closures saw, consecutive repeats folded. Written from the
/// keyframes closure too, which is not main-actor isolated; the probe is
/// single-threaded in practice.
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func note(_ s: String) { if lines.last != s { lines.append(s) } }
    static func flush(_ title: String) { print(title + ": " + lines.joined(separator: " ")); lines = [] }
    /// `k`/`v` entries other than the start and the end written as `mid`,
    /// folded again.
    static func flushClassified(_ title: String, start: String = "0", end: String = "10") {
        var folded: [String] = []
        for line in lines {
            let kind = line.prefix(1), number = line.dropFirst()
            let word = number == start || number == end ? line : kind + "mid"
            if folded.last != word { folded.append(word) }
        }
        lines = folded
        flush(title)
    }
}

/// Takes every hosted view off screen, so the next case logs alone.
@MainActor func closeAll() {
    for w in keep { w.contentView = nil; w.close() }
    keep = []
    spin(0.2)
    Log.lines = []
}

@Observable final class Trigger { var value = 0 }

struct PhaseTriggered: View {
    let trigger: Trigger
    var body: some View {
        Color.red.frame(width: 10, height: 10)
            .phaseAnimator([0, 1, 2], trigger: trigger.value) { content, phase in
                let _ = Log.note("c\(phase)")
                content.opacity(Double(phase) / 2)
            } animation: { phase in
                Log.note("a\(phase)")
                return .linear(duration: 0.2)
            }
    }
}

struct PhaseContinuous: View {
    var body: some View {
        Color.red.frame(width: 10, height: 10)
            .phaseAnimator([0, 1, 2]) { content, phase in
                let _ = Log.note("c\(phase)")
                content.opacity(Double(phase) / 2)
            } animation: { phase in
                Log.note("a\(phase)")
                return .linear(duration: 0.2)
            }
    }
}

struct PhaseNilAnimation: View {
    var body: some View {
        Color.red.frame(width: 10, height: 10)
            .phaseAnimator([0, 1, 2]) { content, phase in
                let _ = Log.note("c\(phase)")
                content.opacity(Double(phase) / 2)
            } animation: { _ in nil }
    }
}

struct KeyframeTriggered: View {
    let trigger: Trigger
    var body: some View {
        Color.red.frame(width: 10, height: 10)
            .keyframeAnimator(initialValue: 0.0, trigger: trigger.value) { content, value in
                let _ = Log.note("v\(Int(value.rounded()))")
                content.opacity(value / 10)
            } keyframes: { start in
                let _ = Log.note("k\(Int(start.rounded()))")
                LinearKeyframe(10.0, duration: 0.3)
            }
    }
}

struct KeyframeOnce: View {
    let repeating: Bool
    var body: some View {
        Color.red.frame(width: 10, height: 10)
            .keyframeAnimator(initialValue: 3.0, repeating: repeating) { content, value in
                let _ = Log.note("v\(Int(value.rounded()))")
                content.opacity(value / 10)
            } keyframes: { start in
                let _ = Log.note("k\(Int(start.rounded()))")
                LinearKeyframe(7.0, duration: 0.1)
                LinearKeyframe(10.0, duration: 0.2)
            }
    }
}

@main
struct Probe {
    @MainActor static func main() {
        let trigger = Trigger()
        _ = host(PhaseTriggered(trigger: trigger)); spin(0.5)
        Log.flush("phase+trigger appear")
        trigger.value += 1; spin(1.5)
        Log.flush("phase+trigger change 1")
        trigger.value += 1; spin(1.5)
        Log.flush("phase+trigger change 2")
        trigger.value += 1; spin(1.5)
        Log.flush("phase+trigger change 3")
        // A change during a run: the second arrives 0.3 s in, during the step
        // to the second phase (each step takes 0.2 s).
        trigger.value += 1; spin(0.3)
        trigger.value += 1; spin(1.5)
        Log.flush("phase+trigger changed twice, 0.3 s apart")
        closeAll()

        _ = host(PhaseContinuous()); spin(1.3)
        Log.flush("phase continuous 1.3s")
        closeAll()

        _ = host(PhaseNilAnimation()); spin(0.5)
        Log.flush("phase nil-animation 0.5s")
        spin(1.5)
        Log.flush("phase nil-animation the next 1.5s")
        closeAll()

        let k = Trigger()
        _ = host(KeyframeTriggered(trigger: k)); spin(0.5)
        Log.flush("keyframe+trigger appear")
        k.value += 1; spin(1.0)
        Log.flush("keyframe+trigger change 1")
        k.value += 1; spin(1.0)
        Log.flush("keyframe+trigger change 2")
        // Interrupted part-way: where it was depends on timing, so these two
        // print only whether a value was the start, the end, or between.
        k.value += 1; spin(0.12)
        Log.flushClassified("keyframe+trigger change 3, 0.12s in")
        k.value += 1; spin(1.0)
        Log.flushClassified("keyframe+trigger change 4, during the third")
        closeAll()

        _ = host(KeyframeOnce(repeating: false)); spin(0.8)
        Log.flush("keyframe repeating:false")
        closeAll()
        // Sampled by frame, so summarised: the first entries, then how often
        // the end was reached and whether what followed it was below it.
        _ = host(KeyframeOnce(repeating: true)); spin(0.75)
        let seen = Log.lines
        let ends = seen.indices.filter { seen[$0] == "v10" }
        let restarts = ends.filter { $0 + 1 < seen.count && seen[$0 + 1] != "v10" }.count
        print("keyframe repeating:true 0.75s: starts \(seen.prefix(2).joined(separator: " ")), reaches v10 \(ends.count >= 2 ? "at least twice" : "\(ends.count) times"), falls back after it \(restarts >= 1 ? "yes" : "no")")
        Log.lines = []
    }
}
