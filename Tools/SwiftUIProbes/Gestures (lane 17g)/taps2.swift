import SwiftUI
import AppKit

// Thresholds: the double-tap window, how long a tap may be held, how far it
// may travel, and a release outside the view.
struct Taps: View {
    let mode: String
    var body: some View {
        let base = Color.gray.frame(width: 100, height: 100).frame(width: 200, height: 200, alignment: .topLeading)
        switch mode {
        case "count1": return AnyView(Color.gray.frame(width: 100, height: 100).gesture(TapGesture().onEnded { log("tap1") }).frame(width: 200, height: 200, alignment: .topLeading))
        case "count2": return AnyView(Color.gray.frame(width: 100, height: 100).gesture(TapGesture(count: 2).onEnded { log("tap2") }).frame(width: 200, height: 200, alignment: .topLeading))
        case "both": return AnyView(Color.gray.frame(width: 100, height: 100).onTapGesture(count: 2) { log("tap2") }.onTapGesture { log("tap1") }.frame(width: 200, height: 200, alignment: .topLeading))
        case "onTap": return AnyView(Color.gray.frame(width: 100, height: 100).onTapGesture { log("onTap") }.frame(width: 200, height: 200, alignment: .topLeading))
        default: return AnyView(base)
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setup()
            for gap in [0.25, 0.3, 0.33, 0.36, 0.4] {
                section("count2: down-to-down gap \(gap)")
                let p = Probe(Taps(mode: "count2"))
                p.play([D(0, 20, 30), U(0.03, 20, 30), D(gap, 20, 30, cc: 2), U(gap + 0.03, 20, 30, cc: 2)], tail: 0.8)
            }
            for gap in [0.3, 0.36] {
                section("count2: up-to-down gap \(gap) after a 0.2 hold")
                let p = Probe(Taps(mode: "count2"))
                p.play([D(0, 20, 30), U(0.2, 20, 30), D(0.2 + gap, 20, 30, cc: 2), U(0.23 + gap, 20, 30, cc: 2)], tail: 0.8)
            }
            for hold in [0.3, 0.5, 0.6, 0.75, 0.9] {
                section("count1: held \(hold)")
                let p = Probe(Taps(mode: "count1"))
                p.play([D(0, 20, 30), U(hold, 20, 30)], tail: 0.5)
            }
            for (dx, label) in [(30.0, "30 inside"), (70.0, "70 inside"), (90.0, "outside by 10"), (150.0, "outside by 70")] {
                section("count1: slide \(label)")
                let p = Probe(Taps(mode: "count1"))
                p.play([D(0, 20, 30), M(0.02, 20 + dx / 2, 30), M(0.04, 20 + dx, 30), U(0.06, 20 + dx, 30)], tail: 0.5)
                section("onTap: slide \(label)")
                let q = Probe(Taps(mode: "onTap"))
                q.play([D(0, 20, 30), M(0.02, 20 + dx / 2, 30), M(0.04, 20 + dx, 30), U(0.06, 20 + dx, 30)], tail: 0.5)
            }
            section("count1: slide out and back in")
            let p = Probe(Taps(mode: "count1"))
            p.play([D(0, 20, 30), M(0.02, 150, 30), M(0.04, 30, 30), U(0.06, 30, 30)], tail: 0.5)
            section("both: single click — when does tap1 fire after the release")
            let q = Probe(Taps(mode: "both"))
            q.play([D(0, 20, 30), U(0.03, 20, 30)], tail: 1.0)
            section("both: single click held 0.2")
            let r = Probe(Taps(mode: "both"))
            r.play([D(0, 20, 30), U(0.2, 20, 30)], tail: 1.0)
            section("count2: second click 10pt away")
            let s = Probe(Taps(mode: "count2"))
            s.play([D(0, 20, 30), U(0.03, 20, 30), D(0.15, 30, 30, cc: 2), U(0.18, 30, 30, cc: 2)], tail: 0.6)
            section("count2: second click 40pt away")
            let t = Probe(Taps(mode: "count2"))
            t.play([D(0, 20, 30), U(0.03, 20, 30), D(0.15, 60, 30, cc: 2), U(0.18, 60, 30, cc: 2)], tail: 0.6)
            section("count2: when does tap2 fire — second press held 0.3")
            let u = Probe(Taps(mode: "count2"))
            u.play([D(0, 20, 30), U(0.03, 20, 30), D(0.15, 20, 30, cc: 2), U(0.45, 20, 30, cc: 2)], tail: 0.6)
        }
    }
}
