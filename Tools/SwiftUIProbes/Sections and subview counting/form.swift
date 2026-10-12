import SwiftUI
import AppKit

struct Box: View {
    let name: String; var w: CGFloat = 20; var h: CGFloat = 10
    var body: some View { Color.red.frame(width: w, height: h).probe(name) }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let size = CGSize(width: 400, height: 400)
            measure("columns: collapsed section", size: size, Form { Section(isExpanded: .constant(false)) { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.columns))
            measure("columns: expanded section", size: size, Form { Section(isExpanded: .constant(true)) { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.columns))
            measure("grouped: collapsed section", size: size, Form { Section(isExpanded: .constant(false)) { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.grouped))
            measure("grouped: expanded section", size: size, Form { Section(isExpanded: .constant(true)) { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.grouped))
            measure("grouped: if-wrapped section", size: size, Form { Box(name: "top"); if true { Section { Box(name: "row") } header: { Text("Head").probe("head") } } }.formStyle(.grouped))
            measure("grouped: plain section", size: size, Form { Box(name: "top"); Section { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.grouped))
            measure("grouped: group-wrapped section", size: size, Form { Box(name: "top"); Group { Section { Box(name: "row") } header: { Text("Head").probe("head") } } }.formStyle(.grouped))
            measure("columns: if-wrapped section", size: size, Form { Box(name: "top"); if true { Section { Box(name: "row") } header: { Text("Head").probe("head") } } }.formStyle(.columns))
            measure("columns: plain section", size: size, Form { Box(name: "top"); Section { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.columns))
        }
    }
}
