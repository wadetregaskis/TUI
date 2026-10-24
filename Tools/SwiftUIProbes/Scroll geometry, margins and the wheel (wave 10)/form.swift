import SwiftUI
import AppKit

struct RowY: View {
    let tag: String
    var body: some View {
        Text("row").onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { print(tag, "row global", $0) }
    }
}
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 300, height: 300)
            _ = host(Form { RowY(tag: "columns plain") }, size: sz); spin(0.4)
            _ = host(Form { RowY(tag: "columns top40") }.contentMargins(.top, 40), size: sz); spin(0.4)
            _ = host(Form { RowY(tag: "columns leading40") }.contentMargins(.leading, 40), size: sz); spin(0.4)
            _ = host(Form { RowY(tag: "grouped plain") }.formStyle(.grouped), size: sz); spin(0.4)
            _ = host(Form { RowY(tag: "grouped leading40") }.formStyle(.grouped).contentMargins(.leading, 40), size: sz); spin(0.4)
            _ = host(Form { RowY(tag: "grouped top40 scrollIndicators") }.formStyle(.grouped).contentMargins(.top, 40, for: .scrollIndicators), size: sz); spin(0.4)
        }
    }
}
