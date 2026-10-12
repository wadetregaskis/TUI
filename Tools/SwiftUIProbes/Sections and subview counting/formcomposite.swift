import SwiftUI
import AppKit

struct Box: View {
    let name: String; var w: CGFloat = 20; var h: CGFloat = 10
    var body: some View { Color.red.frame(width: w, height: h).probe(name) }
}

/// A form's section as a view of the app's own.
struct General: View {
    var body: some View { Section { Box(name: "row") } header: { Text("Head").probe("head") } }
}

/// Two rows as a view of the app's own: a labelled field and a toggle.
struct Pair: View {
    @State var on = false
    var body: some View {
        LabeledContent { Box(name: "value") } label: { Text("Name").probe("label") }
        Toggle(isOn: $on) { Text("Wi-Fi").probe("toggle") }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let size = CGSize(width: 400, height: 400)
            measure("grouped: plain section", size: size, Form { Box(name: "top"); Section { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.grouped))
            measure("grouped: section of the app's own", size: size, Form { Box(name: "top"); General() }.formStyle(.grouped))
            measure("columns: plain section", size: size, Form { Box(name: "top"); Section { Box(name: "row") } header: { Text("Head").probe("head") } }.formStyle(.columns))
            measure("columns: section of the app's own", size: size, Form { Box(name: "top"); General() }.formStyle(.columns))
            measure("columns: rows bare", size: size, Form { LabeledContent { Box(name: "value") } label: { Text("Name").probe("label") }; Toggle(isOn: .constant(false)) { Text("Wi-Fi").probe("toggle") } }.formStyle(.columns))
            measure("columns: rows of the app's own", size: size, Form { Pair() }.formStyle(.columns))
            measure("grouped: rows bare", size: size, Form { LabeledContent { Box(name: "value") } label: { Text("Name").probe("label") }; Toggle(isOn: .constant(false)) { Text("Wi-Fi").probe("toggle") } }.formStyle(.grouped))
            measure("grouped: rows of the app's own", size: size, Form { Pair() }.formStyle(.grouped))
        }
        exit(0)
    }
}
