import SwiftUI
import AppKit

struct C: View {
    var body: some View {
        Text("a").tag(5)
        ForEach(10..<12, id: \.self) { Text("\($0)") }
        Text("z")
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            _ = host(Counter(tag: "direct") { C() }, size: CGSize(width: 50, height: 50)); spin(0.2)
            _ = host(Counter(tag: "proxied") { ForEach(subviews: C()) { $0 } }, size: CGSize(width: 50, height: 50)); spin(0.2)
            _ = host(Counter(tag: "proxied-group") { Group(subviews: C()) { s in s[0]; s[1]; s[3] } }, size: CGSize(width: 50, height: 50)); spin(0.2)
            _ = host(Counter(tag: "proxied-collection") { Group(subviews: C()) { s in s } }, size: CGSize(width: 50, height: 50)); spin(0.2)
        }
    }
}
