import SwiftUI
import AppKit

struct Box: View {
    let name: String; var w: CGFloat = 20; var h: CGFloat = 10
    var body: some View { Color.red.frame(width: w, height: h).probe(name) }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let s = CGSize(width: 100, height: 100)
            _ = host(Counter(tag: "group-rows") { ForEach(0..<2, id: \.self) { i in Group { Box(name: "a\(i)"); Box(name: "b\(i)") } } }, size: s)
            _ = host(Counter(tag: "tuple-rows") { ForEach(0..<2, id: \.self) { i in Box(name: "a\(i)"); Box(name: "b\(i)") } }, size: s)
            _ = host(Counter(tag: "anyview-rows") { ForEach(0..<2, id: \.self) { i in AnyView(Group { Box(name: "a\(i)"); Box(name: "b\(i)") }) } }, size: s)
            _ = host(Counter(tag: "section-rows") { ForEach(0..<2, id: \.self) { i in Section { Box(name: "a\(i)") } header: { Box(name: "h\(i)") } } }, size: s)
            _ = host(Counter(tag: "empty-rows") { ForEach(0..<2, id: \.self) { i in EmptyView() } }, size: s)
            _ = host(Counter(tag: "if-rows") { ForEach(0..<3, id: \.self) { i in if i != 1 { Box(name: "a\(i)"); Box(name: "b\(i)") } } }, size: s)
            _ = host(Counter(tag: "nested-foreach") { ForEach(0..<2, id: \.self) { i in ForEach(0..<3, id: \.self) { j in Box(name: "a\(i)\(j)") } } }, size: s)
            _ = host(Counter(tag: "padded-group-rows") { ForEach(0..<2, id: \.self) { i in Group { Box(name: "a\(i)"); Box(name: "b\(i)") }.padding(3) } }, size: s)
            _ = host(Counter(tag: "tagged-group-rows") { ForEach(0..<2, id: \.self) { i in Group { Box(name: "a\(i)"); Box(name: "b\(i)") }.tag(i + 10) } }, size: s)
            _ = host(Counter(tag: "subviews-of-group-rows") { Group(subviews: Group { ForEach(0..<2, id: \.self) { i in Group { Box(name: "a\(i)"); Box(name: "b\(i)") } } }) { s in ForEach(s) { $0 } } }, size: s)
            _ = host(Counter(tag: "row-with-spacer") { ForEach(0..<2, id: \.self) { i in Box(name: "a\(i)"); Spacer() } }, size: s)
            _ = host(Counter(tag: "row-optional-nil") { ForEach(0..<2, id: \.self) { i in if i == 5 { Box(name: "a\(i)") } } }, size: s)
            spin(0.3)
            measure("hstack of group rows", HStack(spacing: 5) { ForEach(0..<2, id: \.self) { i in Group { Box(name: "a\(i)"); Box(name: "b\(i)") } } })
            measure("vstack of tuple rows", VStack(spacing: 5) { ForEach(0..<2, id: \.self) { i in Box(name: "a\(i)"); Box(name: "b\(i)") } })
            measure("hstack of anyview rows", HStack(spacing: 5) { ForEach(0..<2, id: \.self) { i in AnyView(Group { Box(name: "a\(i)"); Box(name: "b\(i)") }) } })
            measure("hstack of row+spacer", size: CGSize(width: 200, height: 50), HStack(spacing: 5) { ForEach(0..<2, id: \.self) { i in Box(name: "a\(i)"); Spacer() } })
            measure("lazyvstack in scroll of tuple rows", ScrollView { LazyVStack(spacing: 5) { ForEach(0..<3, id: \.self) { i in Box(name: "a\(i)"); Box(name: "b\(i)") } } })
            measure("list of tuple rows", List { ForEach(0..<2, id: \.self) { i in Box(name: "a\(i)"); Box(name: "b\(i)") } })
            measure("zstack of tuple rows", ZStack { ForEach(0..<2, id: \.self) { i in Box(name: "a\(i)", w: 20 + CGFloat(i) * 10); Box(name: "b\(i)", w: 40) } })
            measure("grid of tuple rows", Grid { ForEach(0..<2, id: \.self) { i in GridRow { Box(name: "a\(i)") }; Box(name: "b\(i)") } })
        }
    }
}
