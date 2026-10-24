import SwiftUI
import AppKit

// Arbitration between a parent's gesture and a child's.
struct ParentChild: View {
    let mode: String
    var body: some View {
        let parentTap = TapGesture().onEnded { log("parent tap") }
        let child = Color.red.frame(width: 50, height: 50).onTapGesture { log("child onTap") }
        let stack = VStack(spacing: 0) { child; Color.blue.frame(width: 50, height: 50) }.frame(width: 200, height: 200, alignment: .topLeading).background(Color.gray)
        switch mode {
        case "gesture": return AnyView(stack.gesture(parentTap))
        case "high": return AnyView(stack.highPriorityGesture(parentTap))
        case "simul": return AnyView(stack.simultaneousGesture(parentTap))
        case "gesture.gesture": return AnyView(stack.gesture(parentTap, including: .gesture))
        case "gesture.subviews": return AnyView(stack.gesture(parentTap, including: .subviews))
        case "gesture.none": return AnyView(stack.gesture(parentTap, including: .none))
        case "high.subviews": return AnyView(stack.highPriorityGesture(parentTap, including: .subviews))
        case "onTap": return AnyView(stack.onTapGesture { log("parent onTap") })
        default: return AnyView(stack)
        }
    }
}

struct ButtonCase: View {
    let mode: String
    var body: some View {
        let b = Button("Press") { log("button action") }.frame(width: 100, height: 40)
        let tap = TapGesture().onEnded { log("tap gesture") }
        let v: AnyView
        switch mode {
        case "gesture": v = AnyView(b.gesture(tap))
        case "high": v = AnyView(b.highPriorityGesture(tap))
        case "simul": v = AnyView(b.simultaneousGesture(tap))
        case "onTap": v = AnyView(b.onTapGesture { log("onTap") })
        case "longpress": v = AnyView(b.onLongPressGesture(minimumDuration: 0.3) { log("long press") })
        case "drag": v = AnyView(b.gesture(DragGesture().onChanged { _ in log("drag changed") }.onEnded { _ in log("drag ended") }))
        case "drag0": v = AnyView(b.gesture(DragGesture(minimumDistance: 0).onChanged { _ in log("drag0 changed") }.onEnded { _ in log("drag0 ended") }))
        case "highdrag": v = AnyView(b.highPriorityGesture(DragGesture().onChanged { _ in log("hdrag changed") }.onEnded { _ in log("hdrag ended") }))
        case "highdrag0": v = AnyView(b.highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { _ in log("hdrag0 changed") }.onEnded { _ in log("hdrag0 ended") }))
        default: v = AnyView(b)
        }
        return v.frame(width: 200, height: 200, alignment: .topLeading)
    }
}

// A parent drag over a child tap.
struct DragOverTap: View {
    let mode: String
    var body: some View {
        let child = Color.red.frame(width: 50, height: 50).onTapGesture { log("child onTap") }
        let stack = VStack(spacing: 0) { child; Spacer() }.frame(width: 200, height: 200, alignment: .topLeading).background(Color.gray)
        let drag = DragGesture().onChanged { v in log("parent drag changed \(v.translation)") }.onEnded { v in log("parent drag ended \(v.translation)") }
        switch mode {
        case "gesture": return AnyView(stack.gesture(drag))
        case "high": return AnyView(stack.highPriorityGesture(drag))
        default: return AnyView(stack.simultaneousGesture(drag))
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setup()
            for mode in ["gesture", "high", "simul", "gesture.gesture", "gesture.subviews", "gesture.none", "high.subviews", "onTap"] {
                section("parent \(mode): click child, then click blue sibling")
                let p = Probe(ParentChild(mode: mode))
                p.play([D(0, 25, 25), U(0.03, 25, 25), D(0.6, 25, 75), U(0.63, 25, 75)])
            }
            for mode in ["plain", "gesture", "high", "simul", "onTap", "longpress", "drag", "drag0", "highdrag", "highdrag0"] {
                section("button \(mode): click")
                let p = Probe(ButtonCase(mode: mode))
                p.play([D(0, 50, 20), U(0.03, 50, 20)])
                section("button \(mode): hold 0.5s")
                p.play([D(0, 50, 20), U(0.5, 50, 20)])
                section("button \(mode): drag 30pt")
                p.play([D(0, 50, 20), M(0.05, 60, 20), M(0.1, 80, 20), U(0.15, 80, 20)])
            }
            for mode in ["gesture", "high", "simul"] {
                section("drag-over-tap \(mode): click child")
                let p = Probe(DragOverTap(mode: mode))
                p.play([D(0, 25, 25), U(0.03, 25, 25)])
                section("drag-over-tap \(mode): drag from child")
                p.play([D(0, 25, 25), M(0.05, 30, 25), M(0.1, 45, 25), U(0.15, 45, 25)])
            }
        }
    }
}
