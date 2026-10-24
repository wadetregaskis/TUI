import SwiftUI
import AppKit

func f(_ p: CGPoint) -> String { String(format: "(%.1f,%.1f)", p.x, p.y) }
func f(_ s: CGSize) -> String { String(format: "(%.1f,%.1f)", s.width, s.height) }
func dv(_ v: DragGesture.Value) -> String {
    "loc\(f(v.location)) start\(f(v.startLocation)) tr\(f(v.translation)) vel\(f(v.velocity)) pEnd\(f(v.predictedEndLocation)) pTr\(f(v.predictedEndTranslation)) t\(String(format: "%.3f", v.time.timeIntervalSince1970.truncatingRemainder(dividingBy: 100)))"
}

struct Box<G: Gesture>: View {
    let gesture: G
    var body: some View {
        Color.gray.frame(width: 200, height: 200).gesture(gesture)
    }
}

struct LongPressCase: View {
    let minimumDuration: Double?
    @GestureState var pressing = false
    var body: some View {
        let g = (minimumDuration.map { LongPressGesture(minimumDuration: $0) } ?? LongPressGesture())
            .updating($pressing) { v, s, _ in log("updating \(v)"); s = v }
            .onChanged { v in log("changed \(v)") }
            .onEnded { v in log("ended \(v)") }
        let _ = log("body pressing=\(pressing)")
        return Color.gray.frame(width: 200, height: 200).gesture(g)
    }
}

struct DragStateCase: View {
    @GestureState(reset: { v, _ in log("reset callback from \(v)") }) var offset: CGSize = .zero
    let minimumDistance: CGFloat
    var body: some View {
        let _ = log("body offset=\(f(offset))")
        return Color.gray.frame(width: 200, height: 200)
            .gesture(DragGesture(minimumDistance: minimumDistance)
                .updating($offset) { v, s, _ in s = v.translation }
                .onChanged { v in log("changed " + dv(v)) }
                .onEnded { v in log("ended " + dv(v)) })
    }
}

struct TwoTaps: View {
    let mode: String
    var body: some View {
        let base = Color.gray.frame(width: 200, height: 200)
        switch mode {
        case "count2": return AnyView(base.gesture(TapGesture(count: 2).onEnded { log("tap2") }))
        case "count1": return AnyView(base.gesture(TapGesture(count: 1).onEnded { log("tap1") }))
        case "count3": return AnyView(base.gesture(TapGesture(count: 3).onEnded { log("tap3") }))
        case "both": return AnyView(base.onTapGesture(count: 2) { log("tap2") }.onTapGesture(count: 1) { log("tap1") })
        case "excl": return AnyView(base.gesture(TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { v in log("excl \(v)") }))
        case "spatial": return AnyView(base.gesture(SpatialTapGesture().onChanged { v in log("spatial changed \(f(v.location))") }.onEnded { v in log("spatial ended \(f(v.location))") }))
        case "spatial2": return AnyView(base.gesture(SpatialTapGesture(count: 2).onChanged { v in log("spatial2 changed \(f(v.location))") }.onEnded { v in log("spatial2 ended \(f(v.location))") }))
        case "map": return AnyView(base.gesture(TapGesture().map { "mapped" }.onEnded { v in log("map \(v)") }))
        default: return AnyView(base)
        }
    }
}

struct Combo: View {
    let mode: String
    var body: some View {
        let base = Color.gray.frame(width: 200, height: 200)
        switch mode {
        case "lp>drag":
            return AnyView(base.gesture(LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture())
                .onChanged { v in log("seq changed \(seq(v))") }.onEnded { v in log("seq ended \(seq(v))") }))
        case "lp>drag0":
            return AnyView(base.gesture(LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { v in log("seq0 changed \(seq(v))") }.onEnded { v in log("seq0 ended \(seq(v))") }))
        case "tap>tap":
            return AnyView(base.gesture(TapGesture().sequenced(before: TapGesture()).onEnded { _ in log("tap>tap ended") }))
        case "drag+lp":
            return AnyView(base.gesture(DragGesture().simultaneously(with: LongPressGesture(minimumDuration: 0.3))
                .onChanged { v in log("sim changed drag=\(v.first.map { f($0.translation) } ?? "nil") lp=\(String(describing: v.second))") }
                .onEnded { v in log("sim ended drag=\(v.first.map { f($0.translation) } ?? "nil") lp=\(String(describing: v.second))") }))
        case "tap+tap2":
            return AnyView(base.gesture(TapGesture().simultaneously(with: TapGesture(count: 2))
                .onEnded { v in log("sim ended first=\(v.first != nil) second=\(v.second != nil)") }))
        case "lp|drag":
            return AnyView(base.gesture(LongPressGesture(minimumDuration: 0.3).exclusively(before: DragGesture())
                .onChanged { v in log("excl changed \(ex(v))") }.onEnded { v in log("excl ended \(ex(v))") }))
        case "drag|lp":
            return AnyView(base.gesture(DragGesture().exclusively(before: LongPressGesture(minimumDuration: 0.3))
                .onChanged { v in log("excl2 changed \(ex2(v))") }.onEnded { v in log("excl2 ended \(ex2(v))") }))
        case "shiftdrag":
            return AnyView(base.gesture(DragGesture().modifiers(.shift).onChanged { v in log("shift drag changed \(f(v.translation))") }.onEnded { v in log("shift drag ended") }))
        case "opttap":
            return AnyView(base.gesture(TapGesture().modifiers(.option).onEnded { log("option tap") }))
        default: return AnyView(base)
        }
    }
    func seq(_ v: SequenceGesture<LongPressGesture, DragGesture>.Value) -> String {
        switch v {
        case .first(let b): return "first(\(b))"
        case .second(let b, let d): return "second(\(b), \(d.map { f($0.translation) } ?? "nil"))"
        }
    }
    func ex(_ v: ExclusiveGesture<LongPressGesture, DragGesture>.Value) -> String {
        switch v {
        case .first(let b): return "first(\(b))"
        case .second(let d): return "second(\(f(d.translation)))"
        }
    }
    func ex2(_ v: ExclusiveGesture<DragGesture, LongPressGesture>.Value) -> String {
        switch v {
        case .first(let d): return "first(\(f(d.translation)))"
        case .second(let b): return "second(\(b))"
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setup()
            log("doubleClickInterval \(NSEvent.doubleClickInterval)")
            let which = CommandLine.arguments.dropFirst().first ?? "all"
            if which == "all" || which == "lp" {
                for (label, md) in [("default", nil), ("0.3", 0.3 as Double?)] {
                    section("long press \(label): hold 0.45 release")
                    var p = Probe(LongPressCase(minimumDuration: md))
                    p.play([D(0, 50, 50), U(0.45, 50, 50)])
                    section("long press \(label): hold 0.8 release")
                    p = Probe(LongPressCase(minimumDuration: md))
                    p.play([D(0, 50, 50), U(0.8, 50, 50)])
                }
                for d in [5.0, 9.0, 10.0, 11.0, 15.0] {
                    section("long press default: move \(d) at 0.1 then hold to 0.8")
                    let p = Probe(LongPressCase(minimumDuration: nil))
                    p.play([D(0, 50, 50), M(0.1, 50 + d, 50), U(0.8, 50 + d, 50)])
                }
                section("long press default: diagonal 8,8 at 0.1")
                let p = Probe(LongPressCase(minimumDuration: nil))
                p.play([D(0, 50, 50), M(0.1, 58, 58), U(0.8, 58, 58)])
            }
            if which == "all" || which == "drag" {
                for md in [10.0, 0.0] {
                    section("drag min \(md): click")
                    var p = Probe(DragStateCase(minimumDistance: md))
                    p.play([D(0, 50, 50), U(0.03, 50, 50)])
                    section("drag min \(md): 5pt then release")
                    p = Probe(DragStateCase(minimumDistance: md))
                    p.play([D(0, 50, 50), M(0.02, 55, 50), U(0.04, 55, 50)])
                    section("drag min \(md): 5, 12, 20, 30 at 20ms, release")
                    p = Probe(DragStateCase(minimumDistance: md))
                    p.play([D(0, 50, 50), M(0.02, 55, 50), M(0.04, 62, 50), M(0.06, 70, 50), M(0.08, 80, 50), U(0.10, 80, 50)])
                    section("drag min \(md): 9 diag (6,7) then release")
                    p = Probe(DragStateCase(minimumDistance: md))
                    p.play([D(0, 50, 50), M(0.02, 56, 57), U(0.04, 56, 57)])
                    section("drag min \(md): 30 then hold still 0.3 then release")
                    p = Probe(DragStateCase(minimumDistance: md))
                    p.play([D(0, 50, 50), M(0.02, 65, 50), M(0.04, 80, 50), U(0.34, 80, 50)])
                }
            }
            if which == "all" || which == "taps" {
                for mode in ["count1", "count2", "count3", "both", "excl", "spatial", "spatial2", "map"] {
                    for (gap, cc2) in [(0.2, 2), (0.2, 1), (0.45, 2), (0.6, 2), (1.0, 2)] {
                        section("\(mode): two clicks gap \(gap) second cc\(cc2)")
                        let p = Probe(TwoTaps(mode: mode))
                        p.play([D(0, 20, 30), U(0.03, 20, 30), D(gap, 20, 30, cc: cc2), U(gap + 0.03, 20, 30, cc: cc2)], tail: 0.8)
                    }
                    section("\(mode): three clicks 0.15 apart cc1,2,3")
                    let p = Probe(TwoTaps(mode: mode))
                    p.play([D(0, 20, 30), U(0.03, 20, 30), D(0.15, 20, 30, cc: 2), U(0.18, 20, 30, cc: 2), D(0.3, 20, 30, cc: 3), U(0.33, 20, 30, cc: 3)], tail: 0.8)
                    section("\(mode): click with 3pt slide")
                    let q = Probe(TwoTaps(mode: mode))
                    q.play([D(0, 20, 30), M(0.01, 23, 30), U(0.03, 23, 30)], tail: 0.8)
                    section("\(mode): click with 15pt slide")
                    let r = Probe(TwoTaps(mode: mode))
                    r.play([D(0, 20, 30), M(0.01, 35, 30), U(0.03, 35, 30)], tail: 0.8)
                    section("\(mode): press held 1.0s")
                    let s = Probe(TwoTaps(mode: mode))
                    s.play([D(0, 20, 30), U(1.0, 20, 30)], tail: 0.8)
                }
            }
            if which == "all" || which == "combo" {
                for mode in ["lp>drag", "lp>drag0", "tap>tap", "drag+lp", "tap+tap2", "lp|drag", "drag|lp", "shiftdrag", "opttap"] {
                    section("\(mode): click")
                    var p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50), U(0.03, 50, 50)])
                    section("\(mode): double click")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50), U(0.03, 50, 50), D(0.15, 50, 50, cc: 2), U(0.18, 50, 50, cc: 2)])
                    section("\(mode): hold 0.5 release")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50), U(0.5, 50, 50)])
                    section("\(mode): hold 0.5, drag 30, release")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50), M(0.5, 60, 50), M(0.55, 80, 50), U(0.6, 80, 50)])
                    section("\(mode): drag 30 at once, hold to 0.5, release")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50), M(0.05, 60, 50), M(0.1, 80, 50), U(0.5, 80, 50)])
                    section("\(mode): shift-drag 30")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50, mods: .shift), M(0.05, 60, 50, mods: .shift), M(0.1, 80, 50, mods: .shift), U(0.15, 80, 50, mods: .shift)])
                    section("\(mode): option-click")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50, mods: .option), U(0.03, 50, 50, mods: .option)])
                    section("\(mode): drag 30, shift released mid-drag")
                    p = Probe(Combo(mode: mode))
                    p.play([D(0, 50, 50, mods: .shift), M(0.05, 60, 50, mods: .shift), M(0.1, 80, 50), M(0.12, 90, 50), U(0.15, 90, 50)])
                }
            }
        }
    }
}
