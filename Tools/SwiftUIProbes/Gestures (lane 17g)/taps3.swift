import SwiftUI
import AppKit

struct V: View {
    let mode: String
    var body: some View {
        let base = Color.gray.frame(width: 150, height: 150)
        let v: AnyView
        switch mode {
        case "tap": v = AnyView(base.gesture(TapGesture().onEnded { log("tap") }))
        case "shift": v = AnyView(base.gesture(TapGesture().modifiers(.shift).onEnded { log("shift tap") }))
        case "shiftopt": v = AnyView(base.gesture(TapGesture().modifiers([.shift, .option]).onEnded { log("shift+opt tap") }))
        case "lp+tap": v = AnyView(base.onLongPressGesture(minimumDuration: 0.4) { log("long") }.onTapGesture { log("tap") })
        case "tap+lp": v = AnyView(base.onTapGesture { log("tap") }.onLongPressGesture(minimumDuration: 0.4) { log("long") })
        case "lpPressing": v = AnyView(base.onLongPressGesture(minimumDuration: 0.4) { log("long") } onPressingChanged: { p in log("pressing \(p)") })
        case "lpPressingMoved": v = AnyView(base.onLongPressGesture(minimumDuration: 0.4, maximumDistance: 5) { log("long") } onPressingChanged: { p in log("pressing \(p)") })
        default: v = AnyView(base)
        }
        return v.frame(width: 300, height: 300, alignment: .topLeading)
    }
}

struct Cancelled: View {
    @GestureState(reset: { v, _ in log("reset from \(v)") }) var inner = false
    var body: some View {
        let _ = log("body inner=\(inner)")
        return Color.red.frame(width: 50, height: 50)
            .gesture(LongPressGesture(minimumDuration: 2).updating($inner) { v, s, _ in s = v; log("inner updating \(v)") })
            .frame(width: 200, height: 200, alignment: .topLeading)
            .background(Color.gray)
            .highPriorityGesture(DragGesture().onChanged { _ in log("outer drag changed") }.onEnded { _ in log("outer drag ended") })
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setup()
            for d in [35.0, 40.0, 45.0, 50.0, 60.0] {
                section("tap: slide right \(d)")
                Probe(V(mode: "tap"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), M(0.02, 10 + d, 10), U(0.04, 10 + d, 10)], tail: 0.4)
                section("tap: slide down \(d)")
                Probe(V(mode: "tap"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), M(0.02, 10, 10 + d), U(0.04, 10, 10 + d)], tail: 0.4)
            }
            section("tap: slide right 60 and back to 10")
            Probe(V(mode: "tap"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), M(0.02, 70, 10), M(0.04, 20, 10), U(0.06, 20, 10)], tail: 0.4)
            for hold in [0.78, 0.8, 0.82, 0.85] {
                section("tap: held \(hold)")
                Probe(V(mode: "tap"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), U(hold, 10, 10)], tail: 0.4)
            }
            for (label, mods) in [("none", NSEvent.ModifierFlags()), ("shift", .shift), ("shift+option", [.shift, .option]), ("shift+control", [.shift, .control]), ("option", .option)] {
                section("shift-gated tap, \(label)-click")
                Probe(V(mode: "shift"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10, mods: mods), U(0.03, 10, 10, mods: mods)], tail: 0.4)
                section("shift+option-gated tap, \(label)-click")
                Probe(V(mode: "shiftopt"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10, mods: mods), U(0.03, 10, 10, mods: mods)], tail: 0.4)
            }
            section("shift-gated tap, shift only on the release")
            Probe(V(mode: "shift"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), U(0.03, 10, 10, mods: .shift)], tail: 0.4)
            for mode in ["lp+tap", "tap+lp"] {
                section("\(mode): click")
                Probe(V(mode: mode), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), U(0.03, 10, 10)], tail: 0.6)
                section("\(mode): hold 0.6")
                Probe(V(mode: mode), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), U(0.6, 10, 10)], tail: 0.6)
            }
            section("lpPressing: click")
            Probe(V(mode: "lpPressing"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), U(0.03, 10, 10)], tail: 0.6)
            section("lpPressing: hold 0.6")
            Probe(V(mode: "lpPressing"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), U(0.6, 10, 10)], tail: 0.6)
            section("lpPressingMoved: move 8 at 0.1")
            Probe(V(mode: "lpPressingMoved"), size: CGSize(width: 300, height: 300)).play([D(0, 10, 10), M(0.1, 18, 10), U(0.6, 18, 10)], tail: 0.6)
            section("cancelled: inner long press (updating), outer high-priority drag wins")
            Probe(Cancelled()).play([D(0, 25, 25), M(0.1, 30, 25), M(0.15, 50, 25), U(0.2, 50, 25)], tail: 0.6)
        }
    }
}
