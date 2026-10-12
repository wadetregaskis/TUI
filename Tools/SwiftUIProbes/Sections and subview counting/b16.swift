import SwiftUI
import AppKit

struct Box: View {
    let name: String; var w: CGFloat = 20; var h: CGFloat = 10
    var body: some View { Color.red.frame(width: w, height: h).probe(name) }
}

struct Sec: View {
    var body: some View {
        Section { Box(name: "a"); Box(name: "b") } header: { Box(name: "h", w: 30) } footer: { Box(name: "f", w: 40) }
    }
}

struct ZContent: View {
    var body: some View {
        Color.red.frame(width: 30, height: 10).zIndex(1).probe("top")
        Color.blue.frame(width: 30, height: 10).probe("bottom")
    }
}

struct TextSec: View {
    var body: some View {
        Section { Text("Body") } header: { Text("Header").probe("hdr") } footer: { Text("Footer").probe("ftr") }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            measure("vstack spacing 10", VStack(alignment: .leading, spacing: 10) { Box(name: "x"); Sec(); Box(name: "y") })
            measure("hstack spacing 10", HStack(alignment: .top, spacing: 10) { Box(name: "x"); Sec(); Box(name: "y") })
            measure("zstack", ZStack(alignment: .topLeading) { Sec() })
            measure("section alone", Sec())
            measure("section padded in vstack", VStack(alignment: .leading, spacing: 0) { Sec().padding(.leading, 5) })
            measure("lazyvstack spacing 10", LazyVStack(alignment: .leading, spacing: 10) { Sec() })
            measure("lazyhstack spacing 10", LazyHStack(alignment: .top, spacing: 10) { Sec() })
            measure("grid", Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) { GridRow { Box(name: "g0"); Box(name: "g1") }; Sec() })
            measure("isExpanded false in vstack", VStack(alignment: .leading, spacing: 10) { Section("T", isExpanded: .constant(false)) { Box(name: "a") } })
            measure("isExpanded true in vstack", VStack(alignment: .leading, spacing: 10) { Section("T", isExpanded: .constant(true)) { Box(name: "a") } })
            measure("foreach of sections in vstack", VStack(alignment: .leading, spacing: 2) { ForEach(0..<2, id: \.self) { i in Section { Box(name: "a\(i)") } header: { Box(name: "h\(i)", w: 30) } } })
            measure("text section in vstack", VStack(alignment: .leading, spacing: 0) { TextSec() })
            measure("text plain in vstack", VStack(alignment: .leading, spacing: 0) { Text("Header").probe("hdr"); Text("Body"); Text("Footer").probe("ftr") })
            measure("proxied zindex", HStack { ZStack(alignment: .topLeading) { ForEach(subviews: ZContent()) { $0 } } })
            _ = host(Counter(tag: "isExpanded false") { Section("T", isExpanded: .constant(false)) { Text("a"); Text("b") } }, size: CGSize(width: 100, height: 100))
            _ = host(Counter(tag: "isExpanded true") { Section("T", isExpanded: .constant(true)) { Text("a"); Text("b") } }, size: CGSize(width: 100, height: 100))
            _ = host(Counter(tag: "section in group") { Group { Section { Text("a") } header: { Text("h") } } }, size: CGSize(width: 100, height: 100))
            _ = host(Counter(tag: "section empty header") { Section { Text("a") } header: { EmptyView() } }, size: CGSize(width: 100, height: 100))
            spin(0.3)
        }
    }
}
