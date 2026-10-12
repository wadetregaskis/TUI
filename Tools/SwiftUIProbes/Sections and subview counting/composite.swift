import SwiftUI
import AppKit

struct Box: View {
    let name: String; var w: CGFloat = 20; var h: CGFloat = 10
    var body: some View { Color.red.frame(width: w, height: h).probe(name) }
}

struct Rows: View {
    let tag: String
    var body: some View {
        Box(name: "\(tag)a")
        Box(name: "\(tag)b")
    }
}

struct StatefulRows: View {
    @State var n = 0
    let tag: String
    var body: some View {
        Box(name: "\(tag)a\(n)")
        Box(name: "\(tag)b")
    }
}

struct Nested: View {
    var body: some View { Rows(tag: "n") }
}

struct LoopBody: View {
    var body: some View { ForEach(0..<3, id: \.self) { Box(name: "l\($0)") } }
}

struct IfBody: View {
    let show: Bool
    var body: some View { if show { Box(name: "i") } }
}

struct PaddedPair: View {
    var body: some View { Group { Box(name: "pa"); Box(name: "pb") }.padding(2) }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let s = CGSize(width: 100, height: 100)
            _ = host(Counter(tag: "rows") { Rows(tag: "r"); Box(name: "c") }, size: s)
            _ = host(Counter(tag: "nested") { Nested() }, size: s)
            _ = host(Counter(tag: "loopbody") { LoopBody() }, size: s)
            _ = host(Counter(tag: "ifbody-false") { IfBody(show: false); Box(name: "c") }, size: s)
            _ = host(Counter(tag: "ifbody-true") { IfBody(show: true); Box(name: "c") }, size: s)
            _ = host(Counter(tag: "padded-pair") { PaddedPair() }, size: s)
            _ = host(Counter(tag: "foreach-of-rows") { ForEach(0..<2, id: \.self) { Rows(tag: "f\($0)") } }, size: s)
            _ = host(Counter(tag: "rows-padded") { Rows(tag: "r").padding(3) }, size: s)
            _ = host(Counter(tag: "subviews") { Group(subviews: Rows(tag: "s")) { s in ForEach(s) { $0 } } }, size: s)
            spin(0.3)
            measure("hstack of rows", HStack(spacing: 5) { Rows(tag: "r"); Box(name: "c") })
            measure("vstack of rows", VStack(spacing: 5) { Rows(tag: "r"); Box(name: "c") })
            measure("hstack of stateful rows", HStack(spacing: 5) { StatefulRows(tag: "s"); Box(name: "c") })
            measure("hstack of rows padded", HStack(spacing: 5) { Rows(tag: "r").padding(3); Box(name: "c") })
            measure("list of rows", List { Rows(tag: "r"); Box(name: "c") })
            measure("hstack of loopbody", HStack(spacing: 5) { LoopBody() })
            measure("zstack of rows", ZStack { Rows(tag: "r") })
        }
    }
}
